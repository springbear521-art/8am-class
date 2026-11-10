# Generates the small BMFont subset used by the Chinese watch UI.
# Noto Sans SC is licensed under SIL Open Font License 1.1.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $project 'source\EightAmClassApp.mc') -Raw -Encoding UTF8
$characters = [System.Collections.Generic.SortedSet[char]]::new()
foreach ($match in [regex]::Matches($source, '[\u3400-\u9fff]')) {
    [void]$characters.Add($match.Value[0])
}
for ($code = 32; $code -le 126; $code++) {
    [void]$characters.Add([char]$code)
}

$cellWidth = 28
$cellHeight = 30
$columns = 16
$atlasSize = 512
$bitmap = [System.Drawing.Bitmap]::new($atlasSize, $atlasSize)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$fontFamily = [System.Drawing.FontFamily]::new('Noto Sans SC')
$font = [System.Drawing.Font]::new($fontFamily, 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
$format = [System.Drawing.StringFormat]::GenericTypographic

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('info face="Noto Sans SC" size=18 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0 outline=0')
$lines.Add("common lineHeight=$cellHeight base=24 scaleW=$atlasSize scaleH=$atlasSize pages=1 packed=0")
$lines.Add('page id=0 file="chinese.png"')
$lines.Add("chars count=$($characters.Count)")
$index = 0
foreach ($character in $characters) {
    $x = ($index % $columns) * $cellWidth
    $y = [int][math]::Floor($index / $columns) * $cellHeight
    if ($y + $cellHeight -gt $atlasSize) { throw 'Font atlas is too small' }
    $glyph = [string]$character
    $measured = $graphics.MeasureString($glyph, $font, 100, $format).Width
    $advance = [int][math]::Ceiling($measured) + 1
    if ($advance -gt $cellWidth) { $advance = $cellWidth }
    if ($advance -lt 5) { $advance = 5 }
    if ($character -eq ' ') { $advance = 8 }
    $graphics.DrawString($glyph, $font, $brush, [float]($x + 1), [float]$y, $format)
    $lines.Add("char id=$([int]$character) x=$x y=$y width=$cellWidth height=$cellHeight xoffset=0 yoffset=0 xadvance=$advance page=0 chnl=15")
    $index++
}
$lines.Add('kernings count=0')

$fontsDir = Join-Path $project 'fonts'
New-Item -ItemType Directory -Path $fontsDir -Force | Out-Null
$bitmap.Save((Join-Path $fontsDir 'chinese.png'), [System.Drawing.Imaging.ImageFormat]::Png)
[System.IO.File]::WriteAllLines((Join-Path $fontsDir 'chinese.fnt'), $lines, [System.Text.UTF8Encoding]::new($false))
$brush.Dispose()
$font.Dispose()
$fontFamily.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
Write-Output "Generated $index glyphs in fonts/chinese.png"
