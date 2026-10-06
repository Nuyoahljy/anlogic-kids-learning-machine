#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string]$Validation,[string]$Status='开发中，未上板验证')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workspace = 'E:/juan/FPGA'
$evidence = Join-Path $repo 'evidence/sc520-osd-demo'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$snapshotPath = Join-Path $evidence 'registration-snapshot.json'
$prior = @{}
if (Test-Path -LiteralPath $snapshotPath) { $prior = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable }
$current = @{}
$changes = [Collections.Generic.List[object]]::new()
$dirs = @('fpga/custom_project/sc520-osd-demo','fpga/scripts/sc520-osd-demo','fpga/sim/sc520-osd-demo','evidence/sc520-osd-demo')
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
        $changes.Add(@{Path=$file.FullName;Action=$action;Purpose="SC520中文OSD与内置测试任务文件：$relative";Status=$Status})
    }
}
$log = Join-Path $repo 'memory/branches/sc520-osd-demo.md'
$logAction=if($prior.ContainsKey($log)){'modified'}else{'added'}
$current[$log]=(Get-FileHash -LiteralPath $log).Hash
$changes.Add(@{Path=$log;Action=$logAction;Purpose='本分支进展、验证边界和交接日志';Status=$Status})
$guide=Join-Path $workspace 'learning/sc520-osd-demo/README.md'
if(Test-Path -LiteralPath $guide){
    $guideAction=if($prior.ContainsKey($guide)){'modified'}else{'added'}
    $current[$guide]=(Get-FileHash -LiteralPath $guide).Hash
    $changes.Add(@{Path=$guide;Action=$guideAction;Purpose='本任务教学与用户上板验证导读';Status=$Status})
}
foreach ($dir in @('fpga/custom_project/sc520-osd-demo/td_project/camera_to_dsi_display_Runs','evidence/sc520-osd-demo/builds','evidence/sc520-osd-demo/sim-runs')) {
    $absolute = Join-Path $repo $dir
    if (Test-Path -LiteralPath $absolute) { $changes.Add(@{Path=$absolute;Action='generated';Purpose="独立构建或测试目录：$dir；实际命令和结果见Validation及分支日志";Status=$Status}) }
}
$unexpected=Join-Path $repo '%SystemDrive%'
if(Test-Path -LiteralPath $unexpected){
    $changes.Add(@{Path=$unexpected;Action='observed';Purpose='上一轮已登记的Windows Caches目录，本轮保留原位；具体生成进程仍未确认，不冒称本轮新建，不纳入工程、候选或提交';Status='待归属核查，非项目源码或验证证据'})
}
$current | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $snapshotPath -Encoding utf8
$changes.Add(@{Path=$snapshotPath;Action='generated';Purpose='本任务文件哈希登记快照，不包含其他任务';Status=$Status})
$now = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow, 'China Standard Time')
$id = '{0}-sc520-osd-demo-{1}-{2}' -f $now.ToString('yyyyMMdd-HHmmss'),$Phase,([guid]::NewGuid().ToString('N').Substring(0,6))
$record = Join-Path $workspace "workspace-records/$id.json"
$changes.Add(@{Path=$record;Action='added';Purpose='本批独立登记';Status='已登记，不代表上板通过'})
$changes.Add(@{Path=(Join-Path $workspace 'FILE_INDEX.md');Action='generated';Purpose='统一脚本加锁汇总本批文件登记';Status='以生成与Check结果为准'})
@{Id=$id;UpdatedAt=$now.ToString('o');Task='sc520-osd-demo';Owner='开发对话 01a0fffd-0eb9-7010-9921-5b66e6c1f7d2';Workdir=$repo;Summary=$Phase;Validation=$Validation;NextStep='中文OSD内置测试候选等待用户SRAM验证；测试源不是摄像头实物证据，旧形状版保持待实物验证，保留回退，不改main';Changes=$changes} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $record -Encoding utf8
& (Join-Path $workspace 'anlogic-kids-learning-machine/tools/update-workspace-index.ps1')
if (-not $?) { throw 'Index generation failed' }
& (Join-Path $workspace 'anlogic-kids-learning-machine/tools/update-workspace-index.ps1') -Check
if (-not $?) { throw 'Index check failed' }
Write-Output $record
