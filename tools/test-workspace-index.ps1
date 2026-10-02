#Requires -Version 7.5
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'update-workspace-index.ps1'
$pwsh = (Get-Process -Id $PID).Path
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testName = 'fpga-index-tests-' + [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $tempParent $testName
$recordsDir = Join-Path $testRoot 'workspace-records'
$indexPath = Join-Path $testRoot 'FILE_INDEX.md'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$passed = 0

function Invoke-Index {
    param([bool]$Success, [switch]$Check)
    $arguments = @('-NoProfile', '-File', $scriptPath, '-WorkspaceRoot', $testRoot)
    if ($Check) { $arguments += '-Check' }
    $output = & $pwsh @arguments 2>&1
    if (($LASTEXITCODE -eq 0) -ne $Success) {
        throw "Unexpected index result: $($output -join [Environment]::NewLine)"
    }
}

function Save-Record {
    param([hashtable]$Entry)
    $path = Join-Path $recordsDir ($Entry.Id + '.json')
    [System.IO.File]::WriteAllText($path, ($Entry | ConvertTo-Json -Depth 6), $utf8)
    return $path
}

function Assert-IndexUnchanged {
    param([string]$Before)
    if ([System.IO.File]::ReadAllText($indexPath) -cne $Before) {
        throw 'A failed operation modified the published index.'
    }
}

function Pass {
    param([string]$Name)
    $script:passed++
    Write-Output "PASS: $Name"
}

try {
    New-Item -ItemType Directory -Path $recordsDir -Force | Out-Null
    $source = Join-Path $testRoot 'sample source.v'
    [System.IO.File]::WriteAllText($source, 'module sample; endmodule', $utf8)
    $entry = @{
        Id = '20260928-100000-test-01'
        UpdatedAt = '2026-09-28T10:00:00+08:00'
        Task = 'index-test'
        Owner = 'test-runner'
        Workdir = $testRoot
        Summary = 'Synthetic test record'
        Validation = 'Fixture only; no hardware claim'
        NextStep = 'Continue tests'
        Changes = @(@{
            Path = $source; Action = 'added'; Purpose = 'pipe | and <tag>'; Status = 'pending'
        })
    }
    $entryPath = Save-Record $entry
    Invoke-Index $true
    Invoke-Index $true -Check
    $before = [System.IO.File]::ReadAllText($indexPath)
    if (-not $before.Contains('sample%20source.v') -or -not $before.Contains('&#124;')) {
        throw 'Markdown URL or table escaping failed.'
    }
    Pass 'Generate, validate, and escape a registered file'

    [System.IO.File]::WriteAllText($indexPath, 'stale', $utf8)
    Invoke-Index $false -Check
    Invoke-Index $true
    Pass 'Detect a stale index and regenerate it'

    $badPath = Join-Path $recordsDir 'broken.json'
    [System.IO.File]::WriteAllText($badPath, '{', $utf8)
    Invoke-Index $false
    Assert-IndexUnchanged $before
    Remove-Item -LiteralPath $badPath
    Pass 'Reject malformed JSON without replacing the previous index'

    $entry.Changes[0].Path = Join-Path $tempParent 'outside.v'
    $null = Save-Record $entry
    Invoke-Index $false
    Assert-IndexUnchanged $before
    $entry.Changes[0].Path = $source
    $null = Save-Record $entry
    Pass 'Reject paths outside the selected workspace'

    $entry.Changes[0].Action = 'unknown'
    $null = Save-Record $entry
    Invoke-Index $false
    Assert-IndexUnchanged $before
    $entry.Changes[0].Action = 'added'
    $null = Save-Record $entry
    Pass 'Reject invalid action values'

    $entry.Remove('Validation')
    $null = Save-Record $entry
    Invoke-Index $false
    Assert-IndexUnchanged $before
    $entry.Validation = 'Fixture only; no hardware claim'
    $null = Save-Record $entry
    Pass 'Require an explicit validation statement'

    $entry.Changes[0].Path = Join-Path $testRoot 'missing.v'
    $null = Save-Record $entry
    Invoke-Index $false
    Assert-IndexUnchanged $before
    $entry.Changes[0].Path = $source
    $null = Save-Record $entry
    Pass 'Reject missing active file targets'

    Remove-Item -LiteralPath $source
    $entry.Id = '20260928-110000-test-02'
    $entry.UpdatedAt = '2026-09-28T11:00:00+08:00'
    $entry.Changes[0].Action = 'deleted'
    $entry.Changes[0].Status = 'removed'
    $null = Save-Record $entry
    Invoke-Index $true
    Invoke-Index $true -Check
    $content = [System.IO.File]::ReadAllText($indexPath)
    if (-not $content.Contains('(deleted)') -or
        -not $content.Contains('20260928-100000-test-01') -or
        -not $content.Contains('20260928-110000-test-02')) {
        throw 'Latest-state or history retention failed.'
    }
    Pass 'Keep history while applying the latest deletion'
    Write-Output "PASS: $passed workspace-index tests."
}
finally {
    # Delete only this run's generated fixture directory under the verified temp parent.
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $parent = $tempParent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolved) -cne $testName) {
        throw "Refusing to remove unexpected fixture path: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
