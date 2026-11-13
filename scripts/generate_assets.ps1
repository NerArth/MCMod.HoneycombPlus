<#
.SYNOPSIS
    Deterministic asset, texture, model, recipe, loot table, and tag generator for HoneycombPlus.
.DESCRIPTION
    Reads semantic palette colors from palettes/palette.json and generates all 16x16 PNG textures,
    blockstate definitions, block/item models, 26.3 item definitions, language files, Rechiseled chiseling recipes,
    26.3 loot tables, Crafting/Stonecutter recipes, and block/item tags.

    HAND-EDIT PROTECTION:
    By default, existing .png textures on disk are NOT overwritten so your manual pixel-art edits are safe.
    Pass -ForceTextures to regenerate all .png textures from palettes/palette.json, or -TextureFilter "pattern*"
    to regenerate only matching textures.
.EXAMPLE
    .\scripts\generate_assets.ps1
    Regenerates JSON resources and only creates missing .png textures (preserving existing PNGs).
.EXAMPLE
    .\scripts\generate_assets.ps1 -ForceTextures
    Overwrites all 17 .png textures using the current colors in palettes/palette.json.
.EXAMPLE
    .\scripts\generate_assets.ps1 -TextureFilter "*brick*"
    Overwrites only textures matching "*brick*" using palettes/palette.json.
#>
param(
    [switch]$ForceTextures,
    [string]$TextureFilter = ""
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Web.Extensions

$projectRoot = Split-Path -Parent $PSScriptRoot
$resRoot = "$projectRoot\src\main\resources"
$assetsRoot = "$resRoot\assets\honeycombplus"
$dataRoot = "$resRoot\data\honeycombplus"
$mcTagsBlock = "$resRoot\data\minecraft\tags\block"
$mcTagsItem = "$resRoot\data\minecraft\tags\item"
$palettePath = "$projectRoot\palettes\palette.json"

if (-not (Test-Path $palettePath)) {
    & "$PSScriptRoot\generate_palette.ps1" -Mode ExportActive
}

$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$paletteData = $serializer.DeserializeObject([System.IO.File]::ReadAllText($palettePath))["colors"]

function Get-PaletteColor([string]$roleKey) {
    if (-not $paletteData.ContainsKey($roleKey)) {
        throw "Role '$roleKey' not found in $palettePath"
    }
    $entry = $paletteData[$roleKey]
    $hex = $entry["hex"].Trim().TrimStart('#')
    $alpha = if ($entry.ContainsKey("alpha")) { [int]$entry["alpha"] } else { 255 }
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    return [System.Drawing.Color]::FromArgb($alpha, $r, $g, $b)
}

$dirs = @(
    "$assetsRoot\blockstates",
    "$assetsRoot\items",
    "$assetsRoot\lang",
    "$assetsRoot\models\block",
    "$assetsRoot\models\item",
    "$assetsRoot\textures\block",
    "$assetsRoot\textures\item",
    "$dataRoot\chiseling_recipes",
    "$dataRoot\loot_table\blocks",
    "$dataRoot\recipe",
    "$mcTagsBlock\mineable",
    "$mcTagsItem"
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Write-JsonFile($path, $content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# ==============================================================================
# 1. GENERATE 16x16 PIXEL-ART TEXTURES USING palettes/palette.json
# ==============================================================================
$cDarkest          = Get-PaletteColor "Darkest"
$cDark             = Get-PaletteColor "Dark"
$cMidDark          = Get-PaletteColor "MidDark"
$cMid              = Get-PaletteColor "Mid"
$cMidLight         = Get-PaletteColor "MidLight"
$cLight            = Get-PaletteColor "Light"
$cBright           = Get-PaletteColor "Bright"
$cGlowCore         = Get-PaletteColor "GlowCore"
$cIronDark         = Get-PaletteColor "IronDark"
$cIronMid          = Get-PaletteColor "IronMid"
$cIronLight        = Get-PaletteColor "IronLight"
$cRedstone         = Get-PaletteColor "Redstone"
$cGlassBorderLight = Get-PaletteColor "GlassBorderLight"
$cGlassBorderDark  = Get-PaletteColor "GlassBorderDark"
$cGlassStreak      = Get-PaletteColor "GlassStreak"
$cGlassGridDot     = Get-PaletteColor "GlassGridDot"
$cGlassFill        = Get-PaletteColor "GlassFill"
$cGlassPaneEdge    = Get-PaletteColor "GlassPaneEdge"
$cClear            = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

$script:writtenTextures = 0
$script:skippedTextures = 0

function New-Bitmap16 {
    return New-Object System.Drawing.Bitmap(16, 16, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Save-Png($bmp, $path) {
    $fileName = [System.IO.Path]::GetFileName($path)
    $shouldWrite = $false
    if (-not (Test-Path $path)) {
        $shouldWrite = $true
    } elseif ($ForceTextures) {
        $shouldWrite = $true
    } elseif ($TextureFilter -and ($fileName -like $TextureFilter)) {
        $shouldWrite = $true
    }

    if ($shouldWrite) {
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $script:writtenTextures++
    } else {
        $script:skippedTextures++
    }
    $bmp.Dispose()
}

# Subtle honeycomb cell background helper
function Get-WaxShade($x, $y) {
    $v = (($x * 3 + $y * 5) % 7)
    if ($v -eq 0) { return $cMidLight }
    if ($v -eq 1 -or $v -eq 2) { return $cMid }
    if ($v -eq 3 -or $v -eq 4) { return $cMidDark }
    return $cMid
}

# 1. polished_honeycomb.png: Smooth beveled 16x16 wax tile with subtle hexagonal sheen
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $col = Get-WaxShade $x $y
        if ($x -eq 0 -or $y -eq 0) { $col = $cLight }
        elseif ($x -eq 15 -or $y -eq 15) { $col = $cDark }
        elseif ($x -eq 1 -or $y -eq 1) { $col = $cMidLight }
        elseif ($x -eq 14 -or $y -eq 14) { $col = $cMidDark }
        elseif (($x + $y) -ge 12 -and ($x + $y) -le 14) { $col = $cMidLight }
        elseif (($x + $y) -ge 15 -and ($x + $y) -le 16) { $col = $cLight }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\polished_honeycomb.png"

# 2. cut_honeycomb.png: 2x2 cut blocks (8x8 quadrants with crisp beveled seams)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $lx = $x % 8
        $ly = $y % 8
        $col = Get-WaxShade $x $y
        if ($lx -eq 0 -or $ly -eq 0) { $col = $cLight }
        elseif ($lx -eq 7 -or $ly -eq 7) { $col = $cDarkest }
        elseif ($lx -eq 6 -or $ly -eq 6) { $col = $cDark }
        elseif (($lx + $ly) -eq 5 -or ($lx + $ly) -eq 6) { $col = $cMidLight }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\cut_honeycomb.png"

# 3. honeycomb_bricks.png: 4 courses of staggered bricks (height 4 each, offset by 4 every row)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    $row = [int][Math]::Floor($y / 4)
    $ly = $y % 4
    $offset = ($row % 2) * 4
    for ($x = 0; $x -lt 16; $x++) {
        $lx = ($x + $offset) % 8
        if ($ly -eq 3 -or $lx -eq 7) {
            $col = $cDarkest
        } elseif ($ly -eq 0 -or $lx -eq 0) {
            $col = $cLight
        } elseif ($ly -eq 2 -or $lx -eq 6) {
            $col = $cDark
        } else {
            $col = Get-WaxShade $x $y
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_bricks.png"

# 4. chiseled_honeycomb.png: Ornate outer frame with carved hexagonal/bee-crown medallion in center
$bmp = New-Bitmap16
$chiselMap = @(
    "LLLLLLLLLLLLLLLD",
    "LMMMMMMMMMMMMMDD",
    "LMDDDDDDDDDDDDMD",
    "LMDSSSSSSSSSSDMD",
    "LMDSLLLMMLLLSDMD",
    "LMDSLBBBBBBDSDMD",
    "LMDSLBSSSSBDSDMD",
    "LMDSLBSCCSBDSDMD",
    "LMDSLBSCCSBDSDMD",
    "LMDSLBSSSSBDSDMD",
    "LMDSLBBBBBBDSDMD",
    "LMDSLLLMMLLLSDMD",
    "LMDSSSSSSSSSSDMD",
    "LMDDDDDDDDDDDDMD",
    "LDDDDDDDDDDDDDDD",
    "DDDDDDDDDDDDDDDD"
)
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $ch = $chiselMap[$y][$x]
        $col = switch ($ch) {
            'L' { $cLight }
            'M' { $cMid }
            'D' { $cDarkest }
            'S' { $cDark }
            'B' { $cMidLight }
            'C' { $cBright }
            default { $cMid }
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\chiseled_honeycomb.png"

# 5. honeycomb_pillar.png (side) and honeycomb_pillar_top.png (end)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($y -eq 0) { $col = $cLight }
        elseif ($y -eq 15) { $col = $cDarkest }
        else {
            $flute = $x % 4
            $col = switch ($flute) {
                0 { $cDark }
                1 { $cLight }
                2 { $cMid }
                3 { $cMidDark }
            }
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_pillar.png"

$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $dist = [Math]::Max([Math]::Abs($x - 7.5), [Math]::Abs($y - 7.5))
        if ($dist -gt 6.5) { $col = $cDarkest }
        elseif ($dist -gt 5.5) { $col = $cLight }
        elseif ($dist -gt 4.5) { $col = $cMid }
        elseif ($dist -gt 3.5) { $col = $cDark }
        elseif ($dist -gt 1.5) { $col = $cMidLight }
        else { $col = $cBright }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_pillar_top.png"

# 6. honeycomb_grate.png & honeycomb_bars.png (Cutout alpha: 0 or 255)
$grateMap = @(
    "DDDDDDDDDDDDDDDD",
    "DLLMDDDDDDDDMLLD",
    "DL..MDDDDDDM..LD",
    "DM...MDDDDM...MD",
    "DDM..LMMMMD..MDD",
    "DDDMML....LMMDD.",
    "DDDDL......LDDDD",
    "DDDDM......MDDDD",
    "DDDDM......MDDDD",
    "DDDDL......LDDDD",
    "DDDMML....LMMDDD",
    "DDM..LMMMMD..MDD",
    "DM...MDDDDM...MD",
    "DL..MDDDDDDM..LD",
    "DLLMDDDDDDDDMLLD",
    "DDDDDDDDDDDDDDDD"
)
$bmp = New-Bitmap16
$bmpBars = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $ch = $grateMap[$y][$x]
        $col = switch ($ch) {
            '.' { $cClear }
            'D' { $cDarkest }
            'M' { $cMid }
            'L' { $cLight }
            default { $cMidDark }
        }
        $bmp.SetPixel($x, $y, $col)
        $bmpBars.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_grate.png"
Save-Png $bmpBars "$assetsRoot\textures\block\honeycomb_bars.png"

# 7. honeyed_glass.png & honeyed_glass_pane_top.png (Translucent fractional alpha!)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -eq 0 -or $y -eq 0) {
            $col = $cGlassBorderLight
        } elseif ($x -eq 15 -or $y -eq 15) {
            $col = $cGlassBorderDark
        } elseif ((($x + $y) -eq 4) -or (($x + $y) -eq 5) -or (($x + $y) -eq 11)) {
            # Glossy honey streak
            $col = $cGlassStreak
        } elseif ((($x % 4) -eq 0 -and ($y % 4) -eq 0)) {
            $col = $cGlassGridDot
        } else {
            $col = $cGlassFill
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeyed_glass.png"

$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -ge 7 -and $x -le 8) {
            $col = $cGlassPaneEdge
        } else {
            $col = $cClear
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeyed_glass_pane_top.png"

# 8. honeycomb_door_top.png, honeycomb_door_bottom.png, honeycomb_trapdoor.png, item/honeycomb_door.png
# Door Top (with hexagonal lattice window cutouts)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -eq 0 -or $x -eq 15 -or $y -eq 0 -or $y -eq 15) { $col = $cDarkest }
        elseif ($x -le 2 -or $x -ge 13 -or $y -le 2 -or $y -ge 13) { $col = $cMid }
        elseif ($x -eq 7 -or $x -eq 8 -or $y -eq 7 -or $y -eq 8) { $col = $cDark }
        elseif (($x -ge 4 -and $x -le 6 -and $y -ge 4 -and $y -le 6) -or
                ($x -ge 9 -and $x -le 11 -and $y -ge 4 -and $y -le 6) -or
                ($x -ge 4 -and $x -le 6 -and $y -ge 9 -and $y -le 11) -or
                ($x -ge 9 -and $x -le 11 -and $y -ge 9 -and $y -le 11)) {
            $col = $cClear
        } else {
            $col = $cLight
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_door_top.png"

# Door Bottom (solid paneled wax door with handle)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -eq 0 -or $x -eq 15 -or $y -eq 15) { $col = $cDarkest }
        elseif ($y -le 2 -and ($x -eq 12 -or $x -eq 13)) { $col = $cBright } # door handle
        elseif ($x -le 2 -or $x -ge 13 -or $y -le 1 -or $y -ge 13) { $col = $cMid }
        elseif ($x -eq 3 -or $y -eq 2) { $col = $cDark }
        elseif ($x -eq 12 -or $y -eq 12) { $col = $cLight }
        else { $col = Get-WaxShade $x $y }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_door_bottom.png"

# Trapdoor (framed lattice with 4 cutout windows)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -eq 0 -or $x -eq 15 -or $y -eq 0 -or $y -eq 15) { $col = $cDarkest }
        elseif ($x -le 2 -or $x -ge 13 -or $y -le 2 -or $y -ge 13) { $col = $cMid }
        elseif ($x -eq 7 -or $x -eq 8 -or $y -eq 7 -or $y -eq 8) { $col = $cDark }
        elseif (($x -ge 4 -and $x -le 6 -and $y -ge 4 -and $y -le 6) -or
                ($x -ge 9 -and $x -le 11 -and $y -ge 4 -and $y -le 6) -or
                ($x -ge 4 -and $x -le 6 -and $y -ge 9 -and $y -le 11) -or
                ($x -ge 9 -and $x -le 11 -and $y -ge 9 -and $y -le 11)) {
            $col = $cClear
        } else {
            $col = $cMidLight
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_trapdoor.png"

# Door Item Icon (16x16 inventory sprite)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($x -lt 3 -or $x -gt 12 -or $y -eq 0 -or $y -eq 15) { $col = $cClear }
        elseif ($x -eq 3 -or $x -eq 12 -or $y -eq 1 -or $y -eq 14) { $col = $cDarkest }
        elseif ($y -ge 3 -and $y -le 6 -and (($x -ge 5 -and $x -le 6) -or ($x -ge 9 -and $x -le 10))) { $col = $cClear }
        elseif ($y -eq 8 -and $x -eq 10) { $col = $cBright }
        elseif ($x -eq 4 -or $x -eq 11 -or $y -eq 2 -or $y -eq 7 -or $y -eq 13) { $col = $cMid }
        else { $col = $cMidLight }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\item\honeycomb_door.png"

# 9. honeycomb_lantern.png (16x16 UV sheet for template_lantern / template_hanging_lantern) & item/honeycomb_lantern.png
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        # UV regions for vanilla lantern template:
        # Left side (x: 0..5, y: 0..14) is lantern body/top; right side (x: 11..14) is chain/hook
        if ($x -ge 11 -and $x -le 14) {
            if (($x -eq 11 -or $x -eq 14) -and ($y % 2 -eq 0)) { $col = $cIronDark }
            elseif ($x -ge 12 -and $x -le 13 -and ($y % 3 -ne 0)) { $col = $cIronMid }
            else { $col = $cClear }
        } elseif ($y -le 1 -or $y -ge 9) {
            $col = if (($x + $y) % 2 -eq 0) { $cIronDark } else { $cIronMid }
        } elseif ($x -eq 0 -or $x -eq 5) {
            $col = $cIronDark
        } elseif ($y -eq 2 -or $y -eq 8) {
            $col = $cMid
        } elseif ($x -ge 2 -and $x -le 3 -and $y -ge 4 -and $y -le 6) {
            $col = $cGlowCore
        } else {
            $col = $cBright
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\block\honeycomb_lantern.png"

# Honeycomb Lantern Item Icon (16x16 sprite)
$bmp = New-Bitmap16
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        if ($y -ge 2 -and $y -le 3 -and $x -ge 7 -and $x -le 8) { $col = $cIronMid }
        elseif ($y -eq 4 -and $x -ge 6 -and $x -le 9) { $col = $cIronDark }
        elseif ($y -eq 5 -and $x -ge 5 -and $x -le 10) { $col = $cIronMid }
        elseif ($y -ge 6 -and $y -le 11 -and $x -ge 5 -and $x -le 10) {
            if ($x -eq 5 -or $x -eq 10) { $col = $cDark }
            elseif ($x -ge 7 -and $x -le 8 -and $y -ge 8 -and $y -le 9) { $col = $cGlowCore }
            else { $col = $cBright }
        }
        elseif ($y -eq 12 -and $x -ge 5 -and $x -le 10) { $col = $cIronDark }
        elseif ($y -eq 13 -and $x -ge 6 -and $x -le 9) { $col = $cIronDark }
        else { $col = $cClear }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\item\honeycomb_lantern.png"

# 10. honeycomb_lamp.png, honeycomb_lamp_lit.png, honeycomb_lamp_powered.png, honeycomb_lamp_lit_powered.png
function New-LampTexture([bool]$lit, [bool]$powered) {
    $b = New-Bitmap16
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $dx = [Math]::Abs($x - 7.5)
            $dy = [Math]::Abs($y - 7.5)
            $maxD = [Math]::Max($dx, $dy)
            if ($maxD -gt 6.5) {
                $col = $cDarkest
            } elseif ($maxD -gt 5.5) {
                $col = $cIronDark
            } elseif ($dx -le 0.6 -and $dy -le 0.6) {
                $col = if ($powered) { $cRedstone } elseif ($lit) { $cGlowCore } else { $cDark }
            } elseif ($maxD -gt 4.5) {
                $col = $cMid
            } elseif ($maxD -gt 2.5) {
                $col = if ($lit) { $cBright } else { $cMidDark }
            } else {
                $col = if ($lit) { $cGlowCore } else { $cDark }
            }
            $b.SetPixel($x, $y, $col)
        }
    }
    return $b
}
Save-Png (New-LampTexture $false $false) "$assetsRoot\textures\block\honeycomb_lamp.png"
Save-Png (New-LampTexture $true  $false) "$assetsRoot\textures\block\honeycomb_lamp_lit.png"
Save-Png (New-LampTexture $false $true)  "$assetsRoot\textures\block\honeycomb_lamp_powered.png"
Save-Png (New-LampTexture $true  $true)  "$assetsRoot\textures\block\honeycomb_lamp_lit_powered.png"

# 11. item/wax.png (16x16 Fine Wax beeswax cake sprite)
$bmp = New-Bitmap16
$waxMap = @(
    "................",
    "................",
    ".....DDDDDD.....",
    "...DDLLLLLLDD...",
    "..DLLBBBBBBLLD..",
    "..DLBBCCCCBBMD..",
    ".DLBBCMMMMCBMMD.",
    ".DLBBMLLLLMBMMD.",
    ".DMBBMLLLLMBMMD.",
    ".DMBBMMMMMMBMMD.",
    "..DMBBBBBBBMMD..",
    "..DDMMMMMMMMDD..",
    "...DDSSSSSSDD...",
    ".....DDDDDD.....",
    "................",
    "................"
)
for ($y = 0; $y -lt 16; $y++) {
    for ($x = 0; $x -lt 16; $x++) {
        $ch = $waxMap[$y][$x]
        $col = switch ($ch) {
            '.' { $cClear }
            'D' { $cDarkest }
            'S' { $cDark }
            'M' { $cMid }
            'L' { $cLight }
            'B' { $cBright }
            'C' { $cGlowCore }
            default { $cClear }
        }
        $bmp.SetPixel($x, $y, $col)
    }
}
Save-Png $bmp "$assetsRoot\textures\item\wax.png"

# ==============================================================================
# 2. GENERATE BLOCKSTATES, BLOCK MODELS, ITEM MODELS, AND 26.3 ITEMS/*.JSON
# ==============================================================================
function Add-ItemDef($name, $modelPath) {
    $json = @"
{
  "model": {
    "type": "minecraft:model",
    "model": "$modelPath"
  }
}
"@
    Write-JsonFile "$assetsRoot\items\$name.json" $json
}

function Add-CubeAll($name) {
    $bs = @"
{
  "variants": {
    "": {
      "model": "honeycombplus:block/$name"
    }
  }
}
"@
    $bm = @"
{
  "parent": "minecraft:block/cube_all",
  "textures": {
    "all": "honeycombplus:block/$name"
  }
}
"@
    Write-JsonFile "$assetsRoot\blockstates\$name.json" $bs
    Write-JsonFile "$assetsRoot\models\block\$name.json" $bm
    Add-ItemDef $name "honeycombplus:block/$name"
}

function Add-Stairs($name, $texture) {
    $bs = @"
{
  "variants": {
    "facing=east,half=bottom,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 270 },
    "facing=east,half=bottom,shape=inner_right": { "model": "honeycombplus:block/${name}_inner" },
    "facing=east,half=bottom,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 270 },
    "facing=east,half=bottom,shape=outer_right": { "model": "honeycombplus:block/${name}_outer" },
    "facing=east,half=bottom,shape=straight": { "model": "honeycombplus:block/$name" },
    "facing=east,half=top,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180 },
    "facing=east,half=top,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 90 },
    "facing=east,half=top,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180 },
    "facing=east,half=top,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 90 },
    "facing=east,half=top,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "x": 180 },
    "facing=north,half=bottom,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 180 },
    "facing=north,half=bottom,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 270 },
    "facing=north,half=bottom,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 180 },
    "facing=north,half=bottom,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 270 },
    "facing=north,half=bottom,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "y": 270 },
    "facing=north,half=top,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 270 },
    "facing=north,half=top,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180 },
    "facing=north,half=top,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 270 },
    "facing=north,half=top,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180 },
    "facing=north,half=top,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "x": 180, "y": 270 },
    "facing=south,half=bottom,shape=inner_left": { "model": "honeycombplus:block/${name}_inner" },
    "facing=south,half=bottom,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 90 },
    "facing=south,half=bottom,shape=outer_left": { "model": "honeycombplus:block/${name}_outer" },
    "facing=south,half=bottom,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 90 },
    "facing=south,half=bottom,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "y": 90 },
    "facing=south,half=top,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 90 },
    "facing=south,half=top,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 180 },
    "facing=south,half=top,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 90 },
    "facing=south,half=top,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 180 },
    "facing=south,half=top,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "x": 180, "y": 90 },
    "facing=west,half=bottom,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 90 },
    "facing=west,half=bottom,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "y": 180 },
    "facing=west,half=bottom,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 90 },
    "facing=west,half=bottom,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "y": 180 },
    "facing=west,half=bottom,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "y": 180 },
    "facing=west,half=top,shape=inner_left": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 180 },
    "facing=west,half=top,shape=inner_right": { "model": "honeycombplus:block/${name}_inner", "uvlock": true, "x": 180, "y": 270 },
    "facing=west,half=top,shape=outer_left": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 180 },
    "facing=west,half=top,shape=outer_right": { "model": "honeycombplus:block/${name}_outer", "uvlock": true, "x": 180, "y": 270 },
    "facing=west,half=top,shape=straight": { "model": "honeycombplus:block/$name", "uvlock": true, "x": 180, "y": 180 }
  }
}
"@
    Write-JsonFile "$assetsRoot\blockstates\$name.json" $bs
    foreach ($suffix in @(@("", "stairs"), @("_inner", "inner_stairs"), @("_outer", "outer_stairs"))) {
        $s = $suffix[0]
        $p = $suffix[1]
        $bm = @"
{
  "parent": "minecraft:block/$p",
  "textures": {
    "bottom": "$texture",
    "side": "$texture",
    "top": "$texture"
  }
}
"@
        Write-JsonFile "$assetsRoot\models\block\${name}${s}.json" $bm
    }
    Add-ItemDef $name "honeycombplus:block/$name"
}

function Add-Slab($name, $doubleModel, $texture) {
    $bs = @"
{
  "variants": {
    "type=bottom": { "model": "honeycombplus:block/$name" },
    "type=double": { "model": "$doubleModel" },
    "type=top": { "model": "honeycombplus:block/${name}_top" }
  }
}
"@
    Write-JsonFile "$assetsRoot\blockstates\$name.json" $bs
    $bmBottom = @"
{
  "parent": "minecraft:block/slab",
  "textures": {
    "bottom": "$texture",
    "side": "$texture",
    "top": "$texture"
  }
}
"@
    $bmTop = @"
{
  "parent": "minecraft:block/slab_top",
  "textures": {
    "bottom": "$texture",
    "side": "$texture",
    "top": "$texture"
  }
}
"@
    Write-JsonFile "$assetsRoot\models\block\$name.json" $bmBottom
    Write-JsonFile "$assetsRoot\models\block\${name}_top.json" $bmTop
    Add-ItemDef $name "honeycombplus:block/$name"
}

function Add-Wall($name, $texture) {
    $bs = @"
{
  "multipart": [
    {
      "apply": { "model": "honeycombplus:block/${name}_post" },
      "when": { "up": "true" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side", "uvlock": true },
      "when": { "north": "low" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side", "uvlock": true, "y": 90 },
      "when": { "east": "low" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side", "uvlock": true, "y": 180 },
      "when": { "south": "low" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side", "uvlock": true, "y": 270 },
      "when": { "west": "low" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side_tall", "uvlock": true },
      "when": { "north": "tall" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side_tall", "uvlock": true, "y": 90 },
      "when": { "east": "tall" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side_tall", "uvlock": true, "y": 180 },
      "when": { "south": "tall" }
    },
    {
      "apply": { "model": "honeycombplus:block/${name}_side_tall", "uvlock": true, "y": 270 },
      "when": { "west": "tall" }
    }
  ]
}
"@
    Write-JsonFile "$assetsRoot\blockstates\$name.json" $bs
    foreach ($pair in @(@("_post", "template_wall_post"), @("_side", "template_wall_side"), @("_side_tall", "template_wall_side_tall"), @("_inventory", "wall_inventory"))) {
        $s = $pair[0]
        $p = $pair[1]
        $bm = @"
{
  "parent": "minecraft:block/$p",
  "textures": {
    "wall": "$texture"
  }
}
"@
        Write-JsonFile "$assetsRoot\models\block\${name}${s}.json" $bm
    }
    Add-ItemDef $name "honeycombplus:block/${name}_inventory"
}

# Structural sets
Add-Stairs "honeycomb_stairs" "minecraft:block/honeycomb_block"
Add-Slab   "honeycomb_slab"   "minecraft:block/honeycomb_block" "minecraft:block/honeycomb_block"
Add-Wall   "honeycomb_wall"   "minecraft:block/honeycomb_block"

Add-CubeAll "polished_honeycomb"
Add-Stairs  "polished_honeycomb_stairs" "honeycombplus:block/polished_honeycomb"
Add-Slab    "polished_honeycomb_slab"   "honeycombplus:block/polished_honeycomb" "honeycombplus:block/polished_honeycomb"
Add-Wall    "polished_honeycomb_wall"   "honeycombplus:block/polished_honeycomb"

Add-CubeAll "cut_honeycomb"
Add-Stairs  "cut_honeycomb_stairs" "honeycombplus:block/cut_honeycomb"
Add-Slab    "cut_honeycomb_slab"   "honeycombplus:block/cut_honeycomb" "honeycombplus:block/cut_honeycomb"
Add-Wall    "cut_honeycomb_wall"   "honeycombplus:block/cut_honeycomb"

Add-CubeAll "honeycomb_bricks"
Add-Stairs  "honeycomb_brick_stairs" "honeycombplus:block/honeycomb_bricks"
Add-Slab    "honeycomb_brick_slab"   "honeycombplus:block/honeycomb_bricks" "honeycombplus:block/honeycomb_bricks"
Add-Wall    "honeycomb_brick_wall"   "honeycombplus:block/honeycomb_bricks"

Add-CubeAll "chiseled_honeycomb"

# Honeycomb Pillar
Write-JsonFile "$assetsRoot\blockstates\honeycomb_pillar.json" @"
{
  "variants": {
    "axis=x": { "model": "honeycombplus:block/honeycomb_pillar_horizontal", "x": 90, "y": 90 },
    "axis=y": { "model": "honeycombplus:block/honeycomb_pillar" },
    "axis=z": { "model": "honeycombplus:block/honeycomb_pillar_horizontal", "x": 90 }
  }
}
"@
Write-JsonFile "$assetsRoot\models\block\honeycomb_pillar.json" @"
{
  "parent": "minecraft:block/cube_column",
  "textures": {
    "end": "honeycombplus:block/honeycomb_pillar_top",
    "side": "honeycombplus:block/honeycomb_pillar"
  }
}
"@
Write-JsonFile "$assetsRoot\models\block\honeycomb_pillar_horizontal.json" @"
{
  "parent": "minecraft:block/cube_column_horizontal",
  "textures": {
    "end": "honeycombplus:block/honeycomb_pillar_top",
    "side": "honeycombplus:block/honeycomb_pillar"
  }
}
"@
Add-ItemDef "honeycomb_pillar" "honeycombplus:block/honeycomb_pillar"

# Honeycomb Grate
Add-CubeAll "honeycomb_grate"

# Honeycomb Bars
Write-JsonFile "$assetsRoot\blockstates\honeycomb_bars.json" @"
{
  "multipart": [
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_post_ends" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_post" },
      "when": { "east": "false", "north": "false", "south": "false", "west": "false" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_cap" },
      "when": { "east": "false", "north": "true", "south": "false", "west": "false" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_cap", "y": 90 },
      "when": { "east": "true", "north": "false", "south": "false", "west": "false" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_cap_alt" },
      "when": { "east": "false", "north": "false", "south": "true", "west": "false" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_cap_alt", "y": 90 },
      "when": { "east": "false", "north": "false", "south": "false", "west": "true" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_side" },
      "when": { "north": "true" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_side", "y": 90 },
      "when": { "east": "true" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_side_alt" },
      "when": { "south": "true" }
    },
    {
      "apply": { "model": "honeycombplus:block/honeycomb_bars_side_alt", "y": 90 },
      "when": { "west": "true" }
    }
  ]
}
"@
foreach ($s in @("post", "post_ends", "cap", "cap_alt", "side", "side_alt")) {
    Write-JsonFile "$assetsRoot\models\block\honeycomb_bars_$s.json" @"
{
  "parent": "minecraft:block/template_bars_$s",
  "textures": {
    "bars": "honeycombplus:block/honeycomb_bars",
    "edge": "honeycombplus:block/honeycomb_bars"
  }
}
"@
}
Write-JsonFile "$assetsRoot\models\item\honeycomb_bars.json" @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": "honeycombplus:block/honeycomb_bars"
  }
}
"@
Add-ItemDef "honeycomb_bars" "honeycombplus:item/honeycomb_bars"

# Honeyed Glass & Honeyed Glass Pane (with force_translucent: true)
Write-JsonFile "$assetsRoot\blockstates\honeyed_glass.json" @"
{
  "variants": {
    "": { "model": "honeycombplus:block/honeyed_glass" }
  }
}
"@
Write-JsonFile "$assetsRoot\models\block\honeyed_glass.json" @"
{
  "parent": "minecraft:block/cube_all",
  "textures": {
    "all": {
      "force_translucent": true,
      "sprite": "honeycombplus:block/honeyed_glass"
    }
  }
}
"@
Add-ItemDef "honeyed_glass" "honeycombplus:block/honeyed_glass"

Write-JsonFile "$assetsRoot\blockstates\honeyed_glass_pane.json" @"
{
  "multipart": [
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_post" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_side" }, "when": { "north": "true" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_side", "y": 90 }, "when": { "east": "true" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_side_alt" }, "when": { "south": "true" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_side_alt", "y": 90 }, "when": { "west": "true" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_noside" }, "when": { "north": "false" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_noside_alt" }, "when": { "east": "false" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_noside_alt", "y": 90 }, "when": { "south": "false" } },
    { "apply": { "model": "honeycombplus:block/honeyed_glass_pane_noside", "y": 270 }, "when": { "west": "false" } }
  ]
}
"@
foreach ($s in @("post", "side", "side_alt", "noside", "noside_alt")) {
    Write-JsonFile "$assetsRoot\models\block\honeyed_glass_pane_$s.json" @"
{
  "parent": "minecraft:block/template_glass_pane_$s",
  "textures": {
    "edge": {
      "force_translucent": true,
      "sprite": "honeycombplus:block/honeyed_glass_pane_top"
    },
    "pane": {
      "force_translucent": true,
      "sprite": "honeycombplus:block/honeyed_glass"
    }
  }
}
"@
}
Write-JsonFile "$assetsRoot\models\item\honeyed_glass_pane.json" @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": {
      "force_translucent": true,
      "sprite": "honeycombplus:block/honeyed_glass"
    }
  }
}
"@
Add-ItemDef "honeyed_glass_pane" "honeycombplus:item/honeyed_glass_pane"

# Honeycomb Door & Trapdoor
Write-JsonFile "$assetsRoot\blockstates\honeycomb_door.json" @"
{
  "variants": {
    "facing=east,half=lower,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_left" },
    "facing=east,half=lower,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_left_open", "y": 90 },
    "facing=east,half=lower,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_right" },
    "facing=east,half=lower,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_right_open", "y": 270 },
    "facing=east,half=upper,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_top_left" },
    "facing=east,half=upper,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_top_left_open", "y": 90 },
    "facing=east,half=upper,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_top_right" },
    "facing=east,half=upper,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_top_right_open", "y": 270 },
    "facing=north,half=lower,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_left", "y": 270 },
    "facing=north,half=lower,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_left_open" },
    "facing=north,half=lower,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_right", "y": 270 },
    "facing=north,half=lower,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_right_open", "y": 180 },
    "facing=north,half=upper,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_top_left", "y": 270 },
    "facing=north,half=upper,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_top_left_open" },
    "facing=north,half=upper,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_top_right", "y": 270 },
    "facing=north,half=upper,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_top_right_open", "y": 180 },
    "facing=south,half=lower,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_left", "y": 90 },
    "facing=south,half=lower,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_left_open", "y": 180 },
    "facing=south,half=lower,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_right", "y": 90 },
    "facing=south,half=lower,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_right_open" },
    "facing=south,half=upper,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_top_left", "y": 90 },
    "facing=south,half=upper,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_top_left_open", "y": 180 },
    "facing=south,half=upper,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_top_right", "y": 90 },
    "facing=south,half=upper,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_top_right_open" },
    "facing=west,half=lower,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_left", "y": 180 },
    "facing=west,half=lower,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_left_open", "y": 270 },
    "facing=west,half=lower,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_bottom_right", "y": 180 },
    "facing=west,half=lower,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_bottom_right_open", "y": 90 },
    "facing=west,half=upper,hinge=left,open=false": { "model": "honeycombplus:block/honeycomb_door_top_left", "y": 180 },
    "facing=west,half=upper,hinge=left,open=true": { "model": "honeycombplus:block/honeycomb_door_top_left_open", "y": 270 },
    "facing=west,half=upper,hinge=right,open=false": { "model": "honeycombplus:block/honeycomb_door_top_right", "y": 180 },
    "facing=west,half=upper,hinge=right,open=true": { "model": "honeycombplus:block/honeycomb_door_top_right_open", "y": 90 }
  }
}
"@
foreach ($s in @("bottom_left", "bottom_left_open", "bottom_right", "bottom_right_open", "top_left", "top_left_open", "top_right", "top_right_open")) {
    Write-JsonFile "$assetsRoot\models\block\honeycomb_door_$s.json" @"
{
  "parent": "minecraft:block/door_$s",
  "textures": {
    "bottom": "honeycombplus:block/honeycomb_door_bottom",
    "top": "honeycombplus:block/honeycomb_door_top"
  }
}
"@
}
Write-JsonFile "$assetsRoot\models\item\honeycomb_door.json" @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": "honeycombplus:item/honeycomb_door"
  }
}
"@
Add-ItemDef "honeycomb_door" "honeycombplus:item/honeycomb_door"

Write-JsonFile "$assetsRoot\blockstates\honeycomb_trapdoor.json" @"
{
  "variants": {
    "facing=east,half=bottom,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_bottom" },
    "facing=east,half=bottom,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 90 },
    "facing=east,half=top,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_top" },
    "facing=east,half=top,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 90 },
    "facing=north,half=bottom,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_bottom" },
    "facing=north,half=bottom,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open" },
    "facing=north,half=top,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_top" },
    "facing=north,half=top,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open" },
    "facing=south,half=bottom,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_bottom" },
    "facing=south,half=bottom,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 180 },
    "facing=south,half=top,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_top" },
    "facing=south,half=top,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 180 },
    "facing=west,half=bottom,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_bottom" },
    "facing=west,half=bottom,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 270 },
    "facing=west,half=top,open=false": { "model": "honeycombplus:block/honeycomb_trapdoor_top" },
    "facing=west,half=top,open=true": { "model": "honeycombplus:block/honeycomb_trapdoor_open", "y": 270 }
  }
}
"@
foreach ($s in @("bottom", "top", "open")) {
    Write-JsonFile "$assetsRoot\models\block\honeycomb_trapdoor_$s.json" @"
{
  "parent": "minecraft:block/template_trapdoor_$s",
  "textures": {
    "texture": "honeycombplus:block/honeycomb_trapdoor"
  }
}
"@
}
Add-ItemDef "honeycomb_trapdoor" "honeycombplus:block/honeycomb_trapdoor_bottom"

# Honeycomb Lantern
Write-JsonFile "$assetsRoot\blockstates\honeycomb_lantern.json" @"
{
  "variants": {
    "hanging=false": { "model": "honeycombplus:block/honeycomb_lantern" },
    "hanging=true": { "model": "honeycombplus:block/honeycomb_lantern_hanging" }
  }
}
"@
Write-JsonFile "$assetsRoot\models\block\honeycomb_lantern.json" @"
{
  "parent": "minecraft:block/template_lantern",
  "textures": {
    "lantern": "honeycombplus:block/honeycomb_lantern"
  }
}
"@
Write-JsonFile "$assetsRoot\models\block\honeycomb_lantern_hanging.json" @"
{
  "parent": "minecraft:block/template_hanging_lantern",
  "textures": {
    "lantern": "honeycombplus:block/honeycomb_lantern"
  }
}
"@
Write-JsonFile "$assetsRoot\models\item\honeycomb_lantern.json" @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": "honeycombplus:item/honeycomb_lantern"
  }
}
"@
Add-ItemDef "honeycomb_lantern" "honeycombplus:item/honeycomb_lantern"

# Honeycomb Lamp
Write-JsonFile "$assetsRoot\blockstates\honeycomb_lamp.json" @"
{
  "variants": {
    "lit=false,powered=false": { "model": "honeycombplus:block/honeycomb_lamp" },
    "lit=false,powered=true": { "model": "honeycombplus:block/honeycomb_lamp_powered" },
    "lit=true,powered=false": { "model": "honeycombplus:block/honeycomb_lamp_lit" },
    "lit=true,powered=true": { "model": "honeycombplus:block/honeycomb_lamp_lit_powered" }
  }
}
"@
foreach ($s in @("", "_lit", "_powered", "_lit_powered")) {
    Write-JsonFile "$assetsRoot\models\block\honeycomb_lamp$s.json" @"
{
  "parent": "minecraft:block/cube_all",
  "textures": {
    "all": "honeycombplus:block/honeycomb_lamp$s"
  }
}
"@
}
Add-ItemDef "honeycomb_lamp" "honeycombplus:block/honeycomb_lamp"

# Fine Wax Item Model & Definition
Write-JsonFile "$assetsRoot\models\item\wax.json" @"
{
  "parent": "minecraft:item/generated",
  "textures": {
    "layer0": "honeycombplus:item/wax"
  }
}
"@
Add-ItemDef "wax" "honeycombplus:item/wax"

# ==============================================================================
# 3. LANGUAGE FILE (en_us.json)
# ==============================================================================
Write-JsonFile "$assetsRoot\lang\en_us.json" @"
{
  "itemGroup.honeycombplus.honeycomb_plus": "Honeycomb Plus",
  "item.honeycombplus.wax": "Fine Wax",
  "block.honeycombplus.honeycomb_stairs": "Honeycomb Stairs",
  "block.honeycombplus.honeycomb_slab": "Honeycomb Slab",
  "block.honeycombplus.honeycomb_wall": "Honeycomb Wall",
  "block.honeycombplus.polished_honeycomb": "Polished Honeycomb",
  "block.honeycombplus.polished_honeycomb_stairs": "Polished Honeycomb Stairs",
  "block.honeycombplus.polished_honeycomb_slab": "Polished Honeycomb Slab",
  "block.honeycombplus.polished_honeycomb_wall": "Polished Honeycomb Wall",
  "block.honeycombplus.cut_honeycomb": "Cut Honeycomb",
  "block.honeycombplus.cut_honeycomb_stairs": "Cut Honeycomb Stairs",
  "block.honeycombplus.cut_honeycomb_slab": "Cut Honeycomb Slab",
  "block.honeycombplus.cut_honeycomb_wall": "Cut Honeycomb Wall",
  "block.honeycombplus.honeycomb_bricks": "Honeycomb Bricks",
  "block.honeycombplus.honeycomb_brick_stairs": "Honeycomb Brick Stairs",
  "block.honeycombplus.honeycomb_brick_slab": "Honeycomb Brick Slab",
  "block.honeycombplus.honeycomb_brick_wall": "Honeycomb Brick Wall",
  "block.honeycombplus.chiseled_honeycomb": "Chiseled Honeycomb",
  "block.honeycombplus.honeycomb_pillar": "Honeycomb Pillar",
  "block.honeycombplus.honeycomb_grate": "Honeycomb Grate",
  "block.honeycombplus.honeycomb_bars": "Honeycomb Bars",
  "block.honeycombplus.honeycomb_door": "Honeycomb Door",
  "block.honeycombplus.honeycomb_trapdoor": "Honeycomb Trapdoor",
  "block.honeycombplus.honeyed_glass": "Honeyed Glass",
  "block.honeycombplus.honeyed_glass_pane": "Honeyed Glass Pane",
  "block.honeycombplus.honeycomb_lantern": "Honeycomb Lantern",
  "block.honeycombplus.honeycomb_lamp": "Honeycomb Lamp"
}
"@

# ==============================================================================
# 4. RECHISELED COMPATIBILITY (data/honeycombplus/chiseling_recipes/*.json)
# ==============================================================================
Remove-Item "$dataRoot\chiseling_recipes\*.json" -Force -ErrorAction SilentlyContinue

Write-JsonFile "$dataRoot\chiseling_recipes\honeycomb_block.json" @"
{
  "entries": [
    { "item": "minecraft:honeycomb_block" },
    { "item": "honeycombplus:honeycomb_stairs" },
    { "item": "honeycombplus:honeycomb_slab" },
    { "item": "honeycombplus:honeycomb_wall" }
  ]
}
"@

Write-JsonFile "$dataRoot\chiseling_recipes\polished_honeycomb.json" @"
{
  "entries": [
    { "item": "honeycombplus:polished_honeycomb" },
    { "item": "honeycombplus:cut_honeycomb" },
    { "item": "honeycombplus:honeycomb_bricks" },
    { "item": "honeycombplus:chiseled_honeycomb" },
    { "item": "honeycombplus:honeycomb_pillar" },
    { "item": "honeycombplus:honeycomb_grate" }
  ]
}
"@

Write-JsonFile "$dataRoot\chiseling_recipes\polished_honeycomb_stairs.json" @"
{
  "entries": [
    { "item": "honeycombplus:polished_honeycomb_stairs" },
    { "item": "honeycombplus:cut_honeycomb_stairs" },
    { "item": "honeycombplus:honeycomb_brick_stairs" }
  ]
}
"@

Write-JsonFile "$dataRoot\chiseling_recipes\polished_honeycomb_slab.json" @"
{
  "entries": [
    { "item": "honeycombplus:polished_honeycomb_slab" },
    { "item": "honeycombplus:cut_honeycomb_slab" },
    { "item": "honeycombplus:honeycomb_brick_slab" }
  ]
}
"@

Write-JsonFile "$dataRoot\chiseling_recipes\polished_honeycomb_wall.json" @"
{
  "entries": [
    { "item": "honeycombplus:polished_honeycomb_wall" },
    { "item": "honeycombplus:cut_honeycomb_wall" },
    { "item": "honeycombplus:honeycomb_brick_wall" }
  ]
}
"@

# ==============================================================================
# 5. LOOT TABLES (Minecraft 26.3 schema)
# ==============================================================================
$standardDropBlocks = @(
    "honeycomb_stairs", "honeycomb_wall",
    "polished_honeycomb", "polished_honeycomb_stairs", "polished_honeycomb_wall",
    "cut_honeycomb", "cut_honeycomb_stairs", "cut_honeycomb_wall",
    "honeycomb_bricks", "honeycomb_brick_stairs", "honeycomb_brick_wall",
    "chiseled_honeycomb", "honeycomb_pillar",
    "honeycomb_grate", "honeycomb_bars",
    "honeycomb_trapdoor",
    "honeyed_glass", "honeyed_glass_pane",
    "honeycomb_lantern", "honeycomb_lamp"
)
foreach ($b in $standardDropBlocks) {
    Write-JsonFile "$dataRoot\loot_table\blocks\$b.json" @"
{
  "type": "minecraft:block",
  "pools": [
    {
      "condition": {
        "type": "minecraft:survives_explosion"
      },
      "entries": [
        {
          "type": "minecraft:item",
          "name": "honeycombplus:$b"
        }
      ],
      "rolls": 1
    }
  ],
  "random_sequence": "honeycombplus:blocks/$b"
}
"@
}

$slabBlocks = @("honeycomb_slab", "polished_honeycomb_slab", "cut_honeycomb_slab", "honeycomb_brick_slab")
foreach ($b in $slabBlocks) {
    Write-JsonFile "$dataRoot\loot_table\blocks\$b.json" @"
{
  "type": "minecraft:block",
  "pools": [
    {
      "entries": [
        {
          "type": "minecraft:item",
          "modifier": [
            {
              "type": "minecraft:set_count",
              "condition": {
                "type": "minecraft:match_block",
                "blocks": "honeycombplus:$b",
                "state": {
                  "type": "double"
                }
              },
              "count": 2
            },
            {
              "type": "minecraft:explosion_decay"
            }
          ],
          "name": "honeycombplus:$b"
        }
      ],
      "rolls": 1
    }
  ],
  "random_sequence": "honeycombplus:blocks/$b"
}
"@
}

Write-JsonFile "$dataRoot\loot_table\blocks\honeycomb_door.json" @"
{
  "type": "minecraft:block",
  "pools": [
    {
      "condition": {
        "type": "minecraft:survives_explosion"
      },
      "entries": [
        {
          "type": "minecraft:item",
          "condition": {
            "type": "minecraft:match_block",
            "blocks": "honeycombplus:honeycomb_door",
            "state": {
              "half": "lower"
            }
          },
          "name": "honeycombplus:honeycomb_door"
        }
      ],
      "rolls": 1
    }
  ],
  "random_sequence": "honeycombplus:blocks/honeycomb_door"
}
"@

# ==============================================================================
# 6. CRAFTING, SMELTING & STONECUTTER RECIPES (data/honeycombplus/recipe/*.json)
# ==============================================================================
Remove-Item "$dataRoot\recipe\*.json" -Force -ErrorAction SilentlyContinue

function Add-2x2Recipe($name, $ingredient, $result, $count) {
    Write-JsonFile "$dataRoot\recipe\$name.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "$ingredient"
  },
  "pattern": [
    "##",
    "##"
  ],
  "result": {
    "count": $count,
    "id": "$result"
  }
}
"@
}

function Add-StairSlabWallRecipes($prefix, $ingredient) {
    $stairName = "${prefix}_stairs"
    $slabName  = "${prefix}_slab"
    $wallName  = "${prefix}_wall"
    Write-JsonFile "$dataRoot\recipe\$stairName.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "$ingredient"
  },
  "pattern": [
    "#  ",
    "## ",
    "###"
  ],
  "result": {
    "count": 4,
    "id": "honeycombplus:$stairName"
  }
}
"@
    Write-JsonFile "$dataRoot\recipe\$slabName.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "$ingredient"
  },
  "pattern": [
    "###"
  ],
  "result": {
    "count": 6,
    "id": "honeycombplus:$slabName"
  }
}
"@
    Write-JsonFile "$dataRoot\recipe\$wallName.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "$ingredient"
  },
  "pattern": [
    "###",
    "###"
  ],
  "result": {
    "count": 6,
    "id": "honeycombplus:$wallName"
  }
}
"@
}

function Add-Stonecutting($fileName, $ingredient, $result, $count) {
    $countField = if ($count -gt 1) { "`n    `"count`": $count," } else { "" }
    Write-JsonFile "$dataRoot\recipe\$fileName.json" @"
{
  "type": "minecraft:stonecutting",
  "ingredient": "$ingredient",
  "result": {$countField
    "id": "$result"
  }
}
"@
}

# Fine Wax Smelting / Smoking / Campfire Cooking Recipes
Write-JsonFile "$dataRoot\recipe\wax_from_smelting_honeycomb.json" @"
{
  "type": "minecraft:smelting",
  "category": "misc",
  "cookingtime": 200,
  "experience": 0.2,
  "ingredient": "minecraft:honeycomb",
  "result": {
    "id": "honeycombplus:wax"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\wax_from_smoking_honeycomb.json" @"
{
  "type": "minecraft:smoking",
  "category": "misc",
  "cookingtime": 100,
  "experience": 0.2,
  "ingredient": "minecraft:honeycomb",
  "result": {
    "id": "honeycombplus:wax"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\wax_from_campfire_cooking_honeycomb.json" @"
{
  "type": "minecraft:campfire_cooking",
  "category": "misc",
  "cookingtime": 600,
  "experience": 0.2,
  "ingredient": "minecraft:honeycomb",
  "result": {
    "id": "honeycombplus:wax"
  }
}
"@

# Structural Crafting Recipes (Polished Honeycomb from 1 Fine Wax + 1 Any Wood Plank)
Write-JsonFile "$dataRoot\recipe\polished_honeycomb.json" @"
{
  "type": "minecraft:crafting_shapeless",
  "category": "building",
  "ingredients": [
    "honeycombplus:wax",
    "#minecraft:planks"
  ],
  "result": {
    "count": 1,
    "id": "honeycombplus:polished_honeycomb"
  }
}
"@

Add-2x2Recipe "cut_honeycomb" "honeycombplus:polished_honeycomb" "honeycombplus:cut_honeycomb" 4
Add-2x2Recipe "honeycomb_bricks" "honeycombplus:cut_honeycomb" "honeycombplus:honeycomb_bricks" 4

Write-JsonFile "$dataRoot\recipe\chiseled_honeycomb.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "honeycombplus:polished_honeycomb_slab"
  },
  "pattern": [
    "#",
    "#"
  ],
  "result": {
    "count": 1,
    "id": "honeycombplus:chiseled_honeycomb"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_pillar.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "honeycombplus:polished_honeycomb"
  },
  "pattern": [
    "#",
    "#"
  ],
  "result": {
    "count": 2,
    "id": "honeycombplus:honeycomb_pillar"
  }
}
"@

Add-StairSlabWallRecipes "honeycomb" "minecraft:honeycomb_block"
Add-StairSlabWallRecipes "polished_honeycomb" "honeycombplus:polished_honeycomb"
Add-StairSlabWallRecipes "cut_honeycomb" "honeycombplus:cut_honeycomb"
Add-StairSlabWallRecipes "honeycomb_brick" "honeycombplus:honeycomb_bricks"

# Functional & Decorative Crafting Recipes (Tied to Polished Honeycomb, Fine Wax & Gold Nuggets)
Write-JsonFile "$dataRoot\recipe\honeycomb_grate.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "#": "honeycombplus:polished_honeycomb"
  },
  "pattern": [
    " # ",
    "# #",
    " # "
  ],
  "result": {
    "count": 4,
    "id": "honeycombplus:honeycomb_grate"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_bars.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "misc",
  "key": {
    "#": "honeycombplus:polished_honeycomb"
  },
  "pattern": [
    "###",
    "###"
  ],
  "result": {
    "count": 16,
    "id": "honeycombplus:honeycomb_bars"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_door.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "redstone",
  "key": {
    "#": "honeycombplus:polished_honeycomb"
  },
  "pattern": [
    "##",
    "##",
    "##"
  ],
  "result": {
    "count": 3,
    "id": "honeycombplus:honeycomb_door"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_trapdoor.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "redstone",
  "key": {
    "#": "honeycombplus:polished_honeycomb"
  },
  "pattern": [
    "###",
    "###"
  ],
  "result": {
    "count": 2,
    "id": "honeycombplus:honeycomb_trapdoor"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeyed_glass.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "building",
  "key": {
    "G": "minecraft:glass",
    "H": "minecraft:honey_bottle"
  },
  "pattern": [
    "GGG",
    "GHG",
    "GGG"
  ],
  "result": {
    "count": 8,
    "id": "honeycombplus:honeyed_glass"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeyed_glass_pane.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "misc",
  "key": {
    "#": "honeycombplus:honeyed_glass"
  },
  "pattern": [
    "###",
    "###"
  ],
  "result": {
    "count": 16,
    "id": "honeycombplus:honeyed_glass_pane"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_lantern.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "misc",
  "key": {
    "N": "minecraft:gold_nugget",
    "T": "minecraft:torch",
    "W": "honeycombplus:wax"
  },
  "pattern": [
    "NWN",
    "WTW",
    "NWN"
  ],
  "result": {
    "count": 1,
    "id": "honeycombplus:honeycomb_lantern"
  }
}
"@

Write-JsonFile "$dataRoot\recipe\honeycomb_lamp.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "redstone",
  "key": {
    "G": "minecraft:glowstone_dust",
    "H": "honeycombplus:polished_honeycomb",
    "N": "minecraft:gold_nugget",
    "R": "minecraft:redstone"
  },
  "pattern": [
    "NHN",
    "HGH",
    "NRN"
  ],
  "result": {
    "count": 4,
    "id": "honeycombplus:honeycomb_lamp"
  }
}
"@

# Vanilla Candle Crafting with Fine Wax (1 String + 1 Fine Wax -> 2 Candles)
Write-JsonFile "$dataRoot\recipe\candle_from_wax.json" @"
{
  "type": "minecraft:crafting_shaped",
  "category": "misc",
  "key": {
    "S": "minecraft:string",
    "W": "honeycombplus:wax"
  },
  "pattern": [
    "S",
    "W"
  ],
  "result": {
    "count": 2,
    "id": "minecraft:candle"
  }
}
"@

# Generate all 60 Waxed Copper Crafting Recipes using Fine Wax from the cached Minecraft 26.3 common jar
$commonJar = Get-ChildItem -Path "$env:USERPROFILE\.gradle\caches\fabric-loom" -Recurse -Filter "*common*26.3*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($commonJar) {
    $cZip = [System.IO.Compression.ZipFile]::OpenRead($commonJar.FullName)
    try {
        $waxRecipes = $cZip.Entries | Where-Object { $_.FullName -match '^data/minecraft/recipe/waxed_.*_from_honeycomb\.json$' }
        foreach ($entry in $waxRecipes) {
            $sr = New-Object System.IO.StreamReader($entry.Open())
            $jsonText = $sr.ReadToEnd()
            $sr.Close()
            $waxJsonText = $jsonText.Replace('"minecraft:honeycomb"', '"honeycombplus:wax"')
            $newFileName = $entry.Name.Replace('_from_honeycomb.json', '_from_wax.json')
            Write-JsonFile "$dataRoot\recipe\$newFileName" $waxJsonText
        }
    } finally {
        $cZip.Dispose()
    }
}

# Stonecutter Recipes from minecraft:honeycomb_block (only base stairs, slab, wall)
$fromBaseStonecut = @(
    @("honeycomb_stairs", 1),
    @("honeycomb_slab", 2),
    @("honeycomb_wall", 1)
)
foreach ($entry in $fromBaseStonecut) {
    $target = $entry[0]
    $cnt = $entry[1]
    Add-Stonecutting "${target}_from_honeycomb_block_stonecutting" "minecraft:honeycomb_block" "honeycombplus:$target" $cnt
}

# Stonecutter Recipes from honeycombplus:polished_honeycomb (root of refined structural tier)
$fromPolishedStonecut = @(
    @("polished_honeycomb_stairs", 1),
    @("polished_honeycomb_slab", 2),
    @("polished_honeycomb_wall", 1),
    @("cut_honeycomb", 1),
    @("cut_honeycomb_stairs", 1),
    @("cut_honeycomb_slab", 2),
    @("cut_honeycomb_wall", 1),
    @("honeycomb_bricks", 1),
    @("honeycomb_brick_stairs", 1),
    @("honeycomb_brick_slab", 2),
    @("honeycomb_brick_wall", 1),
    @("chiseled_honeycomb", 1),
    @("honeycomb_pillar", 1),
    @("honeycomb_grate", 1),
    @("honeycomb_bars", 4)
)
foreach ($entry in $fromPolishedStonecut) {
    $target = $entry[0]
    $cnt = $entry[1]
    Add-Stonecutting "${target}_from_polished_honeycomb_stonecutting" "honeycombplus:polished_honeycomb" "honeycombplus:$target" $cnt
}

# Stonecutter Recipes from honeycombplus:cut_honeycomb
$fromCutStonecut = @(
    @("cut_honeycomb_stairs", 1),
    @("cut_honeycomb_slab", 2),
    @("cut_honeycomb_wall", 1),
    @("honeycomb_bricks", 1),
    @("honeycomb_brick_stairs", 1),
    @("honeycomb_brick_slab", 2),
    @("honeycomb_brick_wall", 1),
    @("chiseled_honeycomb", 1)
)
foreach ($entry in $fromCutStonecut) {
    $target = $entry[0]
    $cnt = $entry[1]
    Add-Stonecutting "${target}_from_cut_honeycomb_stonecutting" "honeycombplus:cut_honeycomb" "honeycombplus:$target" $cnt
}

# Stonecutter Recipes from honeycombplus:honeycomb_bricks
$fromBricksStonecut = @(
    @("honeycomb_brick_stairs", 1),
    @("honeycomb_brick_slab", 2),
    @("honeycomb_brick_wall", 1)
)
foreach ($entry in $fromBricksStonecut) {
    $target = $entry[0]
    $cnt = $entry[1]
    Add-Stonecutting "${target}_from_honeycomb_bricks_stonecutting" "honeycombplus:honeycomb_bricks" "honeycombplus:$target" $cnt
}

# ==============================================================================
# 7. BLOCK & ITEM TAGS
# ==============================================================================
Write-JsonFile "$mcTagsBlock\mineable\pickaxe.json" @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_stairs",
    "honeycombplus:honeycomb_slab",
    "honeycombplus:honeycomb_wall",
    "honeycombplus:polished_honeycomb",
    "honeycombplus:polished_honeycomb_stairs",
    "honeycombplus:polished_honeycomb_slab",
    "honeycombplus:polished_honeycomb_wall",
    "honeycombplus:cut_honeycomb",
    "honeycombplus:cut_honeycomb_stairs",
    "honeycombplus:cut_honeycomb_slab",
    "honeycombplus:cut_honeycomb_wall",
    "honeycombplus:honeycomb_bricks",
    "honeycombplus:honeycomb_brick_stairs",
    "honeycombplus:honeycomb_brick_slab",
    "honeycombplus:honeycomb_brick_wall",
    "honeycombplus:chiseled_honeycomb",
    "honeycombplus:honeycomb_pillar",
    "honeycombplus:honeycomb_grate",
    "honeycombplus:honeycomb_bars",
    "honeycombplus:honeycomb_door",
    "honeycombplus:honeycomb_trapdoor",
    "honeycombplus:honeyed_glass",
    "honeycombplus:honeyed_glass_pane",
    "honeycombplus:honeycomb_lantern",
    "honeycombplus:honeycomb_lamp"
  ]
}
"@

Write-JsonFile "$mcTagsBlock\mineable\hoe.json" @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_stairs",
    "honeycombplus:honeycomb_slab",
    "honeycombplus:honeycomb_wall",
    "honeycombplus:polished_honeycomb",
    "honeycombplus:polished_honeycomb_stairs",
    "honeycombplus:polished_honeycomb_slab",
    "honeycombplus:polished_honeycomb_wall",
    "honeycombplus:cut_honeycomb",
    "honeycombplus:cut_honeycomb_stairs",
    "honeycombplus:cut_honeycomb_slab",
    "honeycombplus:cut_honeycomb_wall",
    "honeycombplus:honeycomb_bricks",
    "honeycombplus:honeycomb_brick_stairs",
    "honeycombplus:honeycomb_brick_slab",
    "honeycombplus:honeycomb_brick_wall",
    "honeycombplus:chiseled_honeycomb",
    "honeycombplus:honeycomb_pillar",
    "honeycombplus:honeycomb_grate",
    "honeycombplus:honeycomb_bars",
    "honeycombplus:honeycomb_door",
    "honeycombplus:honeycomb_trapdoor",
    "honeycombplus:honeyed_glass",
    "honeycombplus:honeyed_glass_pane",
    "honeycombplus:honeycomb_lamp"
  ]
}
"@

Write-JsonFile "$mcTagsBlock\mineable\axe.json" @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_door",
    "honeycombplus:honeycomb_trapdoor"
  ]
}
"@

$stairsJson = @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_stairs",
    "honeycombplus:polished_honeycomb_stairs",
    "honeycombplus:cut_honeycomb_stairs",
    "honeycombplus:honeycomb_brick_stairs"
  ]
}
"@
$slabsJson = @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_slab",
    "honeycombplus:polished_honeycomb_slab",
    "honeycombplus:cut_honeycomb_slab",
    "honeycombplus:honeycomb_brick_slab"
  ]
}
"@
$wallsJson = @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_wall",
    "honeycombplus:polished_honeycomb_wall",
    "honeycombplus:cut_honeycomb_wall",
    "honeycombplus:honeycomb_brick_wall"
  ]
}
"@
$doorsJson = @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_door"
  ]
}
"@
$trapdoorsJson = @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeycomb_trapdoor"
  ]
}
"@

Write-JsonFile "$mcTagsBlock\stairs.json" $stairsJson
Write-JsonFile "$mcTagsBlock\slabs.json" $slabsJson
Write-JsonFile "$mcTagsBlock\walls.json" $wallsJson
Write-JsonFile "$mcTagsBlock\doors.json" $doorsJson
Write-JsonFile "$mcTagsBlock\trapdoors.json" $trapdoorsJson
Write-JsonFile "$mcTagsBlock\impermeable.json" @"
{
  "replace": false,
  "values": [
    "honeycombplus:honeyed_glass"
  ]
}
"@

Write-JsonFile "$mcTagsItem\stairs.json" $stairsJson
Write-JsonFile "$mcTagsItem\slabs.json" $slabsJson
Write-JsonFile "$mcTagsItem\walls.json" $wallsJson
Write-JsonFile "$mcTagsItem\doors.json" $doorsJson
Write-JsonFile "$mcTagsItem\trapdoors.json" $trapdoorsJson

Write-Host "Successfully generated HoneycombPlus resources! (Textures written: $script:writtenTextures, Existing textures preserved: $script:skippedTextures)"
