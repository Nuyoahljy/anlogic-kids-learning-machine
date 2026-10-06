#Requires -Version 7.5
[CmdletBinding()]
param([ValidateSet('osd','runtime','video','full')][string]$Testcase='video',[switch]$Negative)
$ErrorActionPreference='Stop'
$quizRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$quizNow=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time')
$quizMode=if($Negative){'negative'}else{'normal'}
$quizRun=Join-Path $quizRepo ('evidence/sc520-quiz-video/runs/{0}-{1}-{2}-{3}' -f $Testcase,$quizMode,$quizNow.ToString('yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,8))
$quizHdl='fpga/custom_project/sc520-quiz-video/user_source/hdl_source'
$quizFiles=@(); $quizRefs=@()
if($Testcase -eq 'osd'){
    $quizTop='tb_quiz_osd'; $quizFiles=@('quiz/quiz_osd.v','quiz/quiz_content.v','quiz/quiz_font_rom.v'); $quizRefs=@('quiz_bitmap_reference.svh')
}elseif($Testcase -eq 'runtime'){
    $quizTop='tb_quiz_runtime';$quizFiles=@('quiz/quiz_millisecond_tick.v','quiz/quiz_boot_controls.v','quiz/quiz_mock_player.v')
}else{
    $quizTop='tb_quiz_video';$quizRefs=@('quiz_bitmap_reference.svh')
    $quizFiles=@('roi/pixel_coord_adapter.v','roi/rgb_color_segment.v','roi/color_bbox_stats.v','roi/bbox_stabilizer.v','roi/shape_classifier.v','roi/shape_confirm.v','learning/detection_adapter.v')
    $quizFiles+=Get-ChildItem -LiteralPath (Join-Path $quizRepo "$quizHdl/quiz") -Filter '*.v' -File | ForEach-Object {'quiz/'+$_.Name}
}
$quizPaths=@($quizFiles|ForEach-Object {"$quizHdl/$_"})
$quizPaths+="fpga/sim/sc520-quiz-video/$quizTop.sv"
$quizPaths+=@($quizRefs|ForEach-Object {"fpga/sim/sc520-quiz-video/$_"})
$quizPaths+=@('fpga/scripts/sc520-quiz-video/simulate.ps1','fpga/scripts/sc520-quiz-video/run-sim.do')
$quizBefore=[ordered]@{}
foreach($quizRel in $quizPaths){
    $quizSource=Join-Path $quizRepo $quizRel; $quizDest=Join-Path $quizRun "inputs/$quizRel"
    [IO.Directory]::CreateDirectory((Split-Path $quizDest))|Out-Null
    Copy-Item -LiteralPath $quizSource -Destination $quizDest
    $quizBefore[$quizRel]=(Get-FileHash -LiteralPath $quizDest).Hash
}
$quizSnapshot=(Join-Path $quizRun 'inputs').Replace('\','/')
$quizNeg=if($Negative){1}else{0}; $quizFull=if($Testcase -eq 'full'){1}else{0}
$quizSourceList=($quizFiles|ForEach-Object {"{$quizSnapshot/$quizHdl/$_}"}) -join ' '
$quizCommand="set quiz_root {$quizSnapshot}; set quiz_top $quizTop; set quiz_full $quizFull; set quiz_test $Testcase; set quiz_negative $quizNeg; set quiz_sources [list $quizSourceList]; source {$quizSnapshot/fpga/scripts/sc520-quiz-video/run-sim.do}"
$quizSim='D:/modeltech64_10.7/win64/vsim.exe'
Push-Location $quizRun
try { & $quizSim -c -l transcript.log -do $quizCommand; $quizCode=$LASTEXITCODE } finally{Pop-Location}
$quizAfter=[ordered]@{}; $quizChanged=@()
foreach($quizRel in $quizPaths){$quizAfter[$quizRel]=(Get-FileHash -LiteralPath (Join-Path $quizRepo $quizRel)).Hash;if($quizBefore[$quizRel] -ne $quizAfter[$quizRel]){$quizChanged+=$quizRel}}
$quizSummaryFile=Join-Path $quizRun 'summary.json'
$quizSummary=if(Test-Path -LiteralPath $quizSummaryFile){Get-Content -LiteralPath $quizSummaryFile -Raw|ConvertFrom-Json -AsHashtable}else{$null}
$quizOutputs=[ordered]@{};foreach($quizFile in (Get-ChildItem -LiteralPath $quizRun -File)){$quizOutputs[$quizFile.Name]=(Get-FileHash -LiteralPath $quizFile.FullName).Hash}
[ordered]@{Task='sc520-quiz-video';Owner='01a11124-e100-75e2-9e85-9f9686e23c73';StartedAt=$quizNow.ToString('o');Testcase=$Testcase;Negative=[bool]$Negative;Simulator=$quizSim;Command=$quizCommand;WorkingDirectory=$quizRun;ExitCode=$quizCode;ExpectedExitCode=$quizNeg;Summary=$quizSummary;InputsSHA256=$quizBefore;InputsAfterSHA256=$quizAfter;ChangedInputs=$quizChanged;OutputSHA256=$quizOutputs}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $quizRun 'run-manifest.json') -Encoding utf8
Write-Output "QUIZ_VIDEO_RUN test=$Testcase negative=$quizNeg exit=$quizCode changed=$($quizChanged.Count) path=$quizRun"
if($quizChanged.Count){throw 'Inputs changed while running; result retained but not qualified.'}
if(!$quizSummary -or $quizSummary.done -ne 1){throw 'No completed simulation summary; inspect transcript.'}
exit $quizCode
