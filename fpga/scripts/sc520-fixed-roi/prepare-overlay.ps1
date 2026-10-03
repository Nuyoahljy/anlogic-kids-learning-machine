#Requires -Version 7.5
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$baseline = Join-Path $repo 'fpga/vendor_labs/sc520'
$target = Join-Path $repo 'fpga/custom_project/sc520'
if (Test-Path -LiteralPath $target) { throw 'Refusing to overwrite overlay project' }
$manifest = Get-Content -LiteralPath (Join-Path $repo 'evidence/sc520-fixed-roi/source-manifest.json') -Raw | ConvertFrom-Json
foreach ($file in $manifest.Files) {
    $source = Join-Path $baseline $file.Path
    if ((Get-FileHash -LiteralPath $source).Hash -ne $file.SHA256) { throw "Baseline changed: $source" }
    $destination = Join-Path $target $file.Path
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}
$imports = @(
    @{Source='E:/juan/FPGA/learning/pixel-coord-adapter/pixel_coord_adapter.v'; Name='pixel_coord_adapter.v'},
    @{Source='E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/fixed-rect-overlay/fpga/custom_project/osd/fixed_rect_overlay.v'; Name='fixed_rect_overlay.v'}
)
$roi = Join-Path $target 'user_source/hdl_source/roi'
[IO.Directory]::CreateDirectory($roi) | Out-Null
foreach ($entry in $imports) {
    $destination = Join-Path $roi $entry.Name
    Copy-Item -LiteralPath $entry.Source -Destination $destination
    $entry.Destination=$destination
    $entry.SHA256=(Get-FileHash -LiteralPath $destination).Hash
}
$imports | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $repo 'evidence/sc520-fixed-roi/reused-modules.json') -Encoding utf8
foreach ($relative in @('td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj','td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.prj')) {
    $path = Join-Path $target $relative
    $text = [IO.File]::ReadAllText($path)
    $prefix = if ($relative.EndsWith('.al')) { '../' } else { '../../../' }
    $nodes = @()
    $order = 100
    foreach ($name in @('pixel_coord_adapter.v','fixed_rect_overlay.v','hdmi_roi_overlay.v')) {
        $nodes += "            <File Path=`"${prefix}user_source/hdl_source/roi/$name`"><FileInfo><Attr Name=`"UsedInSyn`" Val=`"true`"/><Attr Name=`"UsedInP&R`" Val=`"true`"/><Attr Name=`"BelongTo`" Val=`"design_1`"/><Attr Name=`"CompileOrder`" Val=`"$order`"/></FileInfo></File>"
        $order++
    }
    if ([regex]::Matches($text,'</Verilog>').Count -ne 1) { throw 'Unexpected project structure' }
    $text = $text.Replace('        </Verilog>', ($nodes -join "`r`n") + "`r`n        </Verilog>")
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
}
Write-Output 'Independent overlay sources prepared; top-level integration still requires the tracked patch.'
