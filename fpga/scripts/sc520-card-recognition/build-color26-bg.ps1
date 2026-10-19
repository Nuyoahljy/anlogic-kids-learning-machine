#Requires -Version 7.5
[CmdletBinding()]
param([string]$Python='C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',[string]$RunId='')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$tool='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
if (-not $RunId) {$RunId=[guid]::NewGuid().ToString('N').Substring(0,8)}
if ($RunId -notmatch '^[a-f0-9]{8}$') {throw 'RunId must be eight lowercase hexadecimal characters'}
$run=Join-Path $repo "evidence/sc520-color-integration/builds/$RunId"
if (-not (Test-Path -LiteralPath $tool)) {throw 'TD 6.2.1 required'}
& $Python -B -X utf8 (Join-Path $PSScriptRoot 'prepare-color26-bg.py') --snapshot $run
if ($LASTEXITCODE -ne 0) {throw 'Snapshot preparation failed'}
$started=[datetime]::UtcNow
$stages=[Collections.Generic.List[object]]::new()
[string]$drive=''
foreach($candidate in @('V:','U:','T:','S:','R:')) {
    $occupied=@(Get-CimInstance Win32_LogicalDisk | ForEach-Object DeviceID)
    if($candidate -notin $occupied -and -not (Test-Path -LiteralPath ($candidate+'/'))) {$drive=$candidate;break}
}
if(-not $drive){throw 'No free temporary drive for TD MAX_PATH workaround'}
& subst.exe $drive $run
if($LASTEXITCODE -ne 0){throw 'Cannot create task-scoped SUBST drive'}
[ordered]@{StartedAtUtc=$started.ToString('o');Tool=$tool;ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash;Owner='01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl T026';HardwareValidated=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'started.json') -Encoding utf8
try {
    foreach ($stage in @('syn_1','phy_1')) {
        $cwd=Join-Path $run "td_project/camera_to_dsi_display_Runs/$stage"
        $launcher=Join-Path $run "$stage.launch.tcl"
        $text=@'
if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 if {"__STAGE__" eq "phy_1" && $end_step ne "opt_route"} {error "T026 requires route-only"}
 proc bitgen {args} {error "T026 bitgen is prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-__STAGE__-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 if {"__STAGE__" eq "phy_1"} {source ../../../overlay/report-pixel14-cdc.tcl}
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_STAGE_OK __STAGE__"
exit 0
'@
        $text.Replace('__STAGE__',$stage) | Set-Content -LiteralPath $launcher -Encoding utf8
        $stdout=Join-Path $run "$stage.stdout.log";$stderr=Join-Path $run "$stage.stderr.log"
        $marker=Join-Path $cwd $(if($stage -eq 'syn_1'){'.opt_gate.end.f'}else{'.opt_route.end.f'})
        if(Test-Path -LiteralPath $marker){throw 'Stale marker in unique build'}
        $stageStart=[datetime]::UtcNow
        $shortCwd=$drive+'/td_project/camera_to_dsi_display_Runs/'+$stage
        $shortLauncher=$drive+'/'+$stage+'.launch.tcl'
        $process=Start-Process -FilePath $tool -ArgumentList ('"{0}"' -f $shortLauncher) -WorkingDirectory $shortCwd -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        Write-Output "PIXEL14_TD $stage PID=$($process.Id) run=$run"
        $process.WaitForExit();$process.Refresh();$stageEnd=[datetime]::UtcNow
        $fresh=(Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $stageStart
        $stages.Add([ordered]@{Stage=$stage;PID=$process.Id;ExitCode=$process.ExitCode;StartedAtUtc=$stageStart.ToString('o');FinishedAtUtc=$stageEnd.ToString('o');MarkerFresh=$fresh;Stdout=$stdout;Stderr=$stderr})
        $stages | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'stages.json') -Encoding utf8
        if($process.ExitCode -ne 0 -or -not $fresh -or -not (Select-String -LiteralPath $stdout -SimpleMatch "PIXEL14_STAGE_OK $stage" -Quiet)){throw "TD $stage failed"}
        if($stage -eq 'syn_1'){
            & $Python -B -X utf8 (Join-Path $PSScriptRoot 'audit-timing23-reset.py') $run --output (Join-Path $run 'reset-synthesis.json')
            if($LASTEXITCODE -ne 0){throw 'Preserved reset topology/fanout audit failed; do not place'}
        }
    }
    $inputs=Get-Content -Raw -LiteralPath (Join-Path $run 'inputs.json') | ConvertFrom-Json
    $changed=@()
    foreach($file in $inputs.Files){
        if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){$changed+=$file.Path}
        if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){$changed+=$file.Snapshot}
    }
    $bits=@(Get-ChildItem -LiteralPath $run -Filter '*.bit' -File -Recurse)
    if($bits.Count){throw 'Unexpected test bit output: do not deliver'}
    [ordered]@{FinishedAtUtc=[datetime]::UtcNow.ToString('o');Stages=$stages;ChangedInputs=$changed;BitGenerationAllowed=$false;BitFilesFound=@();TestOnly=$false;HardwareValidated=$false;TimingQualified=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
    if($changed.Count){throw 'Build source mutation detected'}
    Write-Output "PIXEL14_BUILD_FINISHED $run (timing/IO/ROM report review still required)"
} catch {
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;Stages=$stages} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'failure.json') -Encoding utf8
    throw
} finally {
    $owned=@(& subst.exe) | Where-Object {$_ -eq ($drive+'\: => '+$run.Replace('/','\'))}
    if($owned){& subst.exe $drive /d}else{Write-Warning 'Mapping changed; leave it intact'}
}
