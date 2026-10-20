#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Approval,
    [Parameter(Mandatory=$true)][string]$ApprovalSHA256,
    [string]$Python='C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
    [string]$RunId=''
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if((Get-FileHash -LiteralPath $Approval).Hash -ne $ApprovalSHA256.ToUpperInvariant()){throw 'Main approval hash mismatch'}
$accepted=Get-Content -LiteralPath $Approval -Raw | ConvertFrom-Json
if($accepted.Stage -ne 'software_accepted' -or $accepted.Candidate -ne 'D0290' -or -not $accepted.BuildAllowed){throw 'T029 software is not main accepted'}
if($accepted.BitGenerationAllowed -or $accepted.HardwareValidated){throw 'Wrong approval stage'}
foreach($row in @($accepted.SoftwareReview,$accepted.IndependentReview,$accepted.SoftwareManifest)){
    if((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.SHA256){throw 'Accepted review hash mismatch'}
}
$software=Get-Content -LiteralPath $accepted.SoftwareManifest.Path -Raw | ConvertFrom-Json
if(-not $software.SoftwareQualified){throw 'Software not qualified'}
foreach($row in $software.SourceFreeze){
    if((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.SHA256){throw "Frozen source changed: $($row.Path)"}
}
& git -C $repo merge-base --is-ancestor $accepted.SourceCommit HEAD
if($LASTEXITCODE -ne 0){throw 'Accepted source is not an ancestor'}
if(-not $RunId){$RunId=[guid]::NewGuid().ToString('N').Substring(0,8)}
if($RunId -notmatch '^[a-f0-9]{8}$'){throw 'RunId must be eight hexadecimal characters'}
$run=Join-Path $repo "evidence/sc520-contour29/builds/$RunId"
if(Test-Path -LiteralPath $run){throw 'Never overwrite an existing build'}
& $Python -B -X utf8 (Join-Path $PSScriptRoot 'prepare-contour29.py') --snapshot $run
if($LASTEXITCODE -ne 0){throw 'Preparation failed'}
$tool='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
$drive=''
$stages=[Collections.Generic.List[object]]::new()
foreach($candidate in @('U:','T:','S:','R:','V:')){
    if(-not(Test-Path -LiteralPath ($candidate+'/'))){$drive=$candidate;break}
}
if(-not $drive){throw 'No free temporary drive'}
& subst.exe $drive $run
if($LASTEXITCODE -ne 0){throw 'Cannot map unique build'}
try {
    [ordered]@{Owner='Codex /root/shape27_delivery T029';StartedAtUtc=[datetime]::UtcNow.ToString('o');
        Approval=$Approval;ApprovalSHA256=$ApprovalSHA256;Tool=$tool;ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash;
        HardwareValidated=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'started.json') -Encoding utf8
    foreach($stage in @('syn_1','phy_1')){
        $cwd=Join-Path $run "td_project/camera_to_dsi_display_Runs/$stage"
        $launcher=Join-Path $run "$stage.launch.tcl"
        $script=@'
if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 if {"__STAGE__" eq "phy_1" && $end_step ne "opt_route"} {error "T029 requires route-only"}
 proc bitgen {args} {error "T029 bitgen prohibited until main review"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-__STAGE__-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 if {"__STAGE__" eq "phy_1"} {source ../../../overlay/report-pixel14-cdc.tcl}
} message]} {puts stderr $message;exit 1}
puts "PIXEL14_STAGE_OK __STAGE__"
exit 0
'@
        $script.Replace('__STAGE__',$stage) | Set-Content -LiteralPath $launcher -Encoding utf8
        $stdout=Join-Path $run "$stage.stdout.log";$stderr=Join-Path $run "$stage.stderr.log"
        $marker=Join-Path $cwd $(if($stage -eq 'syn_1'){'.opt_gate.end.f'}else{'.opt_route.end.f'})
        if(Test-Path -LiteralPath $marker){throw 'Stale marker'}
        $started=[datetime]::UtcNow
        $proc=Start-Process -FilePath $tool -ArgumentList ('"{0}"' -f ($drive+'/'+$stage+'.launch.tcl')) -WorkingDirectory ($drive+'/td_project/camera_to_dsi_display_Runs/'+$stage) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        Write-Output "T029_TD $stage PID=$($proc.Id)"
        $proc.WaitForExit();$proc.Refresh()
        $fresh=(Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $started
        $stages.Add([ordered]@{Stage=$stage;PID=$proc.Id;ExitCode=$proc.ExitCode;StartedAtUtc=$started.ToString('o');
            FinishedAtUtc=[datetime]::UtcNow.ToString('o');MarkerFresh=$fresh;Stdout=$stdout;Stderr=$stderr})
        $stages | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'stages.json') -Encoding utf8
        if($proc.ExitCode -ne 0 -or -not $fresh -or -not(Select-String -LiteralPath $stdout -SimpleMatch "PIXEL14_STAGE_OK $stage" -Quiet)){throw "T029 $stage failed"}
        if((Get-Item -LiteralPath $stderr).Length -ne 0 -or (Select-String -LiteralPath $stdout -Pattern '\bERROR\b' -Quiet)){throw 'Native errors retained; do not continue'}
        if($stage -eq 'syn_1'){
            & $Python -B -X utf8 (Join-Path $PSScriptRoot 'audit-contour29-reset.py') $run --output (Join-Path $run 'reset-synthesis.json')
            if($LASTEXITCODE -ne 0){throw 'Reset partition audit failed'}
        }
    }
    $inputs=Get-Content -LiteralPath (Join-Path $run 'inputs.json') -Raw | ConvertFrom-Json
    $changed=@()
    foreach($row in $inputs.Files){
        if((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.SHA256){$changed+=$row.Path}
        if($row.Snapshot -and (Get-FileHash -LiteralPath $row.Snapshot).Hash -ne $row.SnapshotSHA256){$changed+=$row.Snapshot}
    }
    if(@(Get-ChildItem -LiteralPath $run -Recurse -Filter '*.bit' -File).Count){throw 'Unexpected bit before main physical review'}
    [ordered]@{FinishedAtUtc=[datetime]::UtcNow.ToString('o');Stages=$stages;ChangedInputs=$changed;BitFilesFound=@();
        BitGenerationAllowed=$false;HardwareValidated=$false;TimingQualified=$false;TestOnly=$false} | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
    if($changed.Count){throw 'Build inputs changed'}
} catch {
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;Stages=$stages} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'failure.json') -Encoding utf8
    throw
} finally {
    $owned=@(& subst.exe) | Where-Object {$_ -eq ($drive+'\: => '+$run.Replace('/','\'))}
    if($owned){& subst.exe $drive /D}
}
