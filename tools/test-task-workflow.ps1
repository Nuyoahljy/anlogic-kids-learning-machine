#Requires -Version 7.5
[CmdletBinding()]
param([string]$OutputRoot = '')
. (Join-Path $PSScriptRoot 'task-common.ps1')
$sourceRoot = Split-Path -Parent $PSScriptRoot
$sourceHead = (Invoke-TaskGit $sourceRoot @('rev-parse', 'HEAD')).Trim()
$sourceChanges = Get-TaskChanges $sourceRoot $sourceHead
$sourceClean = @($sourceChanges.DirtyPaths | Where-Object { -not $_.StartsWith('evidence/workflow-tools/runs/', [StringComparison]::Ordinal) }).Count -eq 0
$sourceHashes = @()
foreach ($name in @('new-task-worktree.ps1', 'task-common.ps1', 'check-task.ps1', 'finish-task.ps1', 'test-task.ps1', 'merge-task.ps1', 'test-task-workflow.ps1')) {
    $sourceHashes += [pscustomobject]@{ Path = "tools/$name"; SHA256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash }
}
if (-not $OutputRoot) { $OutputRoot = Join-Path $sourceRoot 'evidence/workflow-tools/runs' }
$outputFull = [IO.Path]::GetFullPath($OutputRoot)
$permittedRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'evidence/workflow-tools/runs'))
if ($outputFull -ne $permittedRoot -and -not $outputFull.StartsWith($permittedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Regression output must stay in this checkout evidence/workflow-tools/runs.' }
Assert-NoTaskLink $outputFull
$runRoot = Join-Path $outputFull ('regression-' + [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $runRoot
$script:cases = @()
$script:invocationCount = 0

function Write-FixtureFile {
    param([string]$Path, [string]$Text)
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($runRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture write escaped its run.' }
    Assert-NoTaskLink $absolute
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $absolute) -Force
    [IO.File]::WriteAllText($absolute, $Text, [Text.UTF8Encoding]::new($false))
}

function Remove-FixtureFile {
    param([string]$Path)
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($runRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw 'Fixture removal must be a file inside its run.' }
    Assert-NoTaskLink $absolute
    Remove-Item -LiteralPath $absolute
}

function Assert-Case {
    param([string]$Name, [bool]$Condition)
    $script:cases += [pscustomobject]@{ Name = $Name; Passed = $Condition }
    if (-not $Condition) { throw "REGRESSION FAILED: $Name" }
}

function Invoke-FixtureScript {
    param([string]$Name, [string]$Root, [string[]]$Arguments = @())
    $script:invocationCount++
    $result = Invoke-TaskProcess 'pwsh' (@('-NoProfile', '-File', (Join-Path $PSScriptRoot $Name), '-RepoRoot', $Root, '-TaskId', 'demo') + $Arguments) $Root
    Write-FixtureFile (Join-Path $runRoot ("command-$script:invocationCount.json")) ([ordered]@{ Script = $Name; Root = $Root; Arguments = $Arguments; ExitCode = $result.ExitCode; Stdout = $result.Stdout; Stderr = $result.Stderr } | ConvertTo-Json -Depth 10)
    return $result
}

function New-Fixture {
    param([string]$Name, [string]$Executable = 'pwsh', [int]$ExitCode = 0, [int]$Expected = 0, [string[]]$EvidencePaths = @('fpga/allowed.v'), [switch]$Mutate)
    $folder = Join-Path $runRoot $Name
    $primary = Join-Path $folder 'repo'
    $trees = Join-Path $folder 'trees'
    $null = New-Item -ItemType Directory -Path $primary
    $null = Invoke-TaskGit $primary @('init', '-b', 'main')
    $null = Invoke-TaskGit $primary @('config', 'user.name', 'Workflow regression')
    $null = Invoke-TaskGit $primary @('config', 'user.email', 'workflow-regression@example.invalid')
    $null = Invoke-TaskGit $primary @('config', 'core.autocrlf', 'false')
    $null = Invoke-TaskGit $primary @('config', 'commit.gpgsign', 'false')
    $null = Invoke-TaskGit $primary @('config', 'core.hooksPath', (Join-Path $folder 'no-hooks'))
    $card = [ordered]@{ TaskId = 'demo'; Owner = 'tester'; Role = 'worker'; AllowedPaths = @('fpga/allowed.v', 'fpga/new.v', 'fpga/moved.v', 'fpga/scope/', 'AGENTS.md', 'docs/', 'memory/branches/demo.md', 'memory/tasks/demo.json', 'evidence/demo/'); RequiredChecks = @('probe'); Checks = @([ordered]@{ Id = 'probe'; Executable = $Executable; Arguments = @('-NoProfile', '-File', 'tools/probe.ps1', '-ExitCode', [string]$ExitCode); ExpectedExitCode = $Expected; EvidencePaths = $EvidencePaths }) }
    Write-FixtureFile (Join-Path $primary 'memory/tasks/demo.json') ($card | ConvertTo-Json -Depth 20)
    Write-FixtureFile (Join-Path $primary 'memory/branches/demo.md') "# demo`n- 任务 ID：demo`n- 状态：待启动`n- 负责人：tester`n- 分支：task/demo`n- 基础提交：pending`n- 开始时间：pending`n- 结束时间：pending`n"
    Write-FixtureFile (Join-Path $primary '.gitignore') "evidence/*/runs/`n"
    Write-FixtureFile (Join-Path $primary 'fpga/allowed.v') "module allowed; endmodule`n"
    Write-FixtureFile (Join-Path $primary 'denied.v') "module denied; endmodule`n"
    Write-FixtureFile (Join-Path $primary 'AGENTS.md') "coordinator only`n"
    Write-FixtureFile (Join-Path $primary 'tools/probe.ps1') ('param([int]$ExitCode = 0)' + "`nWrite-Output 'PASS'`n" + $(if ($Mutate) { "[IO.File]::AppendAllText('fpga/allowed.v', 'dirty')`n" } else { '' }) + 'exit $ExitCode')
    Write-FixtureFile (Join-Path $primary 'tools/update-workspace-index.ps1') 'param([string]$WorkspaceRoot, [switch]$Check); if (-not $Check -or -not (Test-Path -LiteralPath $WorkspaceRoot)) { exit 9 }; exit 0'
    $null = Invoke-TaskGit $primary @('add', '--', '.gitignore', 'memory/tasks/demo.json', 'memory/branches/demo.md', 'fpga/allowed.v', 'denied.v', 'AGENTS.md', 'tools/probe.ps1', 'tools/update-workspace-index.ps1')
    $null = Invoke-TaskGit $primary @('commit', '-m', 'fixture baseline')
    return [pscustomobject]@{ Primary = $primary; Trees = $trees; Worker = (Join-Path $trees 'demo'); Workspace = $folder; Card = $card; BaseHead = (Invoke-TaskGit $primary @('rev-parse', 'HEAD')).Trim() }
}

function Start-Fixture {
    param($Fixture)
    $result = Invoke-FixtureScript 'new-task-worktree.ps1' $Fixture.Primary @('-WorktreeRoot', $Fixture.Trees)
    if ($result.ExitCode -ne 0) { throw "Fixture start failed: $($result.Stderr)" }
}

function Set-FixtureReady {
    param($Fixture)
    $path = Join-Path $Fixture.Worker 'memory/branches/demo.md'
    $text = (Get-Content -LiteralPath $path -Raw).Replace('- 状态：进行中', '- 状态：等待主对话审核')
    Write-FixtureFile $path $text
    $null = Invoke-TaskGit $Fixture.Worker @('add', '--', 'memory/branches/demo.md')
    $null = Invoke-TaskGit $Fixture.Worker @('commit', '-m', 'ready for review')
}

function Get-FixtureSnapshot {
    param([string]$Root)
    $index = (Invoke-TaskGit $Root @('rev-parse', '--path-format=absolute', '--git-path', 'index')).Trim()
    return (@((Invoke-TaskGit $Root @('rev-parse', 'HEAD')), (Invoke-TaskGit $Root @('status', '--porcelain=v1', '--untracked-files=all')), (Invoke-TaskGit $Root @('for-each-ref', '--format=%(refname) %(objectname)')), (Invoke-TaskGit $Root @('worktree', 'list', '--porcelain')), (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash) -join "`n")
}

$failure = $null
try {
    $fixture = New-Fixture 'core'
    $baseLog = Get-Content -LiteralPath (Join-Path $fixture.Primary 'memory/branches/demo.md') -Raw
    $before = Get-FixtureSnapshot $fixture.Primary
    $whatIf = Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Primary @('-WorktreeRoot', $fixture.Trees, '-WhatIf')
    Assert-Case 'new WhatIf exits zero and changes nothing' ($whatIf.ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Primary) -ceq $before -and -not (Test-Path -LiteralPath $fixture.Trees))
    $wrongBranch = Invoke-FixtureScript 'check-task.ps1' $fixture.Primary @('-Json')
    Assert-Case 'check rejects main and reports actual HEAD' ($wrongBranch.ExitCode -ne 0 -and ($wrongBranch.Stdout | ConvertFrom-Json).Head -ceq $fixture.BaseHead)
    Write-FixtureFile (Join-Path $fixture.Primary 'untracked.txt') 'dirty'
    Assert-Case 'new rejects dirty base' ((Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Primary @('-WorktreeRoot', $fixture.Trees)).ExitCode -ne 0)
    Remove-FixtureFile (Join-Path $fixture.Primary 'untracked.txt')
    Assert-Case 'new rejects traversal task root' ((Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Primary @('-WorktreeRoot', (Join-Path $fixture.Primary 'unsafe'))).ExitCode -ne 0)
    Assert-Case 'new rejects mismatching owner' ((Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Primary @('-WorktreeRoot', $fixture.Trees, '-Owner', 'another')).ExitCode -ne 0)
    Start-Fixture $fixture
    Assert-Case 'startup commit changes child HEAD only' ((Invoke-TaskGit $fixture.Worker @('rev-parse', 'HEAD')).Trim() -cne $fixture.BaseHead -and (Invoke-TaskGit $fixture.Primary @('rev-parse', 'HEAD')).Trim() -ceq $fixture.BaseHead)
    Assert-Case 'base working files and status unchanged' ((Get-Content -LiteralPath (Join-Path $fixture.Primary 'memory/branches/demo.md') -Raw) -ceq $baseLog -and (Invoke-TaskGit $fixture.Primary @('status', '--porcelain=v1')).Length -eq 0)
    Assert-Case 'startup commit contains only child log' ((Invoke-TaskGit $fixture.Worker @('diff', '--name-only', 'HEAD^', 'HEAD')).Trim() -ceq 'memory/branches/demo.md')
    Assert-Case 'new rejects existing branch' ((Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Primary @('-WorktreeRoot', $fixture.Trees)).ExitCode -ne 0)
    Assert-Case 'new rejects task checkout as base' ((Invoke-FixtureScript 'new-task-worktree.ps1' $fixture.Worker @('-WorktreeRoot', $fixture.Trees)).ExitCode -ne 0)
    $before = Get-FixtureSnapshot $fixture.Worker
    Assert-Case 'check accepts legal committed startup and is readonly' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-Json')).ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    Assert-Case 'ready check fails before review state' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-RequireReady')).ExitCode -ne 0)
    Assert-Case 'missing PolicyRef fails closed' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-PolicyRef', 'missing-policy')).ExitCode -ne 0)
    Assert-Case 'missing BaseBranch fails closed' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-BaseBranch', 'missing-base')).ExitCode -ne 0)
    Assert-Case 'own branch cannot authorize policy' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-PolicyRef', 'task/demo')).ExitCode -ne 0)
    Write-FixtureFile (Join-Path $fixture.Worker 'fpga/allowed.v') 'legal unstaged'
    Assert-Case 'legal unstaged accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    Assert-Case 'test rejects dirty source before creating report' ((Invoke-FixtureScript 'test-task.ps1' $fixture.Worker).ExitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $fixture.Worker 'evidence/demo/runs')))
    $null = Invoke-TaskGit $fixture.Worker @('add', '--', 'fpga/allowed.v')
    Assert-Case 'legal staged accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    $null = Invoke-TaskGit $fixture.Worker @('commit', '-m', 'legal change')
    Assert-Case 'legal committed accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    Write-FixtureFile (Join-Path $fixture.Worker 'fpga/new.v') 'new allowed'
    Assert-Case 'legal untracked accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    Remove-FixtureFile (Join-Path $fixture.Worker 'fpga/new.v')
    Write-FixtureFile (Join-Path $fixture.Worker 'denied.v') 'outside unstaged'
    Assert-Case 'unauthorized unstaged rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('add', '--', 'denied.v')
    Assert-Case 'unauthorized staged rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('restore', '--staged', '--worktree', '--', 'denied.v')
    Write-FixtureFile (Join-Path $fixture.Worker 'outside.txt') 'outside untracked'
    Assert-Case 'unauthorized untracked rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    Remove-FixtureFile (Join-Path $fixture.Worker 'outside.txt')
    Remove-FixtureFile (Join-Path $fixture.Worker 'fpga/allowed.v')
    Assert-Case 'legal deletion accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    $null = Invoke-TaskGit $fixture.Worker @('restore', '--worktree', '--', 'fpga/allowed.v')
    Remove-FixtureFile (Join-Path $fixture.Worker 'denied.v')
    Assert-Case 'unauthorized deletion rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('restore', '--worktree', '--', 'denied.v')
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'fpga/allowed.v', 'fpga/moved.v')
    Assert-Case 'legal staged rename accepted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -eq 0)
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'fpga/moved.v', 'fpga/allowed.v')
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'denied.v', 'fpga/new.v')
    Assert-Case 'rename source outside allowlist rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'fpga/new.v', 'denied.v')
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'fpga/allowed.v', 'outside.v')
    Assert-Case 'rename destination outside allowlist rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('mv', '--', 'outside.v', 'fpga/allowed.v')
    Write-FixtureFile (Join-Path $fixture.Worker 'AGENTS.md') 'forbidden despite allowlist'
    Assert-Case 'worker cannot change coordinator file even if allowlisted' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('restore', '--worktree', '--', 'AGENTS.md')
    $cardPath = Join-Path $fixture.Worker 'memory/tasks/demo.json'
    $cardText = Get-Content -LiteralPath $cardPath -Raw
    $expanded = $cardText | ConvertFrom-Json
    $expanded.AllowedPaths += 'denied.v'
    Write-FixtureFile $cardPath ($expanded | ConvertTo-Json -Depth 20)
    Assert-Case 'task card cannot expand its own permissions' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    Write-FixtureFile $cardPath $cardText
    $logPath = Join-Path $fixture.Worker 'memory/branches/demo.md'
    $logText = Get-Content -LiteralPath $logPath -Raw
    Remove-FixtureFile $logPath
    Assert-Case 'missing task log rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker).ExitCode -ne 0)
    Write-FixtureFile $logPath $logText
    foreach ($unsafe in @('../escape', '/absolute', 'C:/absolute', 'fpga/*.v', 'fpga/../denied.v', 'fpga\\file', 'fpga/file.', '.git/config', 'fpga/NUL')) {
        $rejected = $false
        try { Assert-TaskPath $unsafe } catch { $rejected = $true }
        Assert-Case "unsafe path rejected: $unsafe" $rejected
    }
    Assert-Case 'directory prefix does not permit different case' (-not (Test-TaskAllowed 'FPGA/scope/file.v' ([pscustomobject]$fixture.Card)))
    Assert-Case 'directory prefix does not permit sibling lookalike' (-not (Test-TaskAllowed 'fpga/scope-sibling/file.v' ([pscustomobject]$fixture.Card)))
    Set-FixtureReady $fixture
    Write-FixtureFile (Join-Path $fixture.Worker 'fpga/allowed.v') 'finish change'
    $before = Get-FixtureSnapshot $fixture.Worker
    Assert-Case 'finish without Commit has no Git side effect' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker).ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    Assert-Case 'finish Commit requires index Check' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker @('-Commit')).ExitCode -ne 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    $finishArguments = @('-Commit', '-WorkspaceRoot', $fixture.Workspace, '-IndexScript', (Join-Path $fixture.Primary 'tools/update-workspace-index.ps1'))
    $indexScript = Join-Path $fixture.Primary 'tools/update-workspace-index.ps1'
    $indexText = Get-Content -LiteralPath $indexScript -Raw
    Write-FixtureFile $indexScript 'param([string]$WorkspaceRoot, [switch]$Check); exit 3'
    Assert-Case 'failed shared index Check blocks commit' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker $finishArguments).ExitCode -ne 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    Write-FixtureFile $indexScript $indexText
    Assert-Case 'finish WhatIf does not stage or commit' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker ($finishArguments + '-WhatIf')).ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    Assert-Case 'finish Commit stages exact approved files' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker $finishArguments).ExitCode -eq 0 -and (Invoke-TaskGit $fixture.Worker @('diff', '--name-only', 'HEAD^', 'HEAD')).Trim() -ceq 'fpga/allowed.v')
    $before = Get-FixtureSnapshot $fixture.Worker
    Assert-Case 'finish already committed succeeds without new commit' ((Invoke-FixtureScript 'finish-task.ps1' $fixture.Worker $finishArguments).ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    $positive = Invoke-FixtureScript 'test-task.ps1' $fixture.Worker
    Assert-Case 'real command exit zero generates passing report' ($positive.ExitCode -eq 0)
    $reportPath = ($positive.Stdout | ConvertFrom-Json).Report
    $reportText = Get-Content -LiteralPath $reportPath -Raw
    $report = $reportText | ConvertFrom-Json -Depth 40
    $before = Get-FixtureSnapshot $fixture.Worker
    Assert-Case 'acceptance report verifies and check stays readonly' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-RequireReady', '-AcceptanceReport', $reportPath, '-Json')).ExitCode -eq 0 -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    $artifact = Join-Path $fixture.Worker $report.Checks[0].Artifacts[0].Path
    $artifactText = Get-Content -LiteralPath $artifact -Raw
    Write-FixtureFile $artifact 'tampered'
    Assert-Case 'tampered evidence hash rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath)).ExitCode -ne 0)
    Write-FixtureFile $artifact $artifactText
    $report.Head = '0000000000000000000000000000000000000000'
    Write-FixtureFile $reportPath ($report | ConvertTo-Json -Depth 40)
    Assert-Case 'report HEAD mismatch rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath)).ExitCode -ne 0)
    $report = $reportText | ConvertFrom-Json -Depth 40
    $report.Checks[0].ExitCode = 1
    Write-FixtureFile $reportPath ($report | ConvertTo-Json -Depth 40)
    Assert-Case 'reported nonzero exit cannot masquerade as passed' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath)).ExitCode -ne 0)
    $report = $reportText | ConvertFrom-Json -Depth 40
    $report.Checks = @()
    Write-FixtureFile $reportPath ($report | ConvertTo-Json -Depth 40)
    Assert-Case 'missing check rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath)).ExitCode -ne 0)
    $report = $reportText | ConvertFrom-Json -Depth 40
    $report.Checks[0].Artifacts[0].Path = 'evidence/demo/runs/absent.txt'
    Write-FixtureFile $reportPath ($report | ConvertTo-Json -Depth 40)
    Assert-Case 'missing evidence file rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath)).ExitCode -ne 0)
    Write-FixtureFile $reportPath $reportText
    Assert-Case 'missing report rejected' ((Invoke-FixtureScript 'check-task.ps1' $fixture.Worker @('-AcceptanceReport', 'evidence/demo/runs/no-report.json')).ExitCode -ne 0)
    Assert-Case 'merge without known origin fails closed' ((Invoke-FixtureScript 'merge-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath, '-PullRequestUrl', 'https://github.com/fixture/repo/pull/1')).ExitCode -ne 0)
    $null = Invoke-TaskGit $fixture.Worker @('remote', 'add', 'origin', 'https://github.com/fixture/repo.git')
    $before = Get-FixtureSnapshot $fixture.Worker
    $merge = Invoke-FixtureScript 'merge-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath, '-PullRequestUrl', 'https://github.com/fixture/repo/pull/1')
    $mergeResult = $merge.Stdout | ConvertFrom-Json
    Assert-Case 'merge only emits SHA-pinned command and never mutates' ($merge.ExitCode -eq 0 -and -not $mergeResult.Executed -and $mergeResult.Mode -ceq 'LocalPreflightOnly' -and $mergeResult.CommandAfterIndependentVerification.Contains('--match-head-commit') -and (Get-FixtureSnapshot $fixture.Worker) -ceq $before)
    Assert-Case 'merge rejects another repository PR' ((Invoke-FixtureScript 'merge-task.ps1' $fixture.Worker @('-AcceptanceReport', $reportPath, '-PullRequestUrl', 'https://github.com/other/repo/pull/1')).ExitCode -ne 0)
    foreach ($scenario in @('exit-one', 'expected-failure', 'missing-tool', 'missing-evidence', 'mutated-source')) {
        $exitCode = if ($scenario -in @('exit-one', 'expected-failure')) { 1 } else { 0 }
        $expected = if ($scenario -eq 'expected-failure') { 1 } else { 0 }
        $executable = if ($scenario -eq 'missing-tool') { 'not-installed-workflow-tool-123456' } else { 'pwsh' }
        $evidence = if ($scenario -eq 'missing-evidence') { @('fpga/missing.v') } else { @('fpga/allowed.v') }
        $negative = New-Fixture $scenario -Executable $executable -ExitCode $exitCode -Expected $expected -EvidencePaths $evidence -Mutate:($scenario -eq 'mutated-source')
        Start-Fixture $negative
        $execution = Invoke-FixtureScript 'test-task.ps1' $negative.Worker
        $negativeReport = Get-Content -LiteralPath (($execution.Stdout | ConvertFrom-Json).Report) -Raw | ConvertFrom-Json -Depth 40
        $status = switch ($scenario) { 'exit-one' { 'unexpected_exit' }; 'expected-failure' { 'expected_failure' }; 'missing-tool' { 'missing_tool' }; 'missing-evidence' { 'missing_evidence' }; 'mutated-source' { 'passed' } }
        Assert-Case "$scenario has explicit status, not PASS-string inference" ($negativeReport.Checks[0].Status -ceq $status -and (($execution.ExitCode -eq 0) -eq ($scenario -eq 'expected-failure')))
        if ($scenario -eq 'mutated-source') { Assert-Case 'source modified by test cannot attest HEAD' (-not $negativeReport.SourceClean -and $negativeReport.Overall -ceq 'failed') }
    }
    $committed = New-Fixture 'committed-violation'
    Start-Fixture $committed
    Write-FixtureFile (Join-Path $committed.Worker 'denied.v') 'committed outside ownership'
    $null = Invoke-TaskGit $committed.Worker @('add', '--', 'denied.v')
    $null = Invoke-TaskGit $committed.Worker @('commit', '-m', 'unauthorized fixture change')
    Assert-Case 'unauthorized committed change rejected' ((Invoke-FixtureScript 'check-task.ps1' $committed.Worker).ExitCode -ne 0)
    $null = Invoke-TaskGit $committed.Worker @('mv', '--', 'denied.v', 'fpga/new.v')
    $null = Invoke-TaskGit $committed.Worker @('commit', '-m', 'rename from forbidden source')
    Assert-Case 'committed rename includes forbidden old path' ((Invoke-FixtureScript 'check-task.ps1' $committed.Worker).ExitCode -ne 0)
    $split = New-Fixture 'approved-policy-separate-from-main'
    Start-Fixture $split
    $null = Invoke-TaskGit $split.Primary @('switch', '-c', 'approved-policy')
    $approved = $split.Card
    $approved.AllowedPaths += 'denied.v'
    $approvedText = $approved | ConvertTo-Json -Depth 20
    Write-FixtureFile (Join-Path $split.Primary 'memory/tasks/demo.json') $approvedText
    $null = Invoke-TaskGit $split.Primary @('add', '--', 'memory/tasks/demo.json')
    $null = Invoke-TaskGit $split.Primary @('commit', '-m', 'coordinator policy approval fixture')
    $policySha = (Invoke-TaskGit $split.Primary @('rev-parse', 'HEAD')).Trim()
    $null = Invoke-TaskGit $split.Primary @('switch', 'main')
    Write-FixtureFile (Join-Path $split.Worker 'memory/tasks/demo.json') $approvedText
    Write-FixtureFile (Join-Path $split.Worker 'denied.v') 'now explicitly approved by different policy commit'
    Assert-Case 'default policy cannot use future approved permissions implicitly' ((Invoke-FixtureScript 'check-task.ps1' $split.Worker).ExitCode -ne 0)
    Assert-Case 'explicit approved policy SHA separates authorization from main diff' ((Invoke-FixtureScript 'check-task.ps1' $split.Worker @('-PolicyRef', $policySha, '-BaseBranch', 'main')).ExitCode -eq 0)
    $null = Invoke-TaskGit $split.Worker @('add', '--', 'memory/tasks/demo.json', 'denied.v')
    $null = Invoke-TaskGit $split.Worker @('commit', '-m', 'use approved task permissions')
    $splitTest = Invoke-FixtureScript 'test-task.ps1' $split.Worker @('-PolicyRef', $policySha, '-BaseBranch', 'main')
    Assert-Case 'test uses approved policy SHA with independent diff base' ($splitTest.ExitCode -eq 0)
    $splitReport = ($splitTest.Stdout | ConvertFrom-Json).Report
    Assert-Case 'report validates against same approved policy SHA' ((Invoke-FixtureScript 'check-task.ps1' $split.Worker @('-PolicyRef', $policySha, '-BaseBranch', 'main', '-AcceptanceReport', $splitReport)).ExitCode -eq 0)
    $missing = New-Fixture 'missing-base-card'
    Remove-FixtureFile (Join-Path $missing.Primary 'memory/tasks/demo.json')
    $null = Invoke-TaskGit $missing.Primary @('add', '--', 'memory/tasks/demo.json')
    $null = Invoke-TaskGit $missing.Primary @('commit', '-m', 'remove policy fixture')
    Assert-Case 'new fails when base card missing' ((Invoke-FixtureScript 'new-task-worktree.ps1' $missing.Primary @('-WorktreeRoot', $missing.Trees)).ExitCode -ne 0)
    $missingLog = New-Fixture 'missing-base-log'
    Remove-FixtureFile (Join-Path $missingLog.Primary 'memory/branches/demo.md')
    $null = Invoke-TaskGit $missingLog.Primary @('add', '--', 'memory/branches/demo.md')
    $null = Invoke-TaskGit $missingLog.Primary @('commit', '-m', 'remove log fixture')
    Assert-Case 'new fails when base log missing' ((Invoke-FixtureScript 'new-task-worktree.ps1' $missingLog.Primary @('-WorktreeRoot', $missingLog.Trees)).ExitCode -ne 0)
}
catch { $failure = $_.Exception.Message }
foreach ($source in $sourceHashes) {
    if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $source.Path) -Algorithm SHA256).Hash -cne $source.SHA256) { $failure = 'Source script changed during regression.' }
}
if ((Invoke-TaskGit $sourceRoot @('rev-parse', 'HEAD')).Trim() -cne $sourceHead) { $failure = 'Source HEAD changed during regression.' }
$summary = [ordered]@{ FinishedAt = (Get-TaskTime); Passed = ($null -eq $failure); SourceHead = $sourceHead; SourceClean = $sourceClean; SourceScriptHashes = $sourceHashes; CaseCount = $script:cases.Count; Cases = $script:cases; Error = $failure; RunDirectory = $runRoot; Cleanup = 'Preserved; no recursive deletion'; TestScope = 'Temporary Git repositories only; no network, TD or ModelSim' }
$summaryPath = Join-Path $runRoot 'summary.json'
Write-FixtureFile $summaryPath ($summary | ConvertTo-Json -Depth 20)
[pscustomobject]@{ Passed = $summary.Passed; CaseCount = $summary.CaseCount; Summary = $summaryPath; Error = $failure } | ConvertTo-Json
if ($failure) { exit 1 }
