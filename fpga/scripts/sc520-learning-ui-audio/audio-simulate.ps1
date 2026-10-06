#Requires -Version 7.5
[CmdletBinding()]
param([switch]$Negative)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$outRoot=Join-Path $repo 'evidence/sc520-learning-ui-audio/audio-runs'
$zone=[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
$now=[TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow,$zone)
$runId=('audio-{0}-{1}-{2}' -f ([int][bool]$Negative),$now.ToString('yyyyMMdd-HHmmss-fff'),$PID)
$run=Join-Path $outRoot $runId
[IO.Directory]::CreateDirectory($run)|Out-Null
$sources=@(
 'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/audio_event_player.v',
 'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/mock_audio_player.v',
 'fpga/sim/sc520-learning-ui-audio/tb_audio.sv',
 'fpga/scripts/sc520-learning-ui-audio/audio-test.do',
 'fpga/scripts/sc520-learning-ui-audio/audio-simulate.ps1'
)
$hashes=[ordered]@{}
foreach($p in $sources){$hashes[$p]=(Get-FileHash -LiteralPath (Join-Path $repo $p) -Algorithm SHA256).Hash}
$script=(Join-Path $PSScriptRoot 'audio-test.do').Replace('\','/')
$command='set negative '+([int][bool]$Negative)+'; set sim_output {'+$run.Replace('\','/')+'}; source {'+$script+'}'
$launch=Join-Path $run 'launch.log'
Push-Location $run
try {
    & 'D:/modeltech64_10.7/win64/vsim.exe' -c -l $launch -do $command
    $exitCode=$LASTEXITCODE
} finally {Pop-Location}
$unchanged=$true
foreach($p in $sources){if((Get-FileHash -LiteralPath (Join-Path $repo $p)).Hash -ne $hashes[$p]){$unchanged=$false}}
$summary=Join-Path $run 'summary.json'
$summaryValue=if(Test-Path -LiteralPath $summary){Get-Content -Raw -LiteralPath $summary | ConvertFrom-Json}else{$null}
$outputHashes=[ordered]@{}
foreach($name in @('summary.json','transcript.log','launch.log','audio.wlf')){
    $path=Join-Path $run $name
    if(Test-Path -LiteralPath $path){$outputHashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
@{RunId=$runId;StartedAt=$now.ToString('o');Tool='D:/modeltech64_10.7/win64/vsim.exe';ToolVersion='ModelSim SE-64 10.7 (verified in transcript)';Negative=[bool]$Negative;ExitCode=$exitCode;ExpectedExitCode=([int][bool]$Negative);Command=$command;SourceSHA256=$hashes;InputsUnchanged=$unchanged;Summary=$summaryValue;SummaryPath=$summary;OutputSHA256=$outputHashes;OutputDirectory=$run} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'manifest.json') -Encoding utf8
Write-Output "AUDIO_SIM_EXIT negative=$([int][bool]$Negative) exit=$exitCode inputsUnchanged=$unchanged output=$run"
if(!$unchanged){throw 'Audio simulation source changed during run'}
exit $exitCode
