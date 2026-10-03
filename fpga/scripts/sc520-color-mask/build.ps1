#Requires -Version 7.5
[CmdletBinding()]
param([switch]$Rebuild)
$Variant='color-mask'
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$project = Join-Path $repo 'fpga/custom_project/sc520-color-mask'
$tool = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
$runId = '{0}-{1}-{2}' -f $Variant, (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
$evidence = Join-Path $repo "evidence/sc520-color-mask/builds/$runId"
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$bit = Join-Path $project 'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
if (Test-Path -LiteralPath $bit) {
    if (-not $Rebuild) { throw 'Existing bit present; use -Rebuild to preserve it in the new evidence directory before rebuilding' }
    Copy-Item -LiteralPath $bit -Destination (Join-Path $evidence 'previous.bit')
}
$inputs = @(Get-ChildItem -LiteralPath (Join-Path $project 'user_source') -File -Recurse)
$inputs += Get-ChildItem -LiteralPath (Join-Path $project 'td_project/al_ip') -File -Recurse
$inputs += Get-ChildItem -LiteralPath (Join-Path $project 'td_project') -File | Where-Object { $_.Extension -in @('.al','.sdc') }
foreach ($stage in @('syn_1','phy_1')) {
    $inputs += Get-ChildItem -LiteralPath (Join-Path $project "td_project/camera_to_dsi_display_Runs/$stage") -File | Where-Object { $_.Name -in @('camera_to_dsi_display.prj','camera_to_dsi_display.tcl','settings.cfg') }
}
$hashes = @{}
foreach ($inputFile in $inputs) { $hashes[[IO.Path]::GetRelativePath($project,$inputFile.FullName).Replace('\','/')] = (Get-FileHash -LiteralPath $inputFile.FullName).Hash }
$sourceSnapshot = Join-Path $evidence 'source-inputs.json'
$hashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sourceSnapshot -Encoding utf8
$results = [Collections.Generic.List[object]]::new()
foreach ($stage in @('syn_1','phy_1')) {
    $runDir = Join-Path $project "td_project/camera_to_dsi_display_Runs/$stage"
    $stdout = Join-Path $evidence "$stage.stdout.log"
    $stderr = Join-Path $evidence "$stage.stderr.log"
    $launcher = Join-Path $evidence "$stage.launch.tcl"
    @'
if {[catch {source camera_to_dsi_display.tcl} message]} {
    puts stderr $message
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath $launcher -Encoding utf8
    $started = Get-Date
    $process = Start-Process -FilePath $tool -ArgumentList $launcher.Replace('\','/') -WorkingDirectory $runDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    Write-Output "TD $Variant $stage PID=$($process.Id) evidence=$evidence"
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $results.Add([ordered]@{ Stage=$stage; PID=$process.Id; ExitCode=$exitCode; Stdout=$stdout; Stderr=$stderr })
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'stages.json') -Encoding utf8
    $terminal = if ($stage -eq 'syn_1') { '.opt_gate.end.f' } else { '.bitgen.end.f' }
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $runDir $terminal))) { throw "TD $stage failed: exit=$exitCode; inspect $evidence" }
    if ((Get-Item -LiteralPath (Join-Path $runDir $terminal)).LastWriteTime -lt $started) { throw 'Stale completion marker' }
}
if (-not (Test-Path -LiteralPath $bit)) { throw 'No bit generated' }
foreach ($inputPath in $hashes.Keys) { if ((Get-FileHash -LiteralPath (Join-Path $project $inputPath)).Hash -ne $hashes[$inputPath]) { throw "Build input changed: $inputPath" } }
[ordered]@{ Variant=$Variant; Bit=$bit; SHA256=(Get-FileHash -LiteralPath $bit).Hash; Bytes=(Get-Item -LiteralPath $bit).Length; HardwareValidated=$false; SourceSnapshot=$sourceSnapshot; SourceSnapshotSHA256=(Get-FileHash -LiteralPath $sourceSnapshot).Hash; Stages=$results } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding utf8
Write-Output "BUILD_FINISHED $Variant $bit"
