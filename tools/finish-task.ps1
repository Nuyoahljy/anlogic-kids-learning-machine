[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$TaskId,

    [string]$BaseBranch = 'main',

    [string]$CommitMessage = ''
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = & git @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') 执行失败：`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Get-ChangedPaths {
    $paths = New-Object System.Collections.Generic.HashSet[string]

    $commands = @(
        @('diff', '--name-only', "$BaseBranch...HEAD"),
        @('diff', '--name-only'),
        @('diff', '--cached', '--name-only'),
        @('ls-files', '--others', '--exclude-standard')
    )

    foreach ($command in $commands) {
        $result = Invoke-Git -Arguments $command -AllowFailure
        if ($result.ExitCode -ne 0) {
            continue
        }

        foreach ($line in $result.Output) {
            $path = ([string]$line).Trim()
            if ($path) {
                [void]$paths.Add($path.Replace('\', '/'))
            }
        }
    }

    return @($paths)
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$currentRoot = (Invoke-Git -Arguments @('rev-parse', '--show-toplevel')).Output.Trim()

if ((Resolve-Path $currentRoot).Path -ne $RepoRoot) {
    throw '当前目录不是项目 Worktree 根目录。'
}

$currentBranch = (Invoke-Git -Arguments @('branch', '--show-current')).Output.Trim()
$expectedBranch = "task/$TaskId"

if ($currentBranch -ne $expectedBranch) {
    throw "当前分支为 $currentBranch，预期为 $expectedBranch。"
}

$logRelativePath = "memory/branches/$TaskId.md"
$logPath = Join-Path $RepoRoot $logRelativePath

if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "找不到分支日志：$logPath"
}

$logContent = [System.IO.File]::ReadAllText($logPath)
if ($logContent -notmatch '(?m)^- 状态：等待主对话审核\s*$') {
    throw '分支日志状态尚未改为“等待主对话审核”。'
}

$requiredFields = @(
    '目标与验收条件',
    '修改文件',
    '验证命令与结果',
    '证据路径',
    '阻塞与风险',
    '待决策事项',
    '建议总文档更新',
    '下一分支交接'
)

foreach ($field in $requiredFields) {
    if ($logContent -notmatch [regex]::Escape("## $field")) {
        throw "分支日志缺少字段：$field"
    }
}

$changedPaths = Get-ChangedPaths
if ($changedPaths.Count -eq 0) {
    throw '没有可提交的变化。'
}

$escapedTaskId = [regex]::Escape($TaskId)
$allowedPatterns = @(
    "^memory/branches/$escapedTaskId\.md$",
    "^evidence/$escapedTaskId/",
    '^fpga/',
    '^assets/',
    '^hardware/'
)

$forbidden = @()
foreach ($path in $changedPaths) {
    $allowed = $false
    foreach ($pattern in $allowedPatterns) {
        if ($path -match $pattern) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        $forbidden += $path
    }
}

if ($forbidden.Count -gt 0) {
    $list = $forbidden -join [Environment]::NewLine
    throw "检测到任务范围外的修改：`n$list`n请迁移到正确分支，或由主对话在 main 中处理。"
}

if (-not $CommitMessage) {
    $CommitMessage = "feat($TaskId): complete task"
}

$action = "提交 $($changedPaths.Count) 个任务文件到 $currentBranch"
if (-not $PSCmdlet.ShouldProcess($RepoRoot, $action)) {
    return
}

Invoke-Git -Arguments @('add', '--all') | Out-Null
Invoke-Git -Arguments @('commit', '-m', $CommitMessage) | Out-Null
$commit = (Invoke-Git -Arguments @('rev-parse', '--short', 'HEAD')).Output.Trim()

Write-Host ''
Write-Host '任务分支已提交，等待主对话审核。' -ForegroundColor Green
Write-Host "任务：$TaskId"
Write-Host "分支：$currentBranch"
Write-Host "提交：$commit"
Write-Host ''
Write-Host '下一步：把提交号和验收证据回报主对话，由主对话执行 merge-task.ps1。'

