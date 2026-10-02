#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$PullRequestUrl,
    [Parameter(Mandatory)][string]$AcceptanceReport,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseBranch = 'main',
    [string]$PolicyRef = ''
)
. (Join-Path $PSScriptRoot 'task-common.ps1')
try {
    $context = Get-TaskContext $RepoRoot $TaskId $BaseBranch $PolicyRef -RequireReady
    $null = Test-TaskReport $context $AcceptanceReport
    if ($PullRequestUrl -cnotmatch '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)$') { throw 'An exact github.com pull request URL is required.' }
    $repository = "$($Matches[1])/$($Matches[2])"
    $remote = (Invoke-TaskGit $context.Root @('remote', 'get-url', 'origin')).Trim()
    $normalized = $remote -creplace '^git@github\.com:', 'https://github.com/' -creplace '\.git$', ''
    if ($normalized -cne "https://github.com/$repository") { throw 'PR repository does not match origin.' }
    [pscustomobject]@{
        Mode = 'LocalPreflightOnly'
        Executed = $false
        MergeAuthorized = $false
        TaskId = $TaskId
        Head = $context.Head
        ExpectedBase = $BaseBranch
        ExpectedHead = $context.Branch
        Unverified = @('PR open and not draft', 'remote head SHA matches local HEAD', 'PR base/head/repository', 'required CI success and branch protection', 'user approval')
        CommandAfterIndependentVerification = "gh pr merge $PullRequestUrl --merge --match-head-commit $($context.Head)"
    } | ConvertTo-Json -Depth 5
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
