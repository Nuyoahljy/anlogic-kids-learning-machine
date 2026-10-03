#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [ValidateSet('baseline','overlay','color-mask','dynamic-box','shape')][string]$Stage = 'overlay',
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$dependency = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checkpoint/dependency.json') -Raw | ConvertFrom-Json -AsHashtable
$recipe = Get-Content -LiteralPath (Join-Path $PSScriptRoot "checkpoint/$Stage.json") -Raw | ConvertFrom-Json -AsHashtable
$projects = @{ baseline='fpga/vendor_labs/sc520'; overlay='fpga/custom_project/sc520'; 'color-mask'='fpga/custom_project/sc520-color-mask'; 'dynamic-box'='fpga/custom_project/sc520-dynamic-box'; shape='fpga/custom_project/sc520-shape' }
if ($recipe.Stage -cne $Stage -or $recipe.Project -cne $projects[$Stage]) { throw 'Unexpected project mapping' }
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -cne $dependency.ArchiveSHA256) { throw 'Authorized dependency archive SHA256 mismatch' }
$project = [IO.Path]::GetFullPath((Join-Path $repo $recipe.Project))
$utf8 = [Text.UTF8Encoding]::new($false, $true)
function Get-ByteHash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function Expand-Delta([byte[]]$Bytes, [hashtable]$Delta) {
    if ((Get-ByteHash $Bytes) -cne $Delta.BaseSHA256) { throw 'Delta baseline hash mismatch' }
    $newline = [string][char]10
    $carriage = [string][char]13
    $text = $utf8.GetString($Bytes).TrimStart([char]0xFEFF).Replace($carriage + $newline, $newline).Replace($carriage, $newline)
    $lines = [Collections.Generic.List[string]]::new()
    if ($text.Length -gt 0) {
        $lines.AddRange([string[]]$text.Split([char]10))
        if ($text.EndsWith($newline)) { $lines.RemoveAt($lines.Count - 1) }
    }
    foreach ($edit in @($Delta.Edits | Sort-Object StartLine -Descending)) {
        if ($edit.StartLine -lt 0 -or $edit.DeleteCount -lt 0 -or ($edit.StartLine + $edit.DeleteCount) -gt $lines.Count) { throw 'Invalid delta range' }
        $lines.RemoveRange([int]$edit.StartLine, [int]$edit.DeleteCount)
        $lines.InsertRange([int]$edit.StartLine, [string[]]@($edit.Lines))
    }
    if ($lines.Count -ne $Delta.Endings.Length) { throw 'Delta newline map mismatch' }
    $builder = [Text.StringBuilder]::new()
    if ($Delta.Utf8Bom) { [void]$builder.Append([char]0xFEFF) }
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        [void]$builder.Append($lines[$lineIndex])
        switch ([string]$Delta.Endings[$lineIndex]) {
            'C' { [void]$builder.Append($carriage + $newline) }
            'L' { [void]$builder.Append($newline) }
            'R' { [void]$builder.Append($carriage) }
            'N' { }
            default { throw 'Invalid newline code' }
        }
    }
    return ,$utf8.GetBytes($builder.ToString())
}
$pending = [Collections.Generic.List[object]]::new()
$skipped = 0
$archiveFile = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try {
    foreach ($relative in @($recipe.Inputs.Keys | Sort-Object)) {
        if ($relative -notmatch '^(user_source|td_project)/' -or $relative.Contains('\')) { throw 'Invalid input path' }
        $target = [IO.Path]::GetFullPath((Join-Path $project $relative))
        if (-not $target.StartsWith($project + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Input path escapes project' }
        $expected = $recipe.Inputs[$relative]
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target).Hash -cne $expected) { throw "Existing input differs; nothing overwritten: $relative" }
            $skipped++
            continue
        }
        if ($VerifyOnly) { throw "Missing input: $relative" }
        if ($relative -in $recipe.OwnedFiles) { throw "Missing tracked self-authored source: $relative" }
        if (-not $dependency.Files.ContainsKey($relative)) { throw "No external dependency entry: $relative" }
        $source = $dependency.Files[$relative]
        $entry = $archiveFile.GetEntry($source.ArchiveEntry)
        if (-not $entry) { throw "Missing archive entry: $relative" }
        $stream = $entry.Open()
        $memory = [IO.MemoryStream]::new()
        try { $stream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
        if ((Get-ByteHash $bytes) -cne $source.SHA256) { throw "Archive input differs: $relative" }
        if ($recipe.Changes.ContainsKey($relative)) { $bytes = Expand-Delta $bytes $recipe.Changes[$relative] }
        if ((Get-ByteHash $bytes) -cne $expected) { throw "Reconstructed input differs: $relative" }
        $pending.Add(@{Path=$target; Bytes=$bytes; SHA256=$expected})
    }
    foreach ($item in $pending) {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Path)) | Out-Null
        $output = [IO.File]::Open($item.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try { $output.Write($item.Bytes, 0, $item.Bytes.Length) } finally { $output.Dispose() }
        if ((Get-FileHash -LiteralPath $item.Path).Hash -cne $item.SHA256) { throw 'Written input hash mismatch' }
    }
} finally { $archiveFile.Dispose() }
[pscustomobject]@{Stage=$Stage; VerifiedInputs=$recipe.Inputs.Count; Created=$pending.Count; Existing=$skipped; ArchiveSHA256=$dependency.ArchiveSHA256; HardwareValidated=$false} | ConvertTo-Json
