#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$Python='C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
    [string]$RunId='6a50b270'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$run=Join-Path $repo "evidence/sc520-shape27/builds/$RunId"
$tool='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
$reset=Join-Path $run 'reset-shape27-synthesis.json'
if(-not (Test-Path -LiteralPath $run)){throw "Build run missing: $run"}
if(-not (Test-Path -LiteralPath $reset)){throw "T027 reset audit missing: $reset"}
$inputs=Get-Content -Raw -LiteralPath (Join-Path $run 'inputs.json') | ConvertFrom-Json
if($inputs.Files.Count -ne 396 -or $inputs.ManifestSources.Count -ne 121){throw 'Unexpected T027 input count'}
foreach($file in $inputs.Files){
    if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256){throw "Current input changed: $($file.Path)"}
    if($file.Snapshot -and (Get-FileHash -LiteralPath $file.Snapshot).Hash -ne $file.SnapshotSHA256){throw "Snapshot changed: $($file.Snapshot)"}
}
$resetSha=(Get-FileHash -LiteralPath $reset).Hash
$syn=Join-Path $run 'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
if(-not (Test-Path -LiteralPath $syn)){throw 'Synthesis netlist missing'}
$phy=Join-Path $run 'td_project/camera_to_dsi_display_Runs/phy_1'
$marker=Join-Path $phy '.opt_route.end.f'
if(Test-Path -LiteralPath $marker){throw 'Stale phy marker in unique build'}
if(-not (Test-Path -LiteralPath $tool)){throw 'TD 6.2.1 required'}
$drive=''
foreach($candidate in @('V:','U:','T:','S:','R:')){
    $occupied=@(Get-CimInstance Win32_LogicalDisk | ForEach-Object DeviceID)
    if($candidate -notin $occupied -and -not (Test-Path -LiteralPath ($candidate+'/'))){$drive=$candidate;break}
}
if(-not $drive){throw 'No free temporary drive'}
& subst.exe $drive $run
if($LASTEXITCODE -ne 0){throw 'Cannot create temporary drive'}
$started=[datetime]::UtcNow
$launcher=Join-Path $run 'phy_1.resume.launch.tcl'
$text=@'
if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 if {$end_step ne "opt_route"} {error "T027 requires route-only"}
 proc bitgen {args} {error "T027 bitgen is prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-phy_1-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 source ../../../overlay/report-pixel14-cdc.tcl
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_STAGE_OK phy_1"
exit 0
'@
$text | Set-Content -LiteralPath $launcher -Encoding utf8
$stdout=Join-Path $run 'phy_1.resume.stdout.log'
$stderr=Join-Path $run 'phy_1.resume.stderr.log'
[ordered]@{
    StartedAtUtc=$started.ToString('o'); RunId=$RunId; Owner='Codex /root/shape27_impl_resume T027'
    Tool=$tool; ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash
    SynthesisNetlistSHA256=(Get-FileHash -LiteralPath $syn).Hash
    ResetAuditSHA256=$resetSha; InputManifestSHA256=(Get-FileHash -LiteralPath (Join-Path $run 'inputs.json')).Hash
    HardwareValidated=$false; BitGenerationAllowed=$false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'phy_1.resume.started.json') -Encoding utf8
$shortCwd=$drive+'/td_project/camera_to_dsi_display_Runs/phy_1'
$shortLauncher=$drive+'/phy_1.resume.launch.tcl'
try {
    $process=Start-Process -FilePath $tool -ArgumentList ('"{0}"' -f $shortLauncher) -WorkingDirectory $shortCwd -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    Write-Output "PIXEL14_TD phy_1_resume PID=$($process.Id) run=$run"
    $process.WaitForExit();$process.Refresh()
    $finished=[datetime]::UtcNow
    $fresh=(Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $started
    $status=[ordered]@{
        Stage='phy_1'; PID=$process.Id; ExitCode=$process.ExitCode
        StartedAtUtc=$started.ToString('o'); FinishedAtUtc=$finished.ToString('o')
        MarkerFresh=$fresh; Stdout=$stdout; Stderr=$stderr
        InputsSHA256=(Get-FileHash -LiteralPath (Join-Path $run 'inputs.json')).Hash
        ResetAuditSHA256=$resetSha; HardwareValidated=$false; BitGenerationAllowed=$false
    }
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'phy_1.resume.result.json') -Encoding utf8
    if($process.ExitCode -ne 0 -or -not $fresh){throw "TD phy_1 resume failed"}
    Write-Output "PIXEL14_PHY_RESUME_FINISHED $run"
} catch {
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;RunId=$RunId} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'phy_1.resume.failure.json') -Encoding utf8
    throw
} finally {
    $owned=@(& subst.exe) | Where-Object {$_ -eq ($drive+'\: => '+$run.Replace('/','\'))}
    if($owned){& subst.exe $drive /d}else{Write-Warning 'Mapping changed; leave it intact'}
}
