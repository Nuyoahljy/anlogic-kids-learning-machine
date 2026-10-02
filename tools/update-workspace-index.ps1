#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'E:\juan\FPGA',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Text {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($property.Value)) {
        throw "Missing or invalid text field: $Name"
    }
    return $property.Value
}

function Get-WorkspacePath {
    param([string]$Path)
    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw "An absolute path is required: $Path"
    }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -ne $root -and -not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the workspace: $Path"
    }
    return $full
}

function ConvertTo-Cell {
    param([string]$Value)
    return $Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').
        Replace('|', '&#124;').Replace("`r", ' ').Replace("`n", ' ')
}

$root = (Resolve-Path -LiteralPath $WorkspaceRoot).Path.TrimEnd('\', '/')
$rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
$recordsDir = Join-Path $root 'workspace-records'
$indexPath = Join-Path $root 'FILE_INDEX.md'
$hashBytes = [System.Security.Cryptography.SHA256]::HashData(
    [System.Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))
$lockName = 'Local\FpgaFileIndex-' + [Convert]::ToHexString($hashBytes)
$mutex = [System.Threading.Mutex]::new($false, $lockName)
$locked = $false
$tempPath = $null
try {
    try {
        $locked = $mutex.WaitOne(30000)
    }
    catch [System.Threading.AbandonedMutexException] {
        $locked = $true
    }
    if (-not $locked) { throw 'Workspace index is busy. Retry after the other writer finishes.' }
    $recordFiles = @(Get-ChildItem -LiteralPath $recordsDir -Filter '*.json' -File | Sort-Object Name)
    if ($recordFiles.Count -eq 0) { throw 'No workspace records found.' }
    $records = @()
    foreach ($file in $recordFiles) {
        $entry = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
        foreach ($field in @('Id', 'UpdatedAt', 'Task', 'Owner', 'Workdir', 'Summary', 'Validation', 'NextStep')) {
            $null = Assert-Text $entry $field
        }
        if ($entry.Id -notmatch '^[a-z0-9][a-z0-9-]*$' -or $entry.Id -cne $file.BaseName) {
            throw "Record Id must match its ASCII filename: $($file.Name)"
        }
        if ($entry.UpdatedAt -notmatch '(Z|[+-]\d{2}:\d{2})$') {
            throw "UpdatedAt must include a timezone: $($file.Name)"
        }
        $when = [DateTimeOffset]::Parse($entry.UpdatedAt, [Globalization.CultureInfo]::InvariantCulture)
        $null = Get-WorkspacePath $entry.Workdir
        if ($null -eq $entry.PSObject.Properties['Changes'] -or
            $entry.Changes -isnot [array] -or $entry.Changes.Count -eq 0) {
            throw "Changes must be a nonempty array: $($file.Name)"
        }
        foreach ($change in $entry.Changes) {
            foreach ($field in @('Path', 'Action', 'Purpose', 'Status')) {
                $null = Assert-Text $change $field
            }
            if ($change.Action -notin @('added', 'modified', 'deleted', 'generated', 'observed')) {
                throw "Invalid action in $($file.Name): $($change.Action)"
            }
            $change.Path = Get-WorkspacePath $change.Path
        }
        $records += [pscustomobject]@{ Entry = $entry; When = $when; File = $file.Name }
    }
    $records = @($records | Sort-Object When, File)
    $latest = @{}
    foreach ($record in $records) {
        foreach ($change in $record.Entry.Changes) {
            $latest[$change.Path] = [pscustomobject]@{ Change = $change; Record = $record }
        }
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(
        '# 文件统筹索引', '',
        '本文件由统一脚本生成，禁止手工编辑。先读 [工作区入口](README.md) 和 [协作规则](AGENTS.md)。',
        '范围仅限已登记变动；不是全部磁盘文件清单，也不代表技术验收。相同路径显示最后一次登记，历史见下方批次。', '',
        '## 已登记文件', '',
        '| 文件或输出目录 | 用途 | 动作 / 状态 | 任务 / 最近登记 |',
        '|---|---|---|---|'
    )) { $lines.Add($line) }
    foreach ($path in @($latest.Keys | Sort-Object)) {
        $item = $latest[$path]
        $change = $item.Change
        $entry = $item.Record.Entry
        $relative = [System.IO.Path]::GetRelativePath($root, $path).Replace('\', '/')
        $url = [Uri]::EscapeDataString($relative).Replace('%2F', '/')
        $label = ConvertTo-Cell $relative
        if ($change.Action -eq 'deleted') {
            $link = "$label (deleted)"
        } else {
            $link = "[$label](<$url>)"
            if ($path -ne $indexPath -and -not (Test-Path -LiteralPath $path)) {
                throw "Latest record points to a missing file or directory: $path"
            }
        }
        $lines.Add("| $link | $(ConvertTo-Cell $change.Purpose) | $($change.Action) / $(ConvertTo-Cell $change.Status) | $(ConvertTo-Cell $entry.Task) / $($entry.UpdatedAt) |")
    }
    $lines.Add('')
    $lines.Add('## 变更批次')
    foreach ($record in @($records | Sort-Object When, File -Descending)) {
        $entry = $record.Entry
        $lines.Add('')
        $lines.Add("### $($entry.Id)")
        $lines.Add("- 记录：[$($record.File)](workspace-records/$($record.File))")
        $lines.Add("- 时间：$($entry.UpdatedAt)；负责人：$(ConvertTo-Cell $entry.Owner)")
        $lines.Add("- 工作目录：$(ConvertTo-Cell $entry.Workdir)")
        $lines.Add("- 变动：$(ConvertTo-Cell $entry.Summary)")
        $lines.Add("- 验证：$(ConvertTo-Cell $entry.Validation)")
        $lines.Add("- 下一步：$(ConvertTo-Cell $entry.NextStep)")
    }
    $content = ($lines -join "`n") + "`n"
    if ($Check) {
        if (-not (Test-Path -LiteralPath $indexPath) -or
            [System.IO.File]::ReadAllText($indexPath) -cne $content) {
            throw 'FILE_INDEX.md is missing or stale. Run without -Check to refresh it.'
        }
        Write-Output "PASS: $($records.Count) records; $($latest.Count) indexed paths."
        return
    }
    # Publish only a fully validated snapshot; never expose a partially written index.
    $tempPath = Join-Path $root ('.file-index-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($tempPath, $content, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $indexPath) {
        [System.IO.File]::Replace($tempPath, $indexPath, [NullString]::Value)
    } else {
        [System.IO.File]::Move($tempPath, $indexPath)
    }
    $tempPath = $null
    Write-Output "Updated: $indexPath ($($records.Count) records; $($latest.Count) paths)."
}
finally {
    if ($null -ne $tempPath -and (Test-Path -LiteralPath $tempPath)) {
        Remove-Item -LiteralPath $tempPath
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
