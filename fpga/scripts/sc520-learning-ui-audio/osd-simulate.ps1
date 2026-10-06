#Requires -Version 7.5
[CmdletBinding()]
param([switch]$Negative)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$output=Join-Path $repo 'evidence/sc520-learning-ui-audio/osd-runs'
[IO.Directory]::CreateDirectory($output) | Out-Null
$negativeValue=if($Negative){1}else{0}
$runid="osd-$negativeValue-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID"
$caseOutput=Join-Path $output $runid
[IO.Directory]::CreateDirectory($caseOutput) | Out-Null
$launch=Join-Path $caseOutput 'launch.log'
$script=(Join-Path $PSScriptRoot 'osd-test.do').Replace('\','/')
$command="set negative $negativeValue; set sim_output {$($caseOutput.Replace('\','/'))}; source {$script}"
$inputs=@(
'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_content.v',
'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_font_rom.v',
'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_osd.v',
'fpga/sim/sc520-learning-ui-audio/tb_learning_osd.sv',
'fpga/sim/sc520-learning-ui-audio/learning_font_reference.svh',
'fpga/sim/sc520-learning-ui-audio/learning_osd_reference.svh',
'fpga/scripts/sc520-learning-ui-audio/osd-test.do',
'fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1')
$hashes=@{}
foreach($inputPath in $inputs){$hashes[$inputPath]=(Get-FileHash -LiteralPath (Join-Path $repo $inputPath)).Hash}
Push-Location $caseOutput
try{
    & 'D:/modeltech64_10.7/win64/vsim.exe' -c -l $launch -do $command
    $result=$LASTEXITCODE
}finally{Pop-Location}
foreach($inputPath in $inputs){if((Get-FileHash -LiteralPath (Join-Path $repo $inputPath)).Hash -ne $hashes[$inputPath]){throw 'Simulation input changed during run'}}
$summaryPath=Join-Path $caseOutput 'summary.json'
$summaryHash=if(Test-Path -LiteralPath $summaryPath){(Get-FileHash -LiteralPath $summaryPath).Hash}else{$null}
@{Negative=[bool]$Negative;ExitCode=$result;ExpectedExitCode=$negativeValue;Command=$command;LaunchLog=$launch;Summary=$summaryPath;SummarySHA256=$summaryHash;InputSHA256=$hashes;Kind='RTL simulation only; not hardware evidence'} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $caseOutput 'run-manifest.json') -Encoding utf8
Write-Output "OSD_SIM_EXIT negative=$negativeValue exit=$result output=$caseOutput"
exit $result
