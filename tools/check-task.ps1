#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseBranch = 'main',
    [string]$PolicyRef = '',
    [switch]$RequireReady,
    [string]$AcceptanceReport = '',
    [switch]$Json
)
. (Join-Path $PSScriptRoot 'task-common.ps1')
$result = [ordered]@{ TaskId = $TaskId; Passed = $false; Head = $null; Branch = $null; Status = $null; State = $null; BaseCommit = $null; PolicyCommit = $null; ChangedPaths = @(); Acceptance = 'not_requested'; Failures = @() }
try {
    $root = Get-TaskRoot $RepoRoot
    $result.Head = (Invoke-TaskGit $root @('rev-parse', 'HEAD')).Trim()
    $result.Branch = (Invoke-TaskGit $root @('branch', '--show-current')).Trim()
    $result.Status = (Invoke-TaskGit $root @('status', '--porcelain=v1', '--untracked-files=all'))
    $context = Get-TaskContext $root $TaskId $BaseBranch $PolicyRef -RequireReady:$RequireReady
    $result.State = $context.State
    $result.BaseCommit = $context.Policy.BaseCommit
    $result.PolicyCommit = $context.Policy.PolicyCommit
    $result.ChangedPaths = $context.Changes.Paths
    if ($AcceptanceReport) { $null = Test-TaskReport $context $AcceptanceReport; $result.Acceptance = 'passed_script_checks_only' }
    $result.Passed = $true
}
catch { $result.Failures = @($_.Exception.Message); if ($AcceptanceReport) { $result.Acceptance = 'failed_or_unverified' } }
if ($Json) { $result | ConvertTo-Json -Depth 10 } else { [pscustomobject]$result | Format-List }
if (-not $result.Passed) { exit 1 }
exit 0
