#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ParentRun='6a50b220',
    [string]$ResumeRun='route220-v1'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$tool='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
if($ParentRun -notmatch '^[a-f0-9]{8}$' -or $ResumeRun -notmatch '^route220-v[1-9][0-9]*$'){throw 'Invalid recovery ID'}
$parent=Join-Path $repo "evidence/sc520-card-recognition/builds/$ParentRun"
$run=Join-Path $repo "evidence/sc520-card-recognition/builds/$ResumeRun"
if(Test-Path -LiteralPath $run){throw 'Recovery directory must be new'}
# A SUBST path can conceal the run ID in a process command line.
if(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'td_commands_prompt.exe'}){throw 'An active TD CLI run must be resolved before recovery'}
$stages=@(Get-Content -Raw -LiteralPath (Join-Path $parent 'stages.json') | ConvertFrom-Json)
if($stages.Count -ne 1 -or $stages[0].Stage -ne 'syn_1' -or $stages[0].ExitCode -ne 0 -or -not $stages[0].MarkerFresh){throw 'Parent synthesis is not qualified'}
$parentPhy=Join-Path $parent 'td_project/camera_to_dsi_display_Runs/phy_1'
foreach($name in @('result.json','failure.json')){
    if(Test-Path -LiteralPath (Join-Path $parent $name)){throw "Parent has $name; inspect its outcome before recovery"}
}
if(-not(Test-Path -LiteralPath (Join-Path $parentPhy '.opt_place.end.f')) -or
   (Test-Path -LiteralPath (Join-Path $parentPhy '.opt_route.end.f'))){throw 'Expected completed placement and interrupted routing'}
$inputs=Get-Content -Raw -LiteralPath (Join-Path $parent 'inputs.json') | ConvertFrom-Json
foreach($file in $inputs.Files){
    if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){throw "Changed source $($file.Path)"}
    if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){throw "Changed snapshot $($file.Snapshot)"}
}
if(@(Get-ChildItem -LiteralPath $parent -File -Recurse -Filter '*.bit').Count){throw 'Unexpected parent bit'}
$place=Join-Path $parentPhy 'camera_to_dsi_display_place.db'
if(-not(Test-Path -LiteralPath $place)){throw 'No placement database'}
$settingsSource=Join-Path $parentPhy 'settings.cfg'
$settings=[IO.File]::ReadAllText($settingsSource)
if(([regex]::Matches($settings,'(?m)^set start_step opt_place\r?$')).Count -ne 1){throw 'Unexpected parent start step'}
New-Item -ItemType Directory -Path $run | Out-Null
$copied=[Collections.Generic.List[object]]::new()
function Copy-SealedFile([string]$source,[string]$destination){
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    $digest=(Get-FileHash -LiteralPath $source).Hash
    if((Get-FileHash -LiteralPath $destination).Hash -ne $digest){throw 'Recovery copy mismatch'}
    $copied.Add([ordered]@{Source=$source;Path=$destination;SHA256=$digest})
}
foreach($relative in @('overlay','rtl','tools','td_project/camera_to_dsi_display_Runs/syn_1')){
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $parent $relative) -Recurse -File){
        Copy-SealedFile $file.FullName (Join-Path $run ([IO.Path]::GetRelativePath($parent,$file.FullName)))
    }
}
foreach($relative in @('templates.mem','anlogic_logo_index.mem','anlogic_logo_palette.mem','profile.json','inputs.json','syn_1.stdout.log','syn_1.stderr.log')){
    Copy-SealedFile (Join-Path $parent $relative) (Join-Path $run $relative)
}
$cwd=Join-Path $run 'td_project/camera_to_dsi_display_Runs/phy_1'
foreach($name in @('camera_to_dsi_display.prj','camera_to_dsi_display.tcl','camera_to_dsi_display_place.db')){
    Copy-SealedFile (Join-Path $parentPhy $name) (Join-Path $cwd $name)
}
$settingsPath=Join-Path $cwd 'settings.cfg'
$settings=$settings.Replace('set start_step opt_place','set start_step opt_route')
[IO.File]::WriteAllText($settingsPath,$settings,[Text.UTF8Encoding]::new($false))
$resumePath=Join-Path $run 'resume.json'
[ordered]@{
    At=[datetime]::UtcNow.ToString('o');ParentRun=$parent;ResumeRun=$run
    ParentPhysicalOutcome='Interrupted: process absent; no native exit, route-end marker, or final result available'
    ParentPhysicalStdout=[ordered]@{Path=(Join-Path $parent 'phy_1.stdout.log');SHA256=(Get-FileHash -LiteralPath (Join-Path $parent 'phy_1.stdout.log')).Hash}
    ParentStages=[ordered]@{Path=(Join-Path $parent 'stages.json');SHA256=(Get-FileHash -LiteralPath (Join-Path $parent 'stages.json')).Hash}
    CopiedFiles=$copied
    Settings=[ordered]@{Source=$settingsSource;SourceSHA256=(Get-FileHash -LiteralPath $settingsSource).Hash;Path=$settingsPath;SHA256=(Get-FileHash -LiteralPath $settingsPath).Hash;OnlyChange='start_step opt_place -> opt_route'}
    SynthesisReexecuted=$false;PlacementReexecuted=$false;RoutingReexecuted=$true
    TestOnly=$true;BitGenerationAllowed=$false;HardwareValidated=$false
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resumePath -Encoding utf8
$launcher=Join-Path $run 'phy_1.launch.tcl'
@'
if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 if {$start_step ne "opt_route" || $end_step ne "opt_route"} {error "T022 recovery must route only"}
 proc bitgen {args} {error "T022 bitgen is prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-phy_1-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 source ../../../overlay/report-pixel14-cdc.tcl
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_STAGE_OK phy_1"
exit 0
'@ | Set-Content -LiteralPath $launcher -Encoding utf8
$drive=''
foreach($candidate in @('Z:','W:','V:','U:')){if(-not(Test-Path -LiteralPath ($candidate+'/'))){$drive=$candidate;break}}
if(-not $drive){throw 'No free temporary drive'}
& subst.exe $drive $run
if($LASTEXITCODE -ne 0){throw 'SUBST failed'}
try{
    $stdout=Join-Path $run 'phy_1.stdout.log';$stderr=Join-Path $run 'phy_1.stderr.log'
    $start=[datetime]::UtcNow
    $process=Start-Process -FilePath $tool -ArgumentList ('"{0}/phy_1.launch.tcl"' -f $drive) -WorkingDirectory ($drive+'/td_project/camera_to_dsi_display_Runs/phy_1') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    [ordered]@{StartedAtUtc=$start.ToString('o');PID=$process.Id;Tool=$tool;ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash;TestOnly=$true;BitGenerationAllowed=$false;HardwareValidated=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'started.json') -Encoding utf8
    Write-Output "T022_RESUME_ROUTE PID=$($process.Id) run=$run"
    $process.WaitForExit();$process.Refresh()
    $marker=Join-Path $cwd '.opt_route.end.f'
    $fresh=(Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $start
    $stages+=[ordered]@{Stage='phy_1';PID=$process.Id;ExitCode=$process.ExitCode;StartedAtUtc=$start.ToString('o');FinishedAtUtc=[datetime]::UtcNow.ToString('o');MarkerFresh=$fresh;Stdout=$stdout;Stderr=$stderr}
    $stages | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'stages.json') -Encoding utf8
    if($process.ExitCode -ne 0 -or -not $fresh -or -not(Select-String -LiteralPath $stdout -SimpleMatch 'PIXEL14_STAGE_OK phy_1' -Quiet)){throw 'Recovery routing/report stage did not qualify'}
    $changed=@()
    foreach($file in $inputs.Files){
        if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){$changed+=$file.Path}
        if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){$changed+=$file.Snapshot}
    }
    foreach($file in $copied){
        if((Get-FileHash -LiteralPath $file.Source).Hash -ne $file.SHA256 -or (Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){$changed+=$file.Path}
    }
    if(@(Get-ChildItem -LiteralPath $run -File -Recurse -Filter '*.bit').Count){throw 'Unexpected test bit: do not deliver'}
    [ordered]@{FinishedAtUtc=[datetime]::UtcNow.ToString('o');Stages=$stages;ChangedInputs=$changed;InheritedPlacement=$parent;Recovery=$resumePath;TestOnly=$true;BitGenerationAllowed=$false;BitFilesFound=@();HardwareValidated=$false;TimingQualified=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
    if($changed.Count){throw 'Recovery inputs changed'}
    Write-Output "T022_RESUME_FINISHED $run"
}catch{
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;Stages=$stages} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'failure.json') -Encoding utf8
    throw
}finally{& subst.exe $drive /d}
