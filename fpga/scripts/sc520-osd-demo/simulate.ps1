#Requires -Version 7.5
[CmdletBinding()]
param([ValidateSet('display','color','sync','stats','stability','capacity','classifier','confirm','shapes','label','sequence','pattern','osd','demo','full')][string]$Testcase='display',[switch]$Negative)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runScript=(Join-Path $PSScriptRoot 'run-sim.do').Replace('\','/')
$negativeValue=if($Negative){1}else{0}
$output=Join-Path $repo 'evidence/sc520-osd-demo/sim-runs'
[IO.Directory]::CreateDirectory($output) | Out-Null
$launch=Join-Path $output ("launch-{0}-{1}-{2}-{3}.log" -f $Testcase,$negativeValue,(Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)
$caseOutput=Join-Path $output ("{0}-{1}-{2}-{3}" -f $Testcase,$negativeValue,(Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)
$command="set testcase $Testcase; set negative $negativeValue; set sim_output {$($caseOutput.Replace('\','/'))}; source $runScript"
$inputs=@("fpga/sim/sc520-osd-demo/tb_$Testcase.sv",'fpga/scripts/sc520-osd-demo/run-sim.do','fpga/scripts/sc520-osd-demo/simulate.ps1','fpga/sim/sc520-osd-demo/color_reference.svh','fpga/sim/sc520-osd-demo/font_reference.svh','fpga/sim/sc520-osd-demo/demo_test_body.svh')
$inputs+=@('roi/pixel_coord_adapter.v','roi/rgb_color_segment.v','roi/hdmi_shape.v','roi/demo_sequence.v','roi/demo_pattern.v','roi/osd_font_rom.v','roi/chinese_osd.v','roi/hdmi_osd_demo.v','roi/shape_classifier.v','roi/shape_confirm.v','roi/shape_label.v','roi/color_bbox_stats.v','roi/bbox_stabilizer.v','vtc/uivtc.v','hdmi_mixer.v') | ForEach-Object { "fpga/custom_project/sc520-osd-demo/user_source/hdl_source/$_" }
$hashes=@{}
foreach($inputPath in $inputs){$hashes[$inputPath]=(Get-FileHash -LiteralPath (Join-Path $repo $inputPath)).Hash}
Push-Location $output
try {
    & 'D:/modeltech64_10.7/win64/vsim.exe' -c -l $launch -do $command
    $result=$LASTEXITCODE
} finally {Pop-Location}
foreach($inputPath in $inputs){if((Get-FileHash -LiteralPath (Join-Path $repo $inputPath)).Hash -ne $hashes[$inputPath]){throw 'Simulation input changed during run'}}
$transcript=Join-Path $caseOutput 'transcript.log'
$summary=Join-Path $caseOutput 'summary.json'
@{Testcase=$Testcase;Negative=[bool]$Negative;ExitCode=$result;ExpectedExitCode=$negativeValue;Command=$command;LaunchLog=$launch;Log=$transcript;LogSHA256=(Get-FileHash -LiteralPath $transcript).Hash;Summary=$summary;SummarySHA256=(Get-FileHash -LiteralPath $summary).Hash;InputSHA256=$hashes} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($launch+'.json') -Encoding utf8
Write-Output "SIM_EXIT testcase=$Testcase negative=$negativeValue exit=$result log=$launch"
exit $result
