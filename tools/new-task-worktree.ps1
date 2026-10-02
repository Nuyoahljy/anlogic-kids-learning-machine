#Requires -Version 7.5
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [string]$Owner = '',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseBranch = 'main',
    [string]$PolicyRef = '',
    [string]$WorktreeRoot = ''
)
. (Join-Path $PSScriptRoot 'task-common.ps1')
try {
    $root = Get-TaskRoot $RepoRoot
    Assert-TaskId $TaskId
    $branch = (Invoke-TaskGit $root @('branch', '--show-current')).Trim()
    if ($branch -cne $BaseBranch -or $branch -ceq "task/$TaskId") { throw "Run from BaseBranch checkout: $BaseBranch" }
    if ((Invoke-TaskGit $root @('status', '--porcelain=v1', '--untracked-files=all')).Length) { throw 'Base checkout is dirty.' }
    $policy = Get-TaskPolicy $root $TaskId $BaseBranch $PolicyRef
    if (-not $Owner) { $Owner = $policy.Card.Owner }
    if ($Owner -cne $policy.Card.Owner) { throw 'Owner does not match trusted task card.' }
    $null = Assert-TaskLog $root $TaskId -AllowPendingIdentity
    $logRelative = "memory/branches/$TaskId.md"
    Assert-TaskOwned $logRelative $policy.Card
    $null = Invoke-TaskGit $root @('show', "$($policy.BaseCommit):$logRelative")
    $null = Invoke-TaskGit $root @('show', "$($policy.BaseCommit):memory/tasks/$TaskId.json")
    if (-not $WorktreeRoot) {
        $common = (Invoke-TaskGit $root @('rev-parse', '--path-format=absolute', '--git-common-dir')).Trim()
        $primary = Split-Path -Parent $common
        $WorktreeRoot = Join-Path (Split-Path -Parent $primary) (Join-Path 'worktrees' (Split-Path -Leaf $primary))
    }
    $workRoot = [IO.Path]::GetFullPath($WorktreeRoot)
    Assert-NoTaskLink $workRoot
    if ($workRoot -eq $root -or $workRoot.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'WorktreeRoot must be outside the base checkout.' }
    $target = [IO.Path]::GetFullPath((Join-Path $workRoot $TaskId))
    if (-not $target.StartsWith($workRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe worktree target.' }
    Assert-NoTaskLink $target
    if (Test-Path -LiteralPath $target) { throw "Target exists: $target" }
    $branches = Invoke-TaskGit $root @('for-each-ref', '--format=%(refname:short)', 'refs/heads/')
    if (@($branches.Trim().Split("`n") | Where-Object { $_.Trim() -ieq "task/$TaskId" }).Count) { throw 'Task branch already exists.' }
    $beforeHead = (Invoke-TaskGit $root @('rev-parse', 'HEAD')).Trim()
    if (-not $PSCmdlet.ShouldProcess($target, "Create task/$TaskId and commit its startup log only in the new checkout")) { return }
    $null = New-Item -ItemType Directory -Path $workRoot -Force
    $null = Invoke-TaskGit $root @('worktree', 'add', '-b', "task/$TaskId", $target, $policy.BaseCommit)
    $logPath = Get-TaskFile $target $logRelative
    $content = Get-Content -LiteralPath $logPath -Raw
    $values = @{ '任务 ID' = $TaskId; '状态' = '进行中'; '负责人' = $Owner; '分支' = "task/$TaskId"; '基础提交' = $beforeHead; '开始时间' = (Get-TaskTime); '结束时间' = '待完成' }
    foreach ($field in $values.Keys) {
        $replacement = "- ${field}：$($values[$field])"
        $content = [regex]::Replace($content, "(?m)^- ${field}：[^\r\n]+", [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
    }
    [IO.File]::WriteAllText($logPath, $content, [Text.UTF8Encoding]::new($false))
    $null = Invoke-TaskGit $target @('add', '--', $logRelative)
    $null = Invoke-TaskGit $target @('commit', '-m', "chore($TaskId): start task")
    if ((Invoke-TaskGit $root @('rev-parse', 'HEAD')).Trim() -cne $beforeHead -or (Invoke-TaskGit $root @('status', '--porcelain=v1', '--untracked-files=all')).Length) { throw 'Base checkout changed concurrently; inspect it without resetting.' }
    [pscustomobject]@{ TaskId = $TaskId; Worktree = $target; Branch = "task/$TaskId"; Head = (Invoke-TaskGit $target @('rev-parse', 'HEAD')).Trim(); BaseHeadUnchanged = $true }
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
