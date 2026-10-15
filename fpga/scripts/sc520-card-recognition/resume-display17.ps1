#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ParentRun='6a50b117',
    [string]$ResumeRun='phy117-v1',
    [string]$Python='C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$tool='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
if($ParentRun -notmatch '^[a-f0-9]{8}$' -or $ResumeRun -notmatch '^[a-z0-9-]+$'){throw 'Invalid build ID'}
$parent=Join-Path $repo "evidence/sc520-card-recognition/builds/$ParentRun"
$run=Join-Path $repo "evidence/sc520-card-recognition/builds/$ResumeRun"
if(Test-Path -LiteralPath $run){throw 'Resume directory must be new'}
if(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'td_commands_prompt.exe' -and $_.CommandLine -match [regex]::Escape($ParentRun)}){throw 'Parent still running'}
$stages=@(Get-Content -Raw -LiteralPath (Join-Path $parent 'stages.json') | ConvertFrom-Json)
if($stages.Count -ne 1 -or $stages[0].Stage -ne 'syn_1' -or $stages[0].ExitCode -ne 0 -or -not $stages[0].MarkerFresh){throw 'No qualified parent synthesis'}
$inputs=Get-Content -Raw -LiteralPath (Join-Path $parent 'inputs.json') | ConvertFrom-Json
foreach($file in $inputs.Files){
    if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){throw "Changed source $($file.Path)"}
    if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){throw "Changed snapshot $($file.Snapshot)"}
}
New-Item -ItemType Directory -Path $run | Out-Null
$copied=[Collections.Generic.List[object]]::new()
$targets=@('overlay','rtl','tools','td_project/camera_to_dsi_display_Runs/syn_1')
foreach($relative in $targets){
    $source=Join-Path $parent $relative
    foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File){
        $destination=Join-Path $run ([IO.Path]::GetRelativePath($parent,$file.FullName))
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
        $digest=(Get-FileHash -LiteralPath $file.FullName).Hash
        if((Get-FileHash -LiteralPath $destination).Hash -ne $digest){throw 'Copy mismatch'}
        $copied.Add([ordered]@{Source=$file.FullName;Path=$destination;SHA256=$digest})
    }
}
foreach($relative in @('templates.mem','anlogic_logo_index.mem','anlogic_logo_palette.mem','inputs.json','syn_1.stdout.log','syn_1.stderr.log')){
    $source=Join-Path $parent $relative;$destination=Join-Path $run $relative
    Copy-Item -LiteralPath $source -Destination $destination
    $digest=(Get-FileHash -LiteralPath $source).Hash
    if((Get-FileHash -LiteralPath $destination).Hash -ne $digest){throw 'Copy mismatch'}
    $copied.Add([ordered]@{Source=$source;Path=$destination;SHA256=$digest})
}
$cwd=Join-Path $run 'td_project/camera_to_dsi_display_Runs/phy_1'
New-Item -ItemType Directory -Path $cwd | Out-Null
foreach($relative in @('camera_to_dsi_display.prj','camera_to_dsi_display.tcl','settings.cfg')){
    $source=Join-Path $parent "td_project/camera_to_dsi_display_Runs/phy_1/$relative"
    $destination=Join-Path $cwd $relative
    Copy-Item -LiteralPath $source -Destination $destination
    $digest=(Get-FileHash -LiteralPath $source).Hash
    $copied.Add([ordered]@{Source=$source;Path=$destination;SHA256=$digest})
}
[ordered]@{
    At=[datetime]::UtcNow.ToString('o');ParentRun=$parent;ResumeRun=$run;CopiedFiles=$copied
    ParentStages=(Get-FileHash -LiteralPath (Join-Path $parent 'stages.json')).Hash
    ParentPhysicalOutcome='Interrupted: no process, native exit or final result available'
    SynthesisReexecuted=$false;HardwareValidated=$false
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'resume.json') -Encoding utf8
$launcher=Join-Path $run 'phy_1.launch.tcl'
@'
if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
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
foreach($candidate in @('Y:','Z:','W:','V:')){if(-not(Test-Path -LiteralPath ($candidate+'/'))){$drive=$candidate;break}}
if(-not $drive){throw 'No free temporary drive'}
& subst.exe $drive $run
if($LASTEXITCODE -ne 0){throw 'SUBST failed'}
try{
    $stdout=Join-Path $run 'phy_1.stdout.log';$stderr=Join-Path $run 'phy_1.stderr.log'
    $start=[datetime]::UtcNow
    $process=Start-Process -FilePath $tool -ArgumentList ('"{0}/phy_1.launch.tcl"' -f $drive) -WorkingDirectory ($drive+'/td_project/camera_to_dsi_display_Runs/phy_1') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    [ordered]@{StartedAtUtc=$start.ToString('o');PID=$process.Id;Tool=$tool;ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash;HardwareValidated=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'started.json') -Encoding utf8
    Write-Output "T017_RESUME_PHY PID=$($process.Id) run=$run"
    $process.WaitForExit();$process.Refresh()
    $marker=Join-Path $cwd '.bitgen.end.f'
    $fresh=(Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $start
    $stages+= [ordered]@{Stage='phy_1';PID=$process.Id;ExitCode=$process.ExitCode;StartedAtUtc=$start.ToString('o');FinishedAtUtc=[datetime]::UtcNow.ToString('o');MarkerFresh=$fresh;Stdout=$stdout;Stderr=$stderr}
    $stages | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'stages.json') -Encoding utf8
    if($process.ExitCode -ne 0 -or -not $fresh -or -not(Select-String -LiteralPath $stdout -SimpleMatch 'PIXEL14_STAGE_OK phy_1' -Quiet)){throw 'Physical stage did not qualify'}
    $changed=@()
    foreach($file in $inputs.Files){
        if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){$changed+=$file.Path}
        if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){$changed+=$file.Snapshot}
    }
    foreach($file in $copied){
        if((Get-FileHash -LiteralPath $file.Source).Hash -ne $file.SHA256 -or (Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){$changed+=$file.Path}
    }
    $bit=Join-Path $cwd 'camera_to_dsi_display.bit'
    [ordered]@{FinishedAtUtc=[datetime]::UtcNow.ToString('o');Bit=$bit;SHA256=(Get-FileHash -LiteralPath $bit).Hash;Bytes=(Get-Item -LiteralPath $bit).Length;Stages=$stages;ChangedInputs=$changed;InheritedSynthesis=$parent;HardwareValidated=$false;TimingQualified=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
    if($changed.Count){throw 'Build inputs changed'}
    Write-Output "T017_RESUME_FINISHED $run"
}catch{
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;Stages=$stages} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'failure.json') -Encoding utf8
    throw
}finally{& subst.exe $drive /d}
