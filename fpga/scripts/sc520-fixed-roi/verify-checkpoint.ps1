#Requires -Version 7.5
[CmdletBinding()]
param(
    [ValidateSet('overlay','color-mask','dynamic-box','shape')][string]$Stage = 'shape',
    [string]$ModelSimPath = 'D:/modeltech64_10.7/win64/vsim.exe'
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$recipe = Get-Content -LiteralPath (Join-Path $PSScriptRoot "checkpoint/$Stage.json") -Raw | ConvertFrom-Json -AsHashtable
$taskId = if ($Stage -eq 'overlay') { 'sc520-fixed-roi' } else { "sc520-$Stage" }
$cases = switch ($Stage) {
    'overlay' { @('stream','display') }
    'color-mask' { @('color','sync','display') }
    'dynamic-box' { @('stats','stability','capacity','color','sync','display') }
    'shape' { @('classifier','confirm','label','shapes','stats','stability','capacity','color','sync','display') }
}
foreach ($relative in $recipe.Inputs.Keys) {
    $target = Join-Path (Join-Path $repo $recipe.Project) $relative
    if ((Get-FileHash -LiteralPath $target).Hash -cne $recipe.Inputs[$relative]) { throw "Restore/check input first: $relative" }
}
if (-not (Test-Path -LiteralPath $ModelSimPath -PathType Leaf)) { throw 'ModelSim executable missing; pass -ModelSimPath' }
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit' }
$sourceStatus = & git -C $repo status --porcelain=v1 --untracked-files=all
if ($LASTEXITCODE -ne 0 -or $sourceStatus) { throw 'Verification requires a clean source checkout' }
$tracked = @(& git -C $repo ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked source' }
$hashes = @{}
foreach ($relative in $tracked) { $hashes[$relative] = (Get-FileHash -LiteralPath (Join-Path $repo $relative)).Hash }
$runId = 'verify-{0}-{1}-{2}' -f $Stage, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $repo "evidence/sc520-fixed-roi/checkpoint-runs/$runId"
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$report = [ordered]@{Head=$head; SourceClean=$true; Stage=$Stage; Passed=$false; Tests=@(); SourceSHA256=$hashes; Unverified=@('TD rebuild','physical board','real-world recognition accuracy','release acceptance'); Error=$null}
$tests = @($cases | ForEach-Object { @{Name=$_; Negative=$false} }) + @(@{Name='display'; Negative=$true})
try {
    foreach ($test in $tests) {
        $negative = if ($test.Negative) { 1 } else { 0 }
        $caseRoot = Join-Path $runRoot "$($test.Name)-$negative"
        [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
        $launcher = Join-Path $caseRoot 'launch.log'
        $console = Join-Path $caseRoot 'console.log'
        $tcl = (Join-Path $repo "fpga/scripts/$taskId/run-sim.do").Replace('\','/')
        $command = "set testcase $($test.Name); set negative $negative; set sim_output {$($caseRoot.Replace('\','/'))}; source {$tcl}"
        Push-Location $caseRoot
        try { & $ModelSimPath -c -l $launcher -do $command *> $console; $exitCode = $LASTEXITCODE } finally { Pop-Location }
        $summaryPath = Join-Path $caseRoot 'summary.json'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $expectedErrors = if ($test.Negative) { 4 } else { 0 }
        $passed = $exitCode -eq $negative -and $summary.done -eq 1 -and $summary.errors -eq $expectedErrors
        $report.Tests += @{Name=$test.Name; Negative=$test.Negative; ExitCode=$exitCode; Errors=$summary.errors; Passed=$passed; Summary=[IO.Path]::GetRelativePath($repo,$summaryPath); SummarySHA256=(Get-FileHash -LiteralPath $summaryPath).Hash; Console=[IO.Path]::GetRelativePath($repo,$console); ConsoleSHA256=(Get-FileHash -LiteralPath $console).Hash}
        if (-not $passed) { throw "Unexpected simulation result: $($test.Name), negative=$negative" }
    }
    foreach ($relative in $tracked) { if ((Get-FileHash -LiteralPath (Join-Path $repo $relative)).Hash -cne $hashes[$relative]) { throw "Tracked input changed: $relative" } }
    if ((& git -C $repo rev-parse HEAD).Trim() -cne $head -or (& git -C $repo status --porcelain=v1 --untracked-files=all)) { throw 'Checkout changed during verification' }
    $report.Passed = $true
} catch { $report.Error = $_.Exception.Message; throw }
finally { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'report.json') -Encoding utf8 }
Write-Output "VERIFIED head=$head stage=$Stage tests=$($report.Tests.Count) report=$runRoot/report.json"
