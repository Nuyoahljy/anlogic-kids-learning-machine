[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$TaskId,

    [string]$Owner = '未指定',

    [string]$BaseBranch = 'main'
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = & git -C $RepoRoot @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') 执行失败：`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Set-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepoParent = Split-Path -Parent $RepoRoot
$ProjectName = Split-Path -Leaf $RepoRoot
$WorktreeRoot = Join-Path $RepoParent (Join-Path 'worktrees' $ProjectName)
$WorktreePath = Join-Path $WorktreeRoot $TaskId
$BranchName = "task/$TaskId"
$LogRelativePath = "memory/branches/$TaskId.md"
$LogPathInMain = Join-Path $RepoRoot $LogRelativePath

$currentBranch = (Invoke-Git -Arguments @('branch', '--show-current')).Output.Trim()
if ($currentBranch -ne $BaseBranch) {
    throw "必须在 $BaseBranch 分支运行。当前分支：$currentBranch"
}

$status = (Invoke-Git -Arguments @('status', '--porcelain')).Output
if ($status.Count -gt 0) {
    throw '主仓库存在未提交修改。请先提交或处理后再创建 Worktree。'
}

if (-not (Test-Path -LiteralPath $LogPathInMain -PathType Leaf)) {
    throw "找不到分支日志：$LogPathInMain。请先在 main 中从模板创建任务日志。"
}

$branchCheck = Invoke-Git -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$BranchName") -AllowFailure
if ($branchCheck.ExitCode -eq 0) {
    throw "分支已存在：$BranchName"
}

if (Test-Path -LiteralPath $WorktreePath) {
    throw "Worktree 路径已存在：$WorktreePath"
}

$baseCommit = (Invoke-Git -Arguments @('rev-parse', '--short', "$BaseBranch^{commit}")).Output.Trim()

$action = "创建分支 $BranchName 和 Worktree $WorktreePath，并启动任务 $TaskId"

if (-not $PSCmdlet.ShouldProcess($WorktreePath, $action)) {
    return
}

New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null

Invoke-Git -Arguments @('branch', $BranchName, $BaseBranch) | Out-Null
Invoke-Git -Arguments @('worktree', 'add', $WorktreePath, $BranchName) | Out-Null

$branchLogPath = Join-Path $WorktreePath $LogRelativePath
if (-not (Test-Path -LiteralPath $branchLogPath -PathType Leaf)) {
    throw "Worktree 中缺少分支日志：$branchLogPath"
}

try {
    $content = [System.IO.File]::ReadAllText($branchLogPath)
    $startedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $content = $content -replace '(?m)^- 状态：.*$', '- 状态：进行中'
    $content = $content -replace '(?m)^- 负责人：.*$', "- 负责人：$Owner"
    $content = $content -replace '(?m)^- 分支：.*$', "- 分支：$BranchName"
    $content = $content -replace '(?m)^- 基础提交：.*$', "- 基础提交：$baseCommit"
    $content = $content -replace '(?m)^- 开始时间：.*$', "- 开始时间：$startedAt"

    Set-Utf8NoBom -Path $branchLogPath -Content $content

    Invoke-Git -Arguments @('add', '--', $LogRelativePath) | Out-Null
    Invoke-Git -Arguments @('commit', '-m', "chore($TaskId): start task") | Out-Null
}
catch {
    Write-Warning "Worktree 已创建，但启动日志提交失败：$($_.Exception.Message)"
    Write-Warning "可进入 $WorktreePath 后手工检查并提交。"
    throw
}

$commit = (Invoke-Git -Arguments @('rev-parse', '--short', 'HEAD')).Output.Trim()

Write-Host ''
Write-Host '任务 Worktree 已创建。' -ForegroundColor Green
Write-Host "任务：$TaskId"
Write-Host "分支：$BranchName"
Write-Host "目录：$WorktreePath"
Write-Host "启动提交：$commit"
Write-Host ''
Write-Host '下一步：在该目录发起分支对话，并先读取 AGENTS.md 和分支日志。'

