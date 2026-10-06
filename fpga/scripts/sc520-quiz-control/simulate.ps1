#Requires -Version 7.5
[CmdletBinding()]
param(
    [ValidateSet('control','audio','keys','system')][string]$Testcase='control',
    [switch]$Negative,
    [string]$Simulator='D:/modeltech64_10.7/win64/vsim.exe'
)
$ErrorActionPreference='Stop'
$quizRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$quizNow=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time')
$quizMode=if($Negative){'negative'}else{'normal'}
$quizRun=Join-Path $quizRepo ('evidence/sc520-quiz-control/runs/{0}-{1}-{2}-{3}' -f $Testcase,$quizMode,$quizNow.ToString('yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($quizRun) | Out-Null
$quizModules=@{control=@('quiz_control');audio=@('quiz_audio_queue');keys=@('quiz_key_debounce');system=@('quiz_control','quiz_audio_queue')}
$quizTop=@{control='tb_quiz_control';audio='tb_quiz_audio_queue';keys='tb_quiz_key_debounce';system='tb_quiz_system'}[$Testcase]
$quizPaths=@($quizModules[$Testcase] | ForEach-Object {"fpga/custom_project/sc520-quiz-control/$_.v"})
$quizPaths+=@("fpga/sim/sc520-quiz-control/$quizTop.sv",'fpga/scripts/sc520-quiz-control/simulate.ps1','fpga/scripts/sc520-quiz-control/test.do')
$quizBefore=[ordered]@{}
foreach($quizRel in $quizPaths){
    $quizSource=Join-Path $quizRepo $quizRel
    $quizDest=Join-Path $quizRun "inputs/$quizRel"
    [IO.Directory]::CreateDirectory((Split-Path $quizDest)) | Out-Null
    Copy-Item -LiteralPath $quizSource -Destination $quizDest
    $quizBefore[$quizRel]=(Get-FileHash -LiteralPath $quizDest).Hash
}
$quizSnapshot=(Join-Path $quizRun 'inputs').Replace('\','/')
$quizMacro=(Join-Path $quizSnapshot 'fpga/scripts/sc520-quiz-control/test.do').Replace('\','/')
$quizNeg=if($Negative){1}else{0}
$quizCommand="set quiz_root {$quizSnapshot}; set quiz_test $Testcase; set quiz_negative $quizNeg; source {$quizMacro}"
$quizCode=2
Push-Location $quizRun
try { & $Simulator -c -l 'transcript.log' -do $quizCommand; $quizCode=$LASTEXITCODE } finally { Pop-Location }
$quizAfter=[ordered]@{}; $quizChanged=@()
foreach($quizRel in $quizPaths){
    $quizAfter[$quizRel]=(Get-FileHash -LiteralPath (Join-Path $quizRepo $quizRel)).Hash
    if($quizBefore[$quizRel] -ne $quizAfter[$quizRel]){$quizChanged+=$quizRel}
}
$quizSummaryPath=Join-Path $quizRun 'summary.json'
$quizSummary=if(Test-Path -LiteralPath $quizSummaryPath){Get-Content -LiteralPath $quizSummaryPath -Raw | ConvertFrom-Json -AsHashtable}else{$null}
$quizOutputs=[ordered]@{}
foreach($quizFile in (Get-ChildItem -LiteralPath $quizRun -File)){$quizOutputs[$quizFile.Name]=(Get-FileHash -LiteralPath $quizFile.FullName).Hash}
$quizResult=[ordered]@{
    Task='sc520-quiz-control';Owner='01a11124-e100-75e2-9e85-9f9686e23c73';StartedAt=$quizNow.ToString('o');FinishedAt=[DateTimeOffset]::Now.ToString('o');
    Testcase=$Testcase;Negative=[bool]$Negative;Simulator=$Simulator;Command="& '$Simulator' -c -l transcript.log -do '$quizCommand'";
    WorkingDirectory=$quizRun;ExitCode=$quizCode;ExpectedExitCode=$quizNeg;Summary=$quizSummary;
    InputsSHA256=$quizBefore;InputsAfterSHA256=$quizAfter;ChangedInputs=$quizChanged;OutputSHA256=$quizOutputs
}
$quizResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $quizRun 'run-manifest.json') -Encoding utf8
Write-Output "QUIZ_RUN testcase=$Testcase negative=$quizNeg exit=$quizCode changed=$($quizChanged.Count) path=$quizRun"
if($quizChanged.Count -gt 0){throw 'Inputs changed during simulation; rerun current source.'}
if(!$quizSummary -or $quizSummary.done -ne 1){throw 'Simulation did not complete; inspect retained transcript.'}
exit $quizCode
