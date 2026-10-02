#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseBranch = 'main',
    [string]$PolicyRef = '',
    [string]$OutputRoot = ''
)
. (Join-Path $PSScriptRoot 'task-common.ps1')
try {
    $context = Get-TaskContext $RepoRoot $TaskId $BaseBranch $PolicyRef
    Assert-TaskSourceClean $context
    if ($context.Policy.Card.RequiredChecks.Count -eq 0) { throw 'No RequiredChecks: nothing can be certified.' }
    if (-not $OutputRoot) { $OutputRoot = "evidence/$TaskId/runs" }
    if ([IO.Path]::IsPathFullyQualified($OutputRoot)) { $OutputRoot = [IO.Path]::GetRelativePath($context.Root, $OutputRoot).Replace('\', '/') }
    if ($OutputRoot -cne "evidence/$TaskId/runs" -and -not $OutputRoot.StartsWith("evidence/$TaskId/runs/", [StringComparison]::Ordinal)) { throw 'OutputRoot must be inside evidence/<task>/runs.' }
    $outputFull = Get-TaskFile $context.Root $OutputRoot
    Assert-TaskOwned ($OutputRoot.TrimEnd('/') + '/') $context.Policy.Card
    $runId = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $relativeRun = "$OutputRoot/$runId"
    $run = Get-TaskFile $context.Root $relativeRun
    $null = New-Item -ItemType Directory -Path $run
    $report = [ordered]@{ SchemaVersion = 1; TaskId = $TaskId; Head = $context.Head; BaseCommit = $context.Policy.BaseCommit; PolicyCommit = $context.Policy.PolicyCommit; CardBlob = $context.Policy.CardBlob; SourceClean = $true; StartedAt = (Get-TaskTime); FinishedAt = $null; Overall = 'failed'; Checks = @(); UnverifiedLevels = @('HDL simulation', 'TD build/timing', 'hardware', 'release'); Failures = @() }
    foreach ($check in $context.Policy.Card.Checks) {
        $checkDir = Join-Path $run $check.Id
        $null = New-Item -ItemType Directory -Path $checkDir
        $entry = [ordered]@{ Id = $check.Id; Executable = $check.Executable; ResolvedExecutable = $null; Arguments = $check.Arguments; ExpectedExitCode = $check.ExpectedExitCode; StartedAt = (Get-TaskTime); FinishedAt = $null; ExitCode = $null; Status = 'not_run'; Artifacts = @(); Error = $null }
        $stdout = ''
        $stderr = ''
        try {
            $command = Get-Command -Name $check.Executable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $command) { $entry.Status = 'missing_tool'; throw "Missing executable: $($check.Executable)" }
            $entry.ResolvedExecutable = $command.Source
            $execution = Invoke-TaskProcess $command.Source $check.Arguments $context.Root
            $stdout = $execution.Stdout
            $stderr = $execution.Stderr
            $entry.ExitCode = $execution.ExitCode
            if ($execution.ExitCode -eq $check.ExpectedExitCode) { $entry.Status = $(if ($check.ExpectedExitCode -eq 0) { 'passed' } else { 'expected_failure' }) }
            else { $entry.Status = 'unexpected_exit'; $entry.Error = "Expected $($check.ExpectedExitCode), actual $($execution.ExitCode)" }
            $evidenceIndex = 0
            foreach ($source in $check.EvidencePaths) {
                $sourceFull = Get-TaskFile $context.Root $source
                if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) { $entry.Status = 'missing_evidence'; throw "Missing evidence: $source" }
                $destination = "$relativeRun/$($check.Id)/evidence-$evidenceIndex"
                $destinationFull = Get-TaskFile $context.Root $destination
                [IO.File]::Copy($sourceFull, $destinationFull, $false)
                $entry.Artifacts += [pscustomobject]@{ Kind = 'evidence'; SourcePath = $source; Path = $destination; SHA256 = (Get-FileHash -LiteralPath $destinationFull -Algorithm SHA256).Hash }
                $evidenceIndex++
            }
        }
        catch { $entry.Error = $_.Exception.Message; if ($entry.Status -in @('not_run', 'passed', 'expected_failure')) { $entry.Status = 'execution_error' } }
        foreach ($kind in @('stdout', 'stderr')) {
            $relativeLog = "$relativeRun/$($check.Id)/$kind.log"
            $fullLog = Get-TaskFile $context.Root $relativeLog
            $text = if ($kind -eq 'stdout') { $stdout } else { $stderr }
            [IO.File]::WriteAllText($fullLog, $text, [Text.UTF8Encoding]::new($false))
            $entry.Artifacts += [pscustomobject]@{ Kind = $kind; SourcePath = $null; Path = $relativeLog; SHA256 = (Get-FileHash -LiteralPath $fullLog -Algorithm SHA256).Hash }
        }
        $entry.FinishedAt = Get-TaskTime
        $report.Checks += [pscustomobject]$entry
    }
    try {
        $after = Get-TaskContext $context.Root $TaskId $BaseBranch $PolicyRef
        Assert-TaskSourceClean $after
        if ($after.Head -cne $context.Head -or $after.Policy.PolicyCommit -cne $context.Policy.PolicyCommit) { throw 'HEAD/policy changed while tests ran.' }
    }
    catch { $report.SourceClean = $false; $report.Failures += $_.Exception.Message }
    if ($report.SourceClean -and @($report.Checks | Where-Object { $_.Status -cnotin @('passed', 'expected_failure') }).Count -eq 0) { $report.Overall = 'passed' }
    $report.FinishedAt = Get-TaskTime
    $reportPath = Join-Path $run 'report.json'
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 40) + "`n", [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ Report = $reportPath; Head = $context.Head; Overall = $report.Overall } | ConvertTo-Json
    if ($report.Overall -cne 'passed') { exit 1 }
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
