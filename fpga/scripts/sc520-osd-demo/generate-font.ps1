#Requires -Version 7.5
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$hdl=Join-Path $repo 'fpga/custom_project/sc520-osd-demo/user_source/hdl_source/roi'
$evidence=Join-Path $repo 'evidence/sc520-osd-demo/font'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$characters='测试模式摄像头输入识别红黄蓝色圆形正方三角未确认无目标空白'.ToCharArray()
$font=[Drawing.Font]::new('SimSun',14,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
if($font.FontFamily.GetName(1033) -ne 'SimSun'){throw 'Required installed SimSun font not found; no silent fallback'}
$format=[Drawing.StringFormat]::GenericTypographic.Clone()
$format.FormatFlags=$format.FormatFlags -bor [Drawing.StringFormatFlags]::NoClip
$bitmap=[Drawing.Bitmap]::new(16,16)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.TextRenderingHint=[Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
$atlas=[Drawing.Bitmap]::new(512,([int][Math]::Ceiling($characters.Length/8))*80)
$atlasGraphics=[Drawing.Graphics]::FromImage($atlas)
$atlasGraphics.Clear([Drawing.Color]::FromArgb(32,32,32))
$atlasGraphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$atlasGraphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$lines=[Collections.Generic.List[string]]::new()
$lines.Add('module osd_font_rom(input wire [5:0] glyph, input wire [3:0] row, output reg [15:0] bits);')
$lines.Add('    always @* begin')
$lines.Add('        bits = 0;')
$lines.Add('        case ({glyph,row})')
$glyphs=@()
for($index=0;$index -lt $characters.Length;$index++){
    $graphics.Clear([Drawing.Color]::Black)
    $graphics.DrawString([string]$characters[$index],$font,[Drawing.Brushes]::White,[Drawing.PointF]::new(1,0),$format)
    $rows=@()
    for($row=0;$row -lt 16;$row++){
        $bits=0
        for($column=0;$column -lt 16;$column++){if($bitmap.GetPixel($column,$row).R -ge 128){$bits=$bits -bor (1 -shl (15-$column))}}
        $rows+=$bits
        if($bits -ne 0){$lines.Add(('            10''d{0}: bits = 16''h{1:X4};' -f (($index+1)*16+$row),$bits))}
    }
    $glyphs+=@{Id=$index+1;Character=[string]$characters[$index];Rows=$rows}
    $atlasGraphics.DrawImage($bitmap,[Drawing.Rectangle]::new(($index%8)*64,[int][Math]::Floor($index/8)*80,64,64),0,0,16,16,[Drawing.GraphicsUnit]::Pixel)
    $atlasGraphics.DrawString([string]($index+1),$font,[Drawing.Brushes]::White,[Drawing.PointF]::new(($index%8)*64,[int][Math]::Floor($index/8)*80+64))
}
$lines.Add('        endcase')
$lines.Add('    end')
$lines.Add('endmodule')
$lines | Set-Content -LiteralPath (Join-Path $hdl 'osd_font_rom.v') -Encoding ascii
@{Font=$font.Name;PixelSize=14;Rendering='SingleBitPerPixelGridFit';Characters=$glyphs;Note='Rendered bitmap subset from locally installed SimSun. Original font file not copied. No claim that the source font is open source.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'glyphs.json') -Encoding utf8
$atlas.Save((Join-Path $evidence 'atlas.png'),[Drawing.Imaging.ImageFormat]::Png)
$atlasGraphics.Dispose();$atlas.Dispose();$graphics.Dispose();$bitmap.Dispose();$font.Dispose();$format.Dispose()
Write-Output "FONT_GENERATED glyphs=$($characters.Length)"
