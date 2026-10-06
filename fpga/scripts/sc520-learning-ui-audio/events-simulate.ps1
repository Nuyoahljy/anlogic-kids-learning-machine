#Requires -Version 7.5
[CmdletBinding()]
param([switch]$Negative)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$now=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time')
$mode=if($Negative){'negative'}else{'normal'}
$runName='{0}-{1}-{2}-{3}' -f $mode,$now.ToString('yyyyMMdd-HHmmss'),$PID,([guid]::NewGuid().ToString('N').Substring(0,6))
$output=Join-Path $repo "evidence/sc520-learning-ui-audio/events-runs/$runName"
[IO.Directory]::CreateDirectory($output) | Out-Null
$inputs=@('fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/detection_adapter.v',
 'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_events.v',
 'fpga/sim/sc520-learning-ui-audio/tb_events.sv',
 'fpga/scripts/sc520-learning-ui-audio/events-test.do',
 'fpga/scripts/sc520-learning-ui-audio/events-simulate.ps1',
 'evidence/sc520-shape/candidates/sc520_shape.bit',
 'evidence/sc520-osd-demo/candidates/sc520_osd_demo.bit')
$before=[ordered]@{}
foreach($path in $inputs){$before[$path]=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash}
$negativeValue=if($Negative){1}else{0}
$macro=(Join-Path $PSScriptRoot 'events-test.do').Replace('\','/')
$command="set negative $negativeValue; set sim_output {$($output.Replace('\','/'))}; source {$macro}"
$simulator='D:/modeltech64_10.7/win64/vsim.exe'
$launch=Join-Path $output 'launch.log'
Push-Location $output
try {
    & $simulator -c -l $launch -do $command
    $result=$LASTEXITCODE
} finally {Pop-Location}
$after=[ordered]@{}
$changed=@()
foreach($path in $inputs){
    $after[$path]=(Get-FileHash -LiteralPath (Join-Path $repo $path)).Hash
    if($after[$path] -ne $before[$path]){$changed+=$path}
}
$summary=Join-Path $output 'summary.json'
$summaryData=if(Test-Path -LiteralPath $summary){Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json -AsHashtable}else{$null}
$manifest=[ordered]@{Timestamp=$now.ToString('o');Owner='event_verification';Simulator=$simulator;
    Command="& '$simulator' -c -l '$launch' -do '$command'";WorkingDirectory=$output;
    Negative=[bool]$Negative;ExitCode=$result;ExpectedExitCode=$negativeValue;
    Summary=$summaryData;SourceSHA256Before=$before;SourceSHA256After=$after;ChangedInputs=$changed}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'run-manifest.json') -Encoding utf8
Write-Output "EVENTS_SIM_EXIT mode=$mode exit=$result changed=$($changed.Count) output=$output"
if($changed.Count -gt 0){throw 'Simulation input changed during run; evidence cannot qualify the new source'}
if(-not $summaryData){throw 'Simulation did not write a completion summary'}
exit $result
