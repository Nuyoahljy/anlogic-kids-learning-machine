#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string]$Validation,[string]$Status='开发中，未上板验证')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workspace = 'E:/juan/FPGA'
$evidence = Join-Path $repo 'evidence/sc520-fixed-roi'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$snapshotPath = Join-Path $evidence 'registration-snapshot.json'
$prior = @{}
if (Test-Path -LiteralPath $snapshotPath) { $prior = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable }
$current = @{}
$changes = [Collections.Generic.List[object]]::new()
$dirs = @('fpga/vendor_labs/sc520','fpga/custom_project/sc520','fpga/scripts/sc520-fixed-roi','fpga/sim/sc520-fixed-roi','evidence/sc520-fixed-roi')
foreach ($dir in $dirs) {
    $absolute = Join-Path $repo $dir
    if (-not (Test-Path -LiteralPath $absolute)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $absolute -File -Recurse -Force) {
        $relative = [IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/')
        if ($relative -match '/(builds|sim-runs)/' -or ($relative -match '_Runs/' -and $file.Name -notmatch '^(settings\.cfg|camera_to_dsi_display\.(prj|tcl))$') -or $file.FullName -eq $snapshotPath) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
        $current[$file.FullName] = $hash
        if ($prior.ContainsKey($file.FullName) -and $prior[$file.FullName] -eq $hash) { continue }
        $action = if ($prior.ContainsKey($file.FullName)) {'modified'} else {'added'}
        $changes.Add(@{Path=$file.FullName;Action=$action;Purpose="SC520重建/固定框任务文件：$relative";Status=$Status})
    }
}
$log = Join-Path $repo 'memory/branches/sc520-fixed-roi.md'
$changes.Add(@{Path=$log;Action='modified';Purpose='本分支进展、验证边界和交接日志';Status=$Status})
$guide=Join-Path $workspace 'learning/sc520-fixed-roi/README.md'
if(Test-Path -LiteralPath $guide){
    $guideAction=if($prior.ContainsKey($guide)){'modified'}else{'added'}
    $current[$guide]=(Get-FileHash -LiteralPath $guide).Hash
    $changes.Add(@{Path=$guide;Action=$guideAction;Purpose='本任务教学与用户上板验证导读';Status=$Status})
}
foreach ($dir in @('fpga/vendor_labs/sc520/td_project/camera_to_dsi_display_Runs','fpga/custom_project/sc520/td_project/camera_to_dsi_display_Runs','evidence/sc520-fixed-roi/builds','evidence/sc520-fixed-roi/sim-runs')) {
    $absolute = Join-Path $repo $dir
    if (Test-Path -LiteralPath $absolute) { $changes.Add(@{Path=$absolute;Action='generated';Purpose="独立构建或测试目录：$dir；实际命令和结果见Validation及分支日志";Status=$Status}) }
}
$current | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $snapshotPath -Encoding utf8
$changes.Add(@{Path=$snapshotPath;Action='generated';Purpose='本任务文件哈希登记快照，不包含其他任务';Status=$Status})
$now = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow, 'China Standard Time')
$id = '{0}-sc520-fixed-roi-{1}-{2}' -f $now.ToString('yyyyMMdd-HHmmss'),$Phase,([guid]::NewGuid().ToString('N').Substring(0,6))
$record = Join-Path $workspace "workspace-records/$id.json"
$changes.Add(@{Path=$record;Action='added';Purpose='本批独立登记';Status='已登记，不代表上板通过'})
@{Id=$id;UpdatedAt=$now.ToString('o');Task='sc520-fixed-roi';Owner='开发对话 01a0fc0e-b0fb-7d00-acd6-e71d76358c4f';Workdir=$repo;Summary=$Phase;Validation=$Validation;NextStep='继续本任务；原版与加框候选均等待用户物理验证，不修改main状态';Changes=$changes} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $record -Encoding utf8
& (Join-Path $workspace 'anlogic-kids-learning-machine/tools/update-workspace-index.ps1')
if (-not $?) { throw 'Index generation failed' }
& (Join-Path $workspace 'anlogic-kids-learning-machine/tools/update-workspace-index.ps1') -Check
if (-not $?) { throw 'Index check failed' }
Write-Output $record
