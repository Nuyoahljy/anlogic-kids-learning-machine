#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildDirectory)
$ErrorActionPreference='Stop'
$gitCommand=Get-Command git -ErrorAction SilentlyContinue
$git=if($gitCommand){$gitCommand.Source}else{Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/cmd/git.exe'}
if(-not(Test-Path -LiteralPath $git)){throw 'Git executable not available'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$evidence=Join-Path $repo 'evidence/sc520-dynamic-box'
$project=Join-Path $repo 'fpga/custom_project/sc520-dynamic-box'
$origin=Get-Content -LiteralPath (Join-Path $evidence 'origin.json') -Raw | ConvertFrom-Json
if((Get-FileHash -LiteralPath $origin.Rollback).Hash -ne $origin.RollbackSHA256){throw 'Rollback changed'}
$changed=@()
foreach($entry in $origin.SourceInputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $origin.Source $entry.Name)).Hash -ne $entry.Value){throw "Old source changed: $($entry.Name)"}
    if((Get-FileHash -LiteralPath (Join-Path $project $entry.Name)).Hash -ne $entry.Value){$changed+=$entry.Name}
}
$expectedChanges=@('user_source/hdl_source/design_top_wrapper.v','td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj','td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.prj')
if(@(Compare-Object ($changed|Sort-Object) ($expectedChanges|Sort-Object)).Count){throw 'Unexpected imported source changes'}
foreach($relative in $expectedChanges | Where-Object {$_ -notmatch '\.v$'}){
    $text=Get-Content -LiteralPath (Join-Path $project $relative) -Raw
    foreach($module in @('color_bbox_stats.v','bbox_stabilizer.v','hdmi_dynamic_box.v')){
        if([regex]::Matches($text,[regex]::Escape('/roi/'+$module+'"')).Count -ne 1){throw "Source list mismatch: $relative $module"}
    }
}
$tests=@()
$reports=Get-ChildItem -LiteralPath (Join-Path $evidence 'sim-runs') -Filter '*.log.json' | Sort-Object Name -Descending
foreach($selection in @(@('stats',$false),@('stability',$false),@('capacity',$false),@('color',$false),@('sync',$false),@('display',$false),@('display',$true))){
    $file=$reports | Where-Object {
        $test=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        $test.Testcase -eq $selection[0] -and $test.Negative -eq $selection[1]
    } | Select-Object -First 1
    if(-not $file){throw 'Missing test report'}
    $test=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if($test.ExitCode -ne $test.ExpectedExitCode){throw 'Unexpected simulation exit'}
    foreach($entry in $test.InputSHA256.PSObject.Properties){
        if((Get-FileHash -LiteralPath (Join-Path $repo $entry.Name)).Hash -ne $entry.Value){throw "Stale simulation: $($entry.Name)"}
    }
    foreach($field in @('Log','Summary')){
        if((Get-FileHash -LiteralPath $test.$field).Hash -ne $test.($field+'SHA256')){throw 'Changed evidence'}
    }
    $summary=Get-Content -LiteralPath $test.Summary -Raw | ConvertFrom-Json
    $expectedErrors=if($test.Negative){4}else{0}
    if($summary.done -ne 1 -or $summary.errors -ne $expectedErrors -or $summary.testcase -ne $test.Testcase){throw 'Test did not complete correctly'}
    $log=Get-Content -LiteralPath $test.Log -Raw
    if($log -notmatch "RESULT $($test.Testcase) errors=$expectedErrors\b"){throw 'Missing actual transcript result'}
    $tests+=@{Report=$file.FullName;SHA256=(Get-FileHash -LiteralPath $file.FullName).Hash;Testcase=$test.Testcase;Negative=$test.Negative;Errors=$summary.errors;ExitCode=$test.ExitCode}
}
$buildPath=Join-Path $BuildDirectory 'result.json'
$build=Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
if($build.Variant -ne 'dynamic-box' -or @($build.Stages).Count -ne 2 -or @($build.Stages | Where-Object ExitCode -ne 0).Count){throw 'Build stages incomplete'}
if((Get-FileHash -LiteralPath $build.SourceSnapshot).Hash -ne $build.SourceSnapshotSHA256){throw 'Changed source snapshot'}
$inputs=Get-Content -LiteralPath $build.SourceSnapshot -Raw | ConvertFrom-Json -AsHashtable
foreach($relative in $inputs.Keys){if((Get-FileHash -LiteralPath (Join-Path $project $relative)).Hash -ne $inputs[$relative]){throw "Stale build: $relative"}}
if((Get-FileHash -LiteralPath $build.Bit).Hash -ne $build.SHA256){throw 'Changed bit'}
$phy=$build.Stages | Where-Object Stage -eq 'phy_1'
$log=Get-Content -LiteralPath $phy.Stdout -Raw
$setup=[regex]::Matches($log,'Setup\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)') | Select-Object -Last 1
$hold=[regex]::Matches($log,'Hold\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)') | Select-Object -Last 1
if(-not $setup -or -not $hold){throw 'No final timing summary'}
foreach($timing in @($setup,$hold)){
    if([int]$timing.Groups[1].Value -lt 0 -or [int]$timing.Groups[2].Value -ne 0 -or [int]$timing.Groups[3].Value -ne 0){throw 'Timing violation'}
}
$runDir=Split-Path -Parent $build.Bit
$timingPath=Join-Path $BuildDirectory 'final_timing.rpt'
$areaPath=Join-Path $BuildDirectory 'final_area.rpt'
Copy-Item -LiteralPath (Join-Path $runDir 'final_timing.rpt') -Destination $timingPath
Copy-Item -LiteralPath (Join-Path $runDir 'camera_to_dsi_display_phy.area') -Destination $areaPath
$coverage=[regex]::Match((Get-Content -LiteralPath $timingPath -Raw),'STA coverage\s+: ([\d.]+)%').Groups[1].Value
if(-not $coverage){throw 'Missing STA coverage'}
$candidates=Join-Path $evidence 'candidates'
[IO.Directory]::CreateDirectory($candidates) | Out-Null
$candidate=Join-Path $candidates 'sc520_dynamic_box.bit'
if(Test-Path -LiteralPath $candidate){
    if((Get-FileHash -LiteralPath $candidate).Hash -ne $build.SHA256){throw 'Never replace a different published candidate'}
}else{Copy-Item -LiteralPath $build.Bit -Destination $candidate}
if((Get-FileHash -LiteralPath $candidate).Hash -ne $build.SHA256){throw 'Candidate copy mismatch'}
$now=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time')
@{Status='software_verified_waiting_user_hardware_test';GeneratedAt=$now.ToString('o');GitHEAD=(& $git -C $repo rev-parse HEAD);UncommittedTask=$true;Candidate=$candidate;SHA256=$build.SHA256;Bytes=$build.Bytes;BuildResult=$buildPath;BuildResultSHA256=(Get-FileHash -LiteralPath $buildPath).Hash;SourceSnapshot=$build.SourceSnapshot;SourceSnapshotSHA256=$build.SourceSnapshotSHA256;OriginalInputsVerified=@($origin.SourceInputs.PSObject.Properties).Count;ChangedImportedInputs=$changed;Rollback=$origin.Rollback;RollbackSHA256=$origin.RollbackSHA256;Tests=$tests;SetupWNSps=[int]$setup.Groups[1].Value;HoldWNSps=[int]$hold.Groups[1].Value;STACoveragePercent=$coverage;TimingReport=$timingPath;TimingSHA256=(Get-FileHash -LiteralPath $timingPath).Hash;AreaReport=$areaPath;AreaSHA256=(Get-FileHash -LiteralPath $areaPath).Hash;HardwareValidated=$false;Risks=@('Uncalibrated RGB thresholds and area/stability parameters; one dominant color only; no shape recognition','Inherited timing/clock warnings and incomplete STA coverage','No DDR, camera or HDMI PHY simulation','No download, measured frame rate, or hardware stability test')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'candidate-manifest.json') -Encoding utf8
"$($build.SHA256)  sc520_dynamic_box.bit" | Set-Content -LiteralPath (Join-Path $candidates 'SHA256SUMS.txt') -Encoding ascii
Write-Output "PACKAGED tests=$($tests.Count) changed=$($changed.Count) bytes=$($build.Bytes) SHA256=$($build.SHA256) setup=$($setup.Groups[1].Value)ps hold=$($hold.Groups[1].Value)ps coverage=$coverage"
