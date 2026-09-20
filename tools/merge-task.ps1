[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$TaskId,

    [Parameter(Mandatory = $true)]
    [string]$AcceptanceEvidence,

    [string]$BaseBranch = 'main',

    [string]$Tag = '',

    [switch]$RemoveWorktree
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

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepoParent = Split-Path -Parent $RepoRoot
$ProjectName = Split-Path -Leaf $RepoRoot
$WorktreeRoot = Join-Path $RepoParent (Join-Path 'worktrees' $ProjectName)
$WorktreePath = Join-Path $WorktreeRoot $TaskId
$BranchName = "task/$TaskId"
$LogRelativePath = "memory/branches/$TaskId.md"

$currentBranch = (Invoke-Git -Arguments @('branch', '--show-current')).Output.Trim()
if ($currentBranch -ne $BaseBranch) {
    throw "只能在 $BaseBranch 分支合并。当前分支：$currentBranch"
}

$status = (Invoke-Git -Arguments @('status', '--porcelain')).Output
if ($status.Count -gt 0) {
    throw '主仓库存在未提交修改。合并前必须先处理。'
}

$branchCheck = Invoke-Git -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$BranchName") -AllowFailure
if ($branchCheck.ExitCode -ne 0) {
    throw "任务分支不存在：$BranchName"
}

$logResult = Invoke-Git -Arguments @('show', "${BranchName}:$LogRelativePath")
$logContent = ($logResult.Output -join [Environment]::NewLine)
if ($logContent -notmatch '(?m)^- 状态：等待主对话审核\s*$') {
    throw ('分支 ' + $BranchName + ' 尚未标记为等待主对话审核。')
}

if ([System.IO.Path]::IsPathRooted($AcceptanceEvidence)) {
    $evidencePath = $AcceptanceEvidence
}
else {
    $evidencePath = Join-Path $RepoRoot $AcceptanceEvidence
}

if (-not (Test-Path -LiteralPath $evidencePath)) {
    throw "验收证据不存在：$evidencePath"
}

if ($Tag -and $Tag -notmatch '^[A-Za-z0-9._/-]+$') {
    throw "标签名称不合法：$Tag"
}

if ($Tag) {
    $tagCheckBeforeMerge = Invoke-Git -Arguments @('show-ref', '--verify', '--quiet', "refs/tags/$Tag") -AllowFailure
    if ($tagCheckBeforeMerge.ExitCode -eq 0) {
        throw "标签已存在：$Tag"
    }
}

$action = "将分支 $BranchName 以 --no-ff 合并到 $BaseBranch"
if (-not $PSCmdlet.ShouldProcess($RepoRoot, $action)) {
    return
}

try {
    Invoke-Git -Arguments @('merge', '--no-ff', $BranchName, '-m', "merge: $TaskId") | Out-Null
}
catch {
    Write-Warning "合并失败或出现冲突。解决冲突后继续，或运行：git -C `"$RepoRoot`" merge --abort"
    throw
}

$mergeCommit = (Invoke-Git -Arguments @('rev-parse', '--short', 'HEAD')).Output.Trim()

if ($Tag) {
    Invoke-Git -Arguments @('tag', $Tag) | Out-Null
}

if ($RemoveWorktree) {
    if (Test-Path -LiteralPath $WorktreePath) {
        Invoke-Git -Arguments @('worktree', 'remove', $WorktreePath) | Out-Null
    }
}

Write-Host ''
Write-Host '任务分支已合并。' -ForegroundColor Green
Write-Host "任务：$TaskId"
Write-Host "合并提交：$mergeCommit"
if ($Tag) {
    Write-Host "标签：$Tag"
}
Write-Host ''
Write-Host '主对话仍需更新 PROJECT_MEMORY.md、TASKS.md、DECISIONS.md、CHANGELOG.md 和相关稳定文档。'
