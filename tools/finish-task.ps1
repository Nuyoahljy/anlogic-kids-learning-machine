#Requires -Version 7.5
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseBranch = 'main',
    [string]$PolicyRef = '',
    [switch]$Commit,
    [string]$CommitMessage = '',
    [string]$WorkspaceRoot = '',
    [string]$IndexScript = '',
    [string]$AcceptanceReport = ''
)
. (Join-Path $PSScriptRoot 'task-common.ps1')
try {
    $context = Get-TaskContext $RepoRoot $TaskId $BaseBranch $PolicyRef -RequireReady
    if ($AcceptanceReport) { $null = Test-TaskReport $context $AcceptanceReport }
    if (-not $Commit) {
        [pscustomobject]@{ TaskId = $TaskId; Head = $context.Head; State = $context.State; Action = 'CheckedOnly'; DirtyPaths = $context.Changes.DirtyPaths; Acceptance = $(if ($AcceptanceReport) { 'script_checks_passed' } else { 'not_requested' }) }
        return
    }
    if (-not $WorkspaceRoot -or -not $IndexScript -or -not [IO.Path]::IsPathFullyQualified($WorkspaceRoot) -or -not [IO.Path]::IsPathFullyQualified($IndexScript)) { throw 'Commit requires absolute WorkspaceRoot and primary IndexScript.' }
    $common = (Invoke-TaskGit $context.Root @('rev-parse', '--path-format=absolute', '--git-common-dir')).Trim()
    $expectedIndex = Join-Path (Split-Path -Parent $common) 'tools/update-workspace-index.ps1'
    if ([IO.Path]::GetFullPath($IndexScript) -ne [IO.Path]::GetFullPath($expectedIndex)) { throw 'IndexScript must be tools/update-workspace-index.ps1 in the primary checkout.' }
    Assert-NoTaskLink $IndexScript
    Assert-NoTaskLink $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $IndexScript -PathType Leaf) -or -not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) { throw 'Missing local workspace/index script.' }
    $checkedIndex = Invoke-TaskProcess 'pwsh' @('-NoProfile', '-File', $IndexScript, '-WorkspaceRoot', $WorkspaceRoot, '-Check') $context.Root
    if ($checkedIndex.ExitCode -ne 0) { throw "Workspace index -Check failed: $($checkedIndex.Stdout) $($checkedIndex.Stderr)" }
    if ($context.Changes.DirtyPaths.Count -eq 0) {
        [pscustomobject]@{ TaskId = $TaskId; Head = $context.Head; Action = 'AlreadyCommitted' }
        return
    }
    foreach ($path in $context.Changes.DirtyPaths) {
        $full = Get-TaskFile $context.Root $path -DirectoryAllowed
        if (Test-Path -LiteralPath $full -PathType Container) { throw "Directory/submodule cannot be staged implicitly: $path" }
        if ($path.StartsWith("evidence/$TaskId/runs/", [StringComparison]::Ordinal)) { throw 'Run outputs must stay outside source commits; configure the coordinator-approved ignore rule.' }
    }
    if (-not $CommitMessage) { $CommitMessage = "feat($TaskId): complete task" }
    if (-not $PSCmdlet.ShouldProcess($context.Root, 'Stage exact approved paths and commit the task branch')) { return }
    $rechecked = Get-TaskContext $context.Root $TaskId $BaseBranch $PolicyRef -RequireReady
    if ($rechecked.Head -cne $context.Head -or $rechecked.Changes.Status -cne $context.Changes.Status -or $rechecked.Policy.PolicyCommit -cne $context.Policy.PolicyCommit) { throw 'Task changed during preflight.' }
    $null = Invoke-TaskGit $context.Root (@('add', '--') + $context.Changes.DirtyPaths)
    $null = Invoke-TaskGit $context.Root @('commit', '-m', $CommitMessage)
    [pscustomobject]@{ TaskId = $TaskId; Head = (Invoke-TaskGit $context.Root @('rev-parse', 'HEAD')).Trim(); Action = 'CommittedOnly'; Pushed = $false }
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
