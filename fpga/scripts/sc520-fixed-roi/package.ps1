#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BaselineBuild,[Parameter(Mandatory)][string]$OverlayBuild)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$evidence=Join-Path $repo 'evidence/sc520-fixed-roi'
$manifest=Get-Content -LiteralPath (Join-Path $evidence 'source-manifest.json') -Raw | ConvertFrom-Json
$allowedChanges=@('user_source/hdl_source/design_top_wrapper.v','td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj','td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.prj')
$actualChanges=@()
foreach($entry in $manifest.Files){
    $base=Join-Path $repo "fpga/vendor_labs/sc520/$($entry.Path)"
    $overlay=Join-Path $repo "fpga/custom_project/sc520/$($entry.Path)"
    if((Get-FileHash -LiteralPath $base).Hash -ne $entry.SHA256){throw "Original source changed: $($entry.Path)"}
    if((Get-FileHash -LiteralPath $overlay).Hash -ne $entry.SHA256){
        if($entry.Path -notin $allowedChanges){throw "Unexpected integration edit: $($entry.Path)"}
        $actualChanges+=$entry.Path
    }
}
if($actualChanges.Count -ne 4){throw 'Expected exactly four changes to imported project inputs'}
$reused=Get-Content -LiteralPath (Join-Path $evidence 'reused-modules.json') -Raw | ConvertFrom-Json
foreach($module in $reused){if((Get-FileHash -LiteralPath $module.Destination).Hash -ne $module.SHA256){throw 'Reused RTL has changed'}}
foreach($relative in $allowedChanges | Where-Object {$_ -match '\.(al|prj)$'}){
    $text=[IO.File]::ReadAllText((Join-Path $repo "fpga/custom_project/sc520/$relative"))
    foreach($name in @('pixel_coord_adapter.v','fixed_rect_overlay.v','hdmi_roi_overlay.v')){
        if([regex]::Matches($text,[regex]::Escape('/roi/'+$name+'"')).Count -ne 1){throw "Missing/duplicate source reference: $relative $name"}
    }
}
$testReports=@()
foreach($selection in @(@('display',$false),@('stream',$false),@('display',$true))){
    $reports=Get-ChildItem -LiteralPath (Join-Path $evidence 'sim-runs') -Filter '*.log.json' | Sort-Object Name -Descending
    $reportFile=$reports | Where-Object {$test=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $test.Testcase -eq $selection[0] -and $test.Negative -eq $selection[1]} | Select-Object -First 1
    if(-not $reportFile){throw 'Missing final simulation report'}
    $test=Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json
    if($test.ExitCode -ne $test.ExpectedExitCode){throw 'Unexpected simulation exit code'}
    if((Get-FileHash -LiteralPath $test.Log).Hash -ne $test.LogSHA256){throw 'Simulation log changed'}
    foreach($property in $test.InputSHA256.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $repo $property.Name)).Hash -ne $property.Value){throw "Stale simulation: $($property.Name)"}}
    $log=Get-Content -LiteralPath $test.Log -Raw
    $expectedErrors=if($test.Negative){4}else{0}
    if((Get-FileHash -LiteralPath $test.Summary).Hash -ne $test.SummarySHA256){throw 'Simulation summary changed'}
    $summary=Get-Content -LiteralPath $test.Summary -Raw | ConvertFrom-Json
    if($summary.done -ne 1 -or $summary.errors -ne $expectedErrors -or $summary.testcase -ne $test.Testcase){throw 'Missing simulation completion proof'}
    if($log -notmatch "RESULT $($test.Testcase) errors=$expectedErrors\b"){throw 'Missing transcript result'}
    $testReports+=@{Path=$reportFile.FullName;SHA256=(Get-FileHash -LiteralPath $reportFile.FullName).Hash;Testcase=$test.Testcase;Negative=$test.Negative;ExitCode=$test.ExitCode}
}
$candidates=Join-Path $evidence 'candidates'
[IO.Directory]::CreateDirectory($candidates) | Out-Null
$buildReports=@()
foreach($entry in @(@{Variant='baseline';Directory=$BaselineBuild;Project='fpga/vendor_labs/sc520'},@{Variant='overlay';Directory=$OverlayBuild;Project='fpga/custom_project/sc520'})){
    $build=Get-Content -LiteralPath (Join-Path $entry.Directory 'result.json') -Raw | ConvertFrom-Json
    if($build.Variant -ne $entry.Variant -or @($build.Stages | Where-Object {$_.ExitCode -ne 0}).Count -ne 0){throw 'Build stages did not pass'}
    if((Get-FileHash -LiteralPath $build.SourceSnapshot).Hash -ne $build.SourceSnapshotSHA256){throw 'Source snapshot changed'}
    $inputs=Get-Content -LiteralPath $build.SourceSnapshot -Raw | ConvertFrom-Json -AsHashtable
    foreach($sourcePath in $inputs.Keys){if((Get-FileHash -LiteralPath (Join-Path (Join-Path $repo $entry.Project) $sourcePath)).Hash -ne $inputs[$sourcePath]){throw "Stale build input: $sourcePath"}}
    if((Get-FileHash -LiteralPath $build.Bit).Hash -ne $build.SHA256){throw 'Build bit changed'}
    $phy=$build.Stages | Where-Object Stage -eq 'phy_1'
    $log=Get-Content -LiteralPath $phy.Stdout -Raw
    $setup=[regex]::Matches($log,'Setup\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)') | Select-Object -Last 1
    $hold=[regex]::Matches($log,'Hold\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)') | Select-Object -Last 1
    if(-not $setup -or -not $hold){throw 'No final timing summary'}
    foreach($timing in @($setup,$hold)){if([int]$timing.Groups[1].Value -lt 0 -or [int]$timing.Groups[2].Value -ne 0 -or [int]$timing.Groups[3].Value -ne 0){throw 'Final timing violation'}}
    $runDir=Split-Path -Parent $build.Bit
    $timingPath=Join-Path $runDir 'final_timing.rpt'
    $areaPath=Join-Path $runDir 'camera_to_dsi_display_phy.area'
    $timingText=Get-Content -LiteralPath $timingPath -Raw
    $coverage=[regex]::Match($timingText,'STA coverage\s+: ([\d.]+)%').Groups[1].Value
    $destination=Join-Path $candidates "sc520_$($entry.Variant).bit"
    if(Test-Path -LiteralPath $destination){if((Get-FileHash -LiteralPath $destination).Hash -ne $build.SHA256){throw 'Refusing to replace a different published candidate'}}else{Copy-Item -LiteralPath $build.Bit -Destination $destination}
    $buildReports+=@{Variant=$entry.Variant;Candidate=$destination;SHA256=$build.SHA256;Bytes=$build.Bytes;BuildResult=(Join-Path $entry.Directory 'result.json');SourceSnapshot=$build.SourceSnapshot;SourceSnapshotSHA256=$build.SourceSnapshotSHA256;SetupWNSps=[int]$setup.Groups[1].Value;HoldWNSps=[int]$hold.Groups[1].Value;STACoveragePercent=$coverage;TimingReport=$timingPath;TimingSHA256=(Get-FileHash -LiteralPath $timingPath).Hash;AreaReport=$areaPath;AreaSHA256=(Get-FileHash -LiteralPath $areaPath).Hash;PhysicalLog=$phy.Stdout;PhysicalLogSHA256=(Get-FileHash -LiteralPath $phy.Stdout).Hash;HardwareValidated=$false}
}
$report=@{Status='simulation_and_build_only_waiting_user_hardware_validation';GeneratedAt=[DateTimeOffset]::Now.ToString('o');GitHEAD=(& git -C $repo rev-parse HEAD);Branch=(& git -C $repo branch --show-current);UncommittedTask=$true;OriginalInputsVerified=$manifest.Files.Count;ChangedImportedInputs=$actualChanges;ReusedModules=$reused;Tests=$testReports;Builds=$buildReports;Risks=@('STA coverage is below 100%; inherited clock-routing warnings remain','Vendor VTC/mixer has 18 read-gating differences in this stimulus; DDR is not simulated','No download, Flash programming, real frame-rate check or 30-minute hardware run has been performed')}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'candidate-manifest.json') -Encoding utf8
$buildReports | ForEach-Object { "$($_.SHA256)  $([IO.Path]::GetFileName($_.Candidate))" } | Set-Content -LiteralPath (Join-Path $candidates 'SHA256SUMS.txt') -Encoding ascii
Write-Output "PACKAGED: original=$($manifest.Files.Count) changed=$($actualChanges.Count) tests=$($testReports.Count) candidates=$($buildReports.Count)"
