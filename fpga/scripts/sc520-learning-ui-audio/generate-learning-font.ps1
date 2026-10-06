#Requires -Version 7.5
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$hdl=Join-Path $repo 'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning'
$evidence=Join-Path $repo 'evidence/sc520-learning-ui-audio/font'
$sim=Join-Path $repo 'fpga/sim/sc520-learning-ui-audio'
foreach($directory in @($hdl,$evidence,$sim)){[IO.Directory]::CreateDirectory($directory) | Out-Null}
$chinese='中文拼音英无目标红黄蓝色圆方三角形语模拟空闲等待播放故障测试输入摄像仅软件验证'.ToCharArray()
$ascii=' -:abcdefghijlnoqrstuwxy'.ToCharArray()
$font=[Drawing.Font]::new('SimSun',14,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
if($font.FontFamily.GetName(1033) -ne 'SimSun'){throw 'Required installed SimSun font not found; no silent fallback'}
$format=[Drawing.StringFormat]::GenericTypographic.Clone()
$format.FormatFlags=$format.FormatFlags -bor [Drawing.StringFormatFlags]::NoClip
$bitmap=[Drawing.Bitmap]::new(16,16)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.TextRenderingHint=[Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
$characters=@()
foreach($character in $ascii){$characters+=@{Id=[int]$character;Character=[string]$character;Ascii=$true}}
for($i=0;$i -lt $chinese.Length;$i++){$characters+=@{Id=128+$i;Character=[string]$chinese[$i];Ascii=$false}}
$atlas=[Drawing.Bitmap]::new(640,([int][Math]::Ceiling($characters.Length/10))*80)
$atlasGraphics=[Drawing.Graphics]::FromImage($atlas)
$atlasGraphics.Clear([Drawing.Color]::FromArgb(24,36,44))
$atlasGraphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$atlasGraphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$rtl=[Collections.Generic.List[string]]::new()
$ref=[Collections.Generic.List[string]]::new()
$rtl.Add('// Generated local SimSun subset; do not edit the ROM by hand.')
$rtl.Add('module learning_font_rom(input wire [7:0] glyph, input wire [3:0] row, output reg [15:0] bits);')
$rtl.Add('    always @* begin')
$rtl.Add('        bits = 0;')
$rtl.Add('        case ({glyph,row})')
$ref.Add('// Independent full-bitmap format for pixel checking; same locally rendered font source.')
$ref.Add('function automatic [255:0] learning_reference_bitmap(input integer glyph_id);')
$ref.Add('    begin')
$ref.Add('        learning_reference_bitmap = 256''d0;')
$ref.Add('        case (glyph_id)')
$index=0
foreach($entry in $characters){
    $graphics.Clear([Drawing.Color]::Black)
    $offset=if($entry.Ascii){0}else{1}
    $graphics.DrawString($entry.Character,$font,[Drawing.Brushes]::White,[Drawing.PointF]::new($offset,0),$format)
    $rows=@()
    for($row=0;$row -lt 16;$row++){
        $bits=0
        for($column=0;$column -lt 16;$column++){
            if($bitmap.GetPixel($column,$row).R -ge 128){$bits=$bits -bor (1 -shl (15-$column))}
        }
        if($entry.Ascii -and ($bits -band 255) -ne 0){throw "ASCII glyph exceeds its 8 pixel cell: $($entry.Character)"}
        $rows+=$bits
        if($bits -ne 0){$rtl.Add(('            12''d{0}: bits = 16''h{1:X4};' -f ($entry.Id*16+$row),$bits))}
    }
    $entry.Rows=$rows
    $hex=($rows | ForEach-Object {'{0:X4}' -f $_}) -join ''
    $ref.Add(('            {0}: learning_reference_bitmap = 256''h{1};' -f $entry.Id,$hex))
    $atlasGraphics.DrawImage($bitmap,[Drawing.Rectangle]::new(($index%10)*64,[int][Math]::Floor($index/10)*80,64,64),0,0,16,16,[Drawing.GraphicsUnit]::Pixel)
    $atlasGraphics.DrawString([string]$entry.Id,$font,[Drawing.Brushes]::White,[Drawing.PointF]::new(($index%10)*64,[int][Math]::Floor($index/10)*80+64))
    $index++
}
$rtl.Add('        endcase');$rtl.Add('    end');$rtl.Add('endmodule')
$ref.Add('        endcase');$ref.Add('    end');$ref.Add('endfunction')
$rtl | Set-Content -LiteralPath (Join-Path $hdl 'learning_font_rom.v') -Encoding ascii
$ref | Set-Content -LiteralPath (Join-Path $sim 'learning_font_reference.svh') -Encoding ascii
@{Font=$font.Name;PixelSize=14;Rendering='SingleBitPerPixelGridFit';Characters=$characters;Note='Locally rendered bitmap subset. No original font file copied; no open-source licensing claim. Software rendering is not hardware evidence.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'glyphs.json') -Encoding utf8
$atlas.Save((Join-Path $evidence 'atlas.png'),[Drawing.Imaging.ImageFormat]::Png)
$atlasGraphics.Dispose();$atlas.Dispose();$graphics.Dispose();$bitmap.Dispose();$font.Dispose();$format.Dispose()
Write-Output "FONT_GENERATED glyphs=$($characters.Length)"
