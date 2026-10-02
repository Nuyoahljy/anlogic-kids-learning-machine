#Requires -Version 7.5
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-TaskProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['GIT_OPTIONAL_LOCKS'] = '0'
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Cannot start $Executable" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.GetAwaiter().GetResult(); Stderr = $stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Invoke-TaskGit {
    param([string]$Root, [string[]]$Arguments)
    $result = Invoke-TaskProcess 'git' (@('-C', $Root, '--literal-pathspecs') + $Arguments) $Root
    if ($result.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed ($($result.ExitCode)): $($result.Stderr)" }
    return $result.Stdout
}

function Assert-TaskId {
    param([string]$TaskId)
    if ($TaskId -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $TaskId -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { throw "Invalid TaskId: $TaskId" }
}

function Assert-TaskPath {
    param([string]$Path, [switch]$DirectoryAllowed)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.StartsWith('/') -or ($Path.EndsWith('/') -and -not $DirectoryAllowed)) { throw "Invalid relative path: $Path" }
    foreach ($segment in $Path.TrimEnd('/').Split('/')) {
        if ($segment -cnotmatch '^[A-Za-z0-9_.-]+$' -or $segment -in @('.', '..') -or $segment.EndsWith('.') -or $segment -ieq '.git' -or $segment -imatch '^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\.|$)') { throw "Unsafe path: $Path" }
    }
}

function Assert-NoTaskLink {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Links/reparse points are not allowed: $current" }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-TaskFile {
    param([string]$Root, [string]$Path, [switch]$DirectoryAllowed)
    Assert-TaskPath $Path -DirectoryAllowed:$DirectoryAllowed
    $current = $Root
    foreach ($segment in $Path.TrimEnd('/').Split('/')) {
        if (Test-Path -LiteralPath $current -PathType Container) {
            $matching = @(Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $segment })
            if ($matching.Count -gt 0 -and ($matching.Count -ne 1 -or $matching[0].Name -cne $segment)) { throw "Path casing mismatch: $Path" }
        }
        $current = Join-Path $current $segment
        Assert-NoTaskLink $current
    }
    return $current
}

function Get-TaskRoot {
    param([string]$Root)
    $full = (Resolve-Path -LiteralPath $Root).Path
    Assert-NoTaskLink $full
    $actual = (Invoke-TaskGit $full @('rev-parse', '--show-toplevel')).Trim()
    if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($full)) { throw 'RepoRoot must be the checkout root.' }
    return $full
}

function Test-TaskAllowed {
    param([string]$Path, $Card)
    foreach ($allowed in $Card.AllowedPaths) {
        if ($allowed.EndsWith('/')) {
            if ($Path.StartsWith($allowed, [StringComparison]::Ordinal)) { return $true }
        }
        elseif ($Path -ceq $allowed) { return $true }
    }
    return $false
}

function Assert-TaskOwned {
    param([string]$Path, $Card)
    Assert-TaskPath $Path -DirectoryAllowed
    if (-not (Test-TaskAllowed $Path $Card)) { throw "Outside AllowedPaths: $Path" }
    if ($Card.Role -ceq 'worker') {
        if ($Path -imatch '^(AGENTS\.md|PROJECT_MEMORY\.md|PLAN\.md|TASKS\.md|DECISIONS\.md|CHANGELOG\.md)$|^docs/') { throw "Coordinator-only file: $Path" }
        foreach ($section in @('branches', 'tasks')) {
            $own = if ($section -eq 'branches') { "memory/branches/$($Card.TaskId).md" } else { "memory/tasks/$($Card.TaskId).json" }
            if ($Path.StartsWith("memory/$section/", [StringComparison]::OrdinalIgnoreCase) -and $Path -cne $own) { throw "Another task's metadata: $Path" }
        }
        if ($Path.StartsWith('evidence/', [StringComparison]::OrdinalIgnoreCase) -and -not $Path.StartsWith("evidence/$($Card.TaskId)/", [StringComparison]::Ordinal)) { throw "Another task's evidence: $Path" }
    }
}

function Get-TaskPolicy {
    param([string]$Root, [string]$TaskId, [string]$BaseBranch, [string]$PolicyRef)
    Assert-TaskId $TaskId
    if (-not $PolicyRef) { $PolicyRef = $BaseBranch }
    if ($BaseBranch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_./-]*$' -or $BaseBranch.Contains('..') -or $BaseBranch -ieq "task/$TaskId") { throw "Invalid or self-authorizing base branch: $BaseBranch" }
    $baseCommit = (Invoke-TaskGit $Root @('rev-parse', '--verify', "refs/heads/$BaseBranch^{commit}")).Trim()
    if ($PolicyRef -ceq $BaseBranch) { $policyCommit = $baseCommit }
    else {
        if ($PolicyRef -cnotmatch '^([a-fA-F0-9]{40}|[a-fA-F0-9]{64})$') { throw 'Explicit PolicyRef must be a full coordinator-approved commit SHA, not HEAD or a task branch.' }
        $policyCommit = (Invoke-TaskGit $Root @('rev-parse', '--verify', "$PolicyRef^{commit}")).Trim()
    }
    $cardPath = "memory/tasks/$TaskId.json"
    $raw = Invoke-TaskGit $Root @('show', "${policyCommit}:$cardPath")
    $card = $raw | ConvertFrom-Json -Depth 30
    foreach ($field in @('TaskId', 'Owner', 'Role', 'AllowedPaths', 'RequiredChecks', 'Checks')) {
        if ($null -eq $card.PSObject.Properties[$field] -or $card.PSObject.Properties[$field].Name -cne $field) { throw "Missing/exact-case policy field: $field" }
    }
    if ($card.TaskId -cne $TaskId -or $card.Owner -isnot [string] -or [string]::IsNullOrWhiteSpace($card.Owner) -or $card.Owner -match '[\r\n]' -or $card.Role -cnotin @('worker', 'coordinator')) { throw 'Invalid policy identity/role.' }
    foreach ($field in @('AllowedPaths', 'RequiredChecks', 'Checks')) { if ($card.$field -isnot [array]) { throw "$field must be an array." } }
    if ($card.AllowedPaths.Count -eq 0) { throw 'AllowedPaths is empty.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $card.AllowedPaths) {
        if ($path -isnot [string]) { throw 'AllowedPaths must contain strings.' }
        Assert-TaskPath $path -DirectoryAllowed
        if (-not $seen.Add($path)) { throw "Duplicate/case-colliding permission: $path" }
    }
    $checkIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($check in $card.Checks) {
        Assert-TaskId $check.Id
        if (-not $checkIds.Add($check.Id) -or $check.Executable -isnot [string] -or [string]::IsNullOrWhiteSpace($check.Executable) -or $check.Executable -match '[\r\n]' -or $check.Arguments -isnot [array]) { throw 'Invalid check command.' }
        foreach ($argument in $check.Arguments) { if ($argument -isnot [string]) { throw 'Arguments must be a string array.' } }
        if ($null -eq $check.PSObject.Properties['ExpectedExitCode']) { $check | Add-Member -NotePropertyName ExpectedExitCode -NotePropertyValue 0 }
        if ($check.ExpectedExitCode -isnot [int] -and $check.ExpectedExitCode -isnot [long]) { throw 'ExpectedExitCode must be an integer.' }
        if ($null -eq $check.PSObject.Properties['EvidencePaths']) { $check | Add-Member -NotePropertyName EvidencePaths -NotePropertyValue @() }
        if ($check.EvidencePaths -isnot [array]) { throw 'EvidencePaths must be an array.' }
        foreach ($path in $check.EvidencePaths) { Assert-TaskPath $path }
    }
    $requiredIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($required in $card.RequiredChecks) {
        if ($required -isnot [string] -or -not $checkIds.Contains($required) -or -not $requiredIds.Add($required)) { throw "Missing/duplicate RequiredCheck: $required" }
    }
    $ownCard = Get-TaskFile $Root $cardPath
    if (-not (Test-Path -LiteralPath $ownCard -PathType Leaf)) { throw "Missing task card: $cardPath" }
    $local = Get-Content -LiteralPath $ownCard -Raw | ConvertFrom-Json -Depth 30
    $trusted = $raw | ConvertFrom-Json -Depth 30
    if (($local | ConvertTo-Json -Depth 30 -Compress) -cne ($trusted | ConvertTo-Json -Depth 30 -Compress)) { throw 'Local task card differs from trusted policy; approve changes in PolicyRef first.' }
    return [pscustomobject]@{ Card = $card; BaseCommit = $baseCommit; PolicyCommit = $policyCommit; PolicyRef = $PolicyRef; CardBlob = (Invoke-TaskGit $Root @('rev-parse', "${policyCommit}:$cardPath")).Trim() }
}

function Get-TaskChanges {
    param([string]$Root, [string]$BaseCommit)
    $status = Invoke-TaskGit $Root @('status', '--porcelain=v1', '-z', '--untracked-files=all')
    $entries = @($status.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
    $dirty = @()
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $dirty += $entry.Substring(3)
        if ($entry.Substring(0, 2) -match '[RC]') { $index++; $dirty += $entries[$index] }
        if ($entry.Substring(0, 2) -match 'U|AA|DD') { throw 'Unmerged Git index.' }
    }
    $committed = Invoke-TaskGit $Root @('diff', '--name-only', '--no-renames', '-z', "$BaseCommit...HEAD", '--')
    $paths = @(@($committed.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) + $dirty | Sort-Object -Unique -CaseSensitive)
    return [pscustomobject]@{ Paths = $paths; DirtyPaths = @($dirty | Sort-Object -Unique -CaseSensitive); Status = $status.Replace([string][char]0, "`n") }
}

function Assert-TaskLog {
    param([string]$Root, [string]$TaskId, [switch]$RequireReady)
    $path = Get-TaskFile $Root "memory/branches/$TaskId.md"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Missing task log.' }
    $log = Get-Content -LiteralPath $path -Raw
    foreach ($field in @('任务 ID', '状态', '负责人', '分支', '基础提交', '开始时间', '结束时间')) {
        if ([regex]::Matches($log, "(?m)^- ${field}：[^\r\n]+\r?$").Count -ne 1) { throw "Missing/ambiguous log field: $field" }
    }
    if ($log -cnotmatch "(?m)^- 任务 ID：$([regex]::Escape($TaskId))\r?$" -or $log -cnotmatch "(?m)^- 分支：task/$([regex]::Escape($TaskId))\r?$") { throw 'Task log identity mismatch.' }
    $state = [regex]::Match($log, '(?m)^- 状态：([^\r\n]+)\r?$').Groups[1].Value
    if ($state -cnotin @('待启动', '进行中', '等待主对话审核', '已合并', '阻塞', '取消')) { throw 'Invalid task log state.' }
    if ($RequireReady -and $state -cne '等待主对话审核') { throw 'Task is not ready for coordinator review.' }
    return $state
}

function Get-TaskContext {
    param([string]$RepoRoot, [string]$TaskId, [string]$BaseBranch, [string]$PolicyRef, [switch]$RequireReady)
    $root = Get-TaskRoot $RepoRoot
    $branch = (Invoke-TaskGit $root @('branch', '--show-current')).Trim()
    if ($branch -cne "task/$TaskId") { throw "Expected task/$TaskId; actual branch: $branch" }
    $policy = Get-TaskPolicy $root $TaskId $BaseBranch $PolicyRef
    $changes = Get-TaskChanges $root $policy.BaseCommit
    $entries = (Invoke-TaskGit $root @('ls-files', '--stage', '-z')).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)
    foreach ($entry in $entries) {
        if ($entry -match '^(120000|160000) [^\t]+\t(.+)$' -and $changes.Paths -ccontains $Matches[2]) { throw "Changed symlink/submodule is not supported: $($Matches[2])" }
    }
    $failures = @()
    foreach ($path in $changes.Paths) {
        try { Assert-TaskOwned $path $policy.Card; $null = Get-TaskFile $root $path -DirectoryAllowed }
        catch { $failures += $_.Exception.Message }
    }
    if ($failures.Count) { throw ($failures -join "`n") }
    $state = Assert-TaskLog $root $TaskId -RequireReady:$RequireReady
    $log = Get-Content -LiteralPath (Get-TaskFile $root "memory/branches/$TaskId.md") -Raw
    if ($log -cnotmatch "(?m)^- 负责人：$([regex]::Escape($policy.Card.Owner))\r?$") { throw 'Task log owner does not match trusted card.' }
    return [pscustomobject]@{ Root = $root; TaskId = $TaskId; Branch = $branch; Head = (Invoke-TaskGit $root @('rev-parse', 'HEAD')).Trim(); Policy = $policy; Changes = $changes; State = $state }
}

function Assert-TaskSourceClean {
    param($Context)
    $tracked = Invoke-TaskGit $Context.Root @('diff', '--name-only', 'HEAD', '--')
    if ($tracked.Length) { throw 'Tracked source/log/index is dirty; cannot attest HEAD.' }
    foreach ($path in $Context.Changes.DirtyPaths) {
        if (-not $path.StartsWith("evidence/$($Context.TaskId)/runs/", [StringComparison]::Ordinal)) { throw "Untracked source is dirty: $path" }
    }
}

function Get-TaskTime { return [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o') }

function Test-TaskReport {
    param($Context, [string]$ReportPath)
    Assert-TaskSourceClean $Context
    if (-not [IO.Path]::IsPathFullyQualified($ReportPath)) { $ReportPath = Get-TaskFile $Context.Root $ReportPath }
    Assert-NoTaskLink $ReportPath
    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json -Depth 40
    if ($report.SchemaVersion -ne 1 -or $report.TaskId -cne $Context.TaskId -or $report.Head -cne $Context.Head -or $report.PolicyCommit -cne $Context.Policy.PolicyCommit -or $report.CardBlob -cne $Context.Policy.CardBlob -or $report.SourceClean -isnot [bool] -or -not $report.SourceClean -or $report.Overall -cne 'passed') { throw 'Report HEAD/policy/status mismatch.' }
    $null = [DateTimeOffset]::Parse($report.StartedAt)
    $null = [DateTimeOffset]::Parse($report.FinishedAt)
    if ($Context.Policy.Card.RequiredChecks.Count -eq 0) { throw 'No RequiredChecks; acceptance remains unverified.' }
    if ($report.Checks -isnot [array] -or $report.Checks.Count -ne $Context.Policy.Card.Checks.Count) { throw 'Missing/extra reported checks.' }
    foreach ($check in $Context.Policy.Card.Checks) {
        $found = @($report.Checks | Where-Object { $_.Id -ceq $check.Id })
        if ($found.Count -ne 1) { throw "Missing/duplicate result: $($check.Id)" }
        $result = $found[0]
        $expectedStatus = if ($check.ExpectedExitCode -eq 0) { 'passed' } else { 'expected_failure' }
        if ($result.ExitCode -isnot [int] -and $result.ExitCode -isnot [long]) { throw "Missing actual exit code: $($check.Id)" }
        if ($result.Executable -cne $check.Executable -or ($result.Arguments | ConvertTo-Json -Compress) -cne ($check.Arguments | ConvertTo-Json -Compress) -or $result.ExpectedExitCode -ne $check.ExpectedExitCode -or $result.ExitCode -ne $check.ExpectedExitCode -or $result.Status -cne $expectedStatus) { throw "Command/exit mismatch: $($check.Id)" }
        if ($result.Artifacts -isnot [array] -or $result.Artifacts.Count -ne (2 + $check.EvidencePaths.Count)) { throw "Missing evidence/logs: $($check.Id)" }
        foreach ($kind in @('stdout', 'stderr')) { if (@($result.Artifacts | Where-Object { $_.Kind -ceq $kind }).Count -ne 1) { throw "Missing $kind log." } }
        foreach ($source in $check.EvidencePaths) { if (@($result.Artifacts | Where-Object { $_.Kind -ceq 'evidence' -and $_.SourcePath -ceq $source }).Count -ne 1) { throw "Missing expected evidence: $source" } }
        foreach ($artifact in $result.Artifacts) {
            if (-not $artifact.Path.StartsWith("evidence/$($Context.TaskId)/runs/", [StringComparison]::Ordinal)) { throw 'Artifact outside task runs.' }
            $path = Get-TaskFile $Context.Root $artifact.Path
            if ($artifact.SHA256 -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $artifact.SHA256) { throw "Evidence hash mismatch: $($artifact.Path)" }
        }
    }
    return $report
}
