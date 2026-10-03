#Requires -Version 7.5
[CmdletBinding()]
param([string]$Archive = 'E:\juan\FPGA\Data\HX1P35A_Contest_202606\SC520CS摄像头资料\lab_ex1_mipi_hdmi_SC520 (2).zip')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$target = Join-Path $repo 'fpga/vendor_labs/sc520'
if (Test-Path -LiteralPath $target) { throw 'Refusing to overwrite existing baseline' }
$expected = 'F3B51D6BA4A96B2669A10E88BDF014B1588E4D7D1A8D7103F5423BCEE42A0DEC'
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expected) { throw 'Archive hash mismatch' }
$prefix = 'lab_ex1_mipi_hdmi_SC520/lab_ex1_mipi_hdmi/'
$manifest = [Collections.Generic.List[object]]::new()
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
    foreach ($entry in $zip.Entries) {
        if (-not $entry.FullName.StartsWith($prefix) -or $entry.Name -eq '') { continue }
        $relative = $entry.FullName.Substring($prefix.Length)
        $keep = $relative.StartsWith('user_source/') -or
            $relative -match '^td_project/(camera_to_dsi_display\.(al|sdc)|al_ip/.*)$' -or
            $relative -match '^td_project/camera_to_dsi_display_Runs/(syn_1|phy_1)/(settings\.cfg|camera_to_dsi_display\.(prj|tcl))$'
        if (-not $keep) { continue }
        $output = [IO.Path]::GetFullPath((Join-Path $target $relative))
        if (-not $output.StartsWith($target + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive path escapes target' }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $output, $false)
        $manifest.Add([ordered]@{ Path=$relative; ArchiveEntry=$entry.FullName; SHA256=(Get-FileHash -LiteralPath $output).Hash; Bytes=$entry.Length })
    }
} finally { $zip.Dispose() }
$evidence = Join-Path $repo 'evidence/sc520-fixed-roi'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
[ordered]@{ Archive=$Archive; ArchiveSHA256=$expected; ExtractedAt=[DateTimeOffset]::Now.ToString('o'); Files=$manifest } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'source-manifest.json') -Encoding utf8
Write-Output "Extracted $($manifest.Count) source/input files; no historical bit or databases copied."
