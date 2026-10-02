#Requires -Version 7.5
[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$prefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$files = @(& git -C $root -c core.quotepath=false ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked delivery files.' }
$failures = [Collections.Generic.List[string]]::new()
$linksChecked = 0
$jsonChecked = 0
foreach ($relative in $files) {
    $path = Join-Path $root $relative
    if ($relative -match '[^\x20-\x7e]') { $failures.Add("Non-ASCII filename: $relative") }
    if ($relative -match '(?i)(^|/)(\.env($|\.)|secrets/|private/)|\.(lic|pem|key|exe|msi|zip|rar|7z|bit|wlf)$|(^|/)(runs|test-runs)/') {
        $failures.Add("Private file, binary or runtime output tracked: $relative")
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Tracked file missing: $relative")
        continue
    }
    $item = Get-Item -LiteralPath $path
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $failures.Add("Linked file is not a self-contained deliverable: $relative")
        continue
    }
    if ($item.Length -gt 10MB) { $failures.Add("Use Release for file larger than 10 MiB: $relative") }
    if ($relative -notmatch '(?i)\.(md|json|ps1|ya?ml|v|sv|vh|txt)$') { continue }
    $text = [IO.File]::ReadAllText($path)
    if ($text -match 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') {
        $failures.Add("Possible credential in $relative (value not printed)")
    }
    if ($relative -match '(?i)\.json$') {
        try { $null = $text | ConvertFrom-Json -DateKind String; $jsonChecked++ }
        catch { $failures.Add("Invalid JSON: $relative") }
    }
    if ($relative -notmatch '(?i)\.md$') { continue }
    foreach ($match in [regex]::Matches($text, '(?<!!)\[[^\]\r\n]*\]\((?:<(?<angle>[^>]+)>|(?<plain>[^)\r\n]+))\)')) {
        $target = if ($match.Groups['angle'].Success) { $match.Groups['angle'].Value } else { $match.Groups['plain'].Value }
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:|^#|[<>]') { continue }
        $target = [Uri]::UnescapeDataString(($target -split '[#?]', 2)[0])
        if (-not $target) { continue }
        $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $path) $target))
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $failures.Add("Link leaves repository: $relative -> $target")
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) { $failures.Add("Missing local link: $relative -> $target") }
        else { $linksChecked++ }
    }
}
if ($failures.Count) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output "PASS: delivery files=$($files.Count) local_links=$linksChecked json=$jsonChecked"
Write-Output 'Remote URLs, complete secret history, licences, HDL function and hardware are not verified by this check.'
