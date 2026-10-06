#Requires -Version 7.5
[CmdletBinding()]
param([ValidateSet('before-fix','after-fix')][string]$Phase='after-fix')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$now=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time')
$name='{0}-{1}-{2}-{3}' -f $Phase,$now.ToString('yyyyMMdd-HHmmss'),$PID,([guid]::NewGuid().ToString('N').Substring(0,6))
$output=Join-Path $repo "evidence/sc520-learning-ui-audio/transition-runs/$name"
[IO.Directory]::CreateDirectory($output) | Out-Null
$hdl='fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source'
$inputs=@('fpga/sim/sc520-learning-ui-audio/tb_transition.sv','fpga/scripts/sc520-learning-ui-audio/transition-test.do','fpga/scripts/sc520-learning-ui-audio/transition-simulate.ps1')
$inputs+=@('pixel_coord_adapter','rgb_color_segment','shape_classifier','shape_confirm','color_bbox_stats','bbox_stabilizer','demo_sequence','demo_pattern','osd_font_rom','chinese_osd') | ForEach-Object {"$hdl/roi/$_.v"}
$inputs+=Get-ChildItem -LiteralPath (Join-Path $repo "$hdl/learning") -Filter '*.v' -File | ForEach-Object {[IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/')}
$inputs+=@('evidence/sc520-shape/candidates/sc520_shape.bit','evidence/sc520-osd-demo/candidates/sc520_osd_demo.bit')
$before=[ordered]@{}
foreach($path in $inputs){$before[$path]=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
# Preserve the exact wrapper needed to reproduce the before-fix integration bug.
Copy-Item -LiteralPath (Join-Path $repo "$hdl/learning/hdmi_learning.v") -Destination (Join-Path $output 'hdmi_learning.snapshot.v')
$macro=(Join-Path $PSScriptRoot 'transition-test.do').Replace('\','/')
$command="set sim_output {$($output.Replace('\','/'))}; source {$macro}"
$simulator='D:/modeltech64_10.7/win64/vsim.exe'
$launch=Join-Path $output 'launch.log'
Push-Location $output
try {& $simulator -c -l $launch -do $command; $result=$LASTEXITCODE} finally {Pop-Location}
$after=[ordered]@{};$changed=@()
foreach($path in $inputs){$after[$path]=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash;if($after[$path] -ne $before[$path]){$changed+=$path}}
$summary=Join-Path $output 'summary.json'
$summaryData=if(Test-Path -LiteralPath $summary){Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json -AsHashtable}else{$null}
$artifacts=[ordered]@{}
foreach($file in @('summary.json','transcript.log','launch.log','transition.wlf','hdmi_learning.snapshot.v')){
    $absolute=Join-Path $output $file
    if(Test-Path -LiteralPath $absolute){$artifacts[$file]=@{Path=$absolute;SHA256=(Get-FileHash -LiteralPath $absolute).Hash;Bytes=(Get-Item -LiteralPath $absolute).Length}}
}
@{Timestamp=$now.ToString('o');Owner='event_verification';Phase=$Phase;Simulator=$simulator;
    Command="& '$simulator' -c -l '$launch' -do '$command'";WorkingDirectory=$output;
    ExitCode=$result;ExpectedExitCode=$(if($Phase -eq 'before-fix'){1}else{0});Summary=$summaryData;
    SourceSHA256Before=$before;SourceSHA256After=$after;ChangedInputs=$changed;Artifacts=$artifacts} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'run-manifest.json') -Encoding utf8
Write-Output "TRANSITION_SIM_EXIT phase=$Phase exit=$result changed=$($changed.Count) output=$output"
if($changed.Count -gt 0){throw 'Simulation input changed during run'}
if(-not $summaryData){throw 'Simulation did not write a summary'}
exit $result
