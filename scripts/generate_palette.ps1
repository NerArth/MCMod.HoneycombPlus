<#
.SYNOPSIS
    Palette extraction, auditing, mathematical ramp generation, and editor export tool for HoneycombPlus.
.DESCRIPTION
    Supports four modes (or -Mode All to run active export, vanilla reference extraction, and mod texture audit):
      1. -Mode AuditMod        : Scans all PNGs in src/main/resources/assets/honeycombplus/textures/ (or -InputPath),
                                 identifies all colors (including custom hand-edited colors vs. palette.json roles),
                                 and exports PNG swatches, .gpl, .hex, Paint.NET .txt, .json, and a Markdown audit report.
      2. -Mode ExtractVanilla  : Reads vanilla honeycomb_block, honey_block, copper_bulb, and lantern textures directly
                                 from the local Gradle Loom Minecraft 26.3 cache and exports their palettes + report.
      3. -Mode GenerateRamp    : Mathematically generates a hue-shifted pixel-art color ramp from -BaseHex (default #E89624)
                                 and optionally updates palettes/palette.json when -UpdateSharedPalette is specified.
      4. -Mode ExportActive    : Exports palettes/palette.json into PNG swatches and editor formats (.gpl, .hex, Paint.NET .txt).

.EXAMPLE
    .\scripts\generate_palette.ps1
    Runs ExportActive, ExtractVanilla, and AuditMod, populating the palettes/ folder.

.EXAMPLE
    .\scripts\generate_palette.ps1 -Mode AuditMod
    Re-audits the mod's textures after you hand-edit PNGs and updates palettes/mod_audit/.

.EXAMPLE
    .\scripts\generate_palette.ps1 -Mode GenerateRamp -BaseHex "#E89624" -ShadowHueShift -12 -HighlightHueShift 14 -UpdateSharedPalette
    Generates a new mathematical wax ramp and writes it to palettes/palette.json.
#>
param(
    [ValidateSet("All", "AuditMod", "ExtractVanilla", "GenerateRamp", "ExportActive")]
    [string]$Mode = "All",

    [string]$InputPath = "",

    [string]$BaseHex = "#E89624",
    [double]$ShadowHueShift = -14.0,
    [double]$HighlightHueShift = 12.0,
    [switch]$UpdateSharedPalette
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Web.Extensions

$projectRoot = Split-Path -Parent $PSScriptRoot
$palettesRoot = "$projectRoot\palettes"
$sharedPalettePath = "$palettesRoot\palette.json"
$modTexturesRoot = "$projectRoot\src\main\resources\assets\honeycombplus\textures"

New-Item -ItemType Directory -Force -Path $palettesRoot | Out-Null

function Write-Utf8File($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# ==============================================================================
# COLOR CONVERSION HELPERS (RGBA <-> HEX <-> HSL)
# ==============================================================================
function ConvertTo-HexRgb([System.Drawing.Color]$c) {
    return ("#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B)
}

function ConvertTo-HexArgb([System.Drawing.Color]$c) {
    return ("{0:X2}{1:X2}{2:X2}{3:X2}" -f $c.A, $c.R, $c.G, $c.B)
}

function ConvertFrom-HexColor([string]$hex, [int]$defaultAlpha = 255) {
    $clean = $hex.Trim().TrimStart('#')
    if ($clean.Length -eq 6) {
        $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)
        return [System.Drawing.Color]::FromArgb($defaultAlpha, $r, $g, $b)
    } elseif ($clean.Length -eq 8) {
        $a = [Convert]::ToInt32($clean.Substring(0, 2), 16)
        $r = [Convert]::ToInt32($clean.Substring(2, 2), 16)
        $g = [Convert]::ToInt32($clean.Substring(4, 2), 16)
        $b = [Convert]::ToInt32($clean.Substring(6, 2), 16)
        return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
    }
    throw "Invalid hex color: $hex"
}

function ConvertTo-Hsl([System.Drawing.Color]$c) {
    $r = $c.R / 255.0
    $g = $c.G / 255.0
    $b = $c.B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2.0

    if ($max -eq $min) {
        $h = 0.0
        $s = 0.0
    } else {
        $d = $max - $min
        $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        if ($max -eq $r) {
            $h = ($g - $b) / $d + $(if ($g -lt $b) { 6.0 } else { 0.0 })
        } elseif ($max -eq $g) {
            $h = ($b - $r) / $d + 2.0
        } else {
            $h = ($r - $g) / $d + 4.0
        }
        $h /= 6.0
    }
    return [PSCustomObject]@{
        H = [Math]::Round($h * 360.0, 1)
        S = [Math]::Round($s * 100.0, 1)
        L = [Math]::Round($l * 100.0, 1)
    }
}

function ConvertFrom-Hsl([double]$hDeg, [double]$sPct, [double]$lPct, [int]$alpha = 255) {
    $h = (($hDeg % 360.0) + 360.0) % 360.0 / 360.0
    $s = [Math]::Max(0.0, [Math]::Min(100.0, $sPct)) / 100.0
    $l = [Math]::Max(0.0, [Math]::Min(100.0, $lPct)) / 100.0

    if ($s -eq 0.0) {
        $r = $g = $b = $l
    } else {
        $q = if ($l -lt 0.5) { $l * (1.0 + $s) } else { $l + $s - $l * $s }
        $p = 2.0 * $l - $q
        $hue2rgb = {
            param($pVal, $qVal, $tVal)
            if ($tVal -lt 0.0) { $tVal += 1.0 }
            if ($tVal -gt 1.0) { $tVal -= 1.0 }
            if ($tVal -lt (1.0 / 6.0)) { return $pVal + ($qVal - $pVal) * 6.0 * $tVal }
            if ($tVal -lt 0.5)         { return $qVal }
            if ($tVal -lt (2.0 / 3.0)) { return $pVal + ($qVal - $pVal) * (2.0 / 3.0 - $tVal) * 6.0 }
            return $pVal
        }
        $r = & $hue2rgb $p $q ($h + 1.0 / 3.0)
        $g = & $hue2rgb $p $q $h
        $b = & $hue2rgb $p $q ($h - 1.0 / 3.0)
    }
    return [System.Drawing.Color]::FromArgb(
        $alpha,
        [int][Math]::Round($r * 255.0),
        [int][Math]::Round($g * 255.0),
        [int][Math]::Round($b * 255.0)
    )
}

# ==============================================================================
# ENSURE DEFAULT palettes/palette.json EXISTS
# ==============================================================================
function Initialize-DefaultSharedPalette {
    if (Test-Path $sharedPalettePath) { return }
    $defaultPaletteJson = @"
{
  "name": "HoneycombPlus Active Palette",
  "description": "Shared semantic palette read by scripts/generate_assets.ps1 and exported by scripts/generate_palette.ps1.",
  "colors": {
    "Darkest":          { "hex": "#9E4E0C", "alpha": 255, "role": "Deep amber border, mortar lines, and recessed shadow" },
    "Dark":             { "hex": "#C16711", "alpha": 255, "role": "Rich amber secondary shadow and bevel edge" },
    "MidDark":          { "hex": "#D87F19", "alpha": 255, "role": "Warm honey-orange lower midtone for wax grain" },
    "Mid":              { "hex": "#E89624", "alpha": 255, "role": "Base honeycomb gold primary surface fill" },
    "MidLight":         { "hex": "#F5B238", "alpha": 255, "role": "Bright honey gold upper midtone and inner bevel" },
    "Light":            { "hex": "#FCCC58", "alpha": 255, "role": "Top/left lit wax bevel highlight" },
    "Bright":           { "hex": "#FFE58A", "alpha": 255, "role": "Specular wax highlight and outer lamp/lantern glow" },
    "GlowCore":         { "hex": "#FFF8C4", "alpha": 255, "role": "Incandescent light core for lantern and lit lamp" },
    "IronDark":         { "hex": "#3E3630", "alpha": 255, "role": "Warm dark bronze-iron housing for lantern and lamp frame" },
    "IronMid":          { "hex": "#5C4F44", "alpha": 255, "role": "Warm mid bronze-iron for lantern cap and chain" },
    "IronLight":        { "hex": "#7C6C5C", "alpha": 255, "role": "Warm bronze-iron metallic highlight" },
    "Redstone":         { "hex": "#DC2D19", "alpha": 255, "role": "Powered redstone indicator on Honeycomb Lamp" },
    "GlassBorderLight": { "hex": "#F5B238", "alpha": 225, "role": "Honeyed Glass top/left translucent border (alpha 225)" },
    "GlassBorderDark":  { "hex": "#C16711", "alpha": 225, "role": "Honeyed Glass bottom/right translucent border (alpha 225)" },
    "GlassStreak":      { "hex": "#FFE58A", "alpha": 150, "role": "Honeyed Glass diagonal specular streak (alpha 150)" },
    "GlassGridDot":     { "hex": "#E89624", "alpha": 125, "role": "Honeyed Glass subtle cell dot (alpha 125)" },
    "GlassFill":        { "hex": "#F5AA2D", "alpha": 85,  "role": "Honeyed Glass interior translucent fill (alpha 85)" },
    "GlassPaneEdge":    { "hex": "#E89624", "alpha": 200, "role": "Honeyed Glass Pane top/bottom rim (alpha 200)" }
  }
}
"@
    Write-Utf8File $sharedPalettePath $defaultPaletteJson
    Write-Host "Initialized default shared palette at $sharedPalettePath"
}

# ==============================================================================
# EXPORT HELPERS (.png 1xN, .png Swatch Grid, .gpl, .hex, Paint.NET .txt)
# ==============================================================================
function Export-PaletteBundle {
    param(
        [string]$OutDir,
        [string]$BaseName,
        [string]$PaletteTitle,
        [array]$ColorEntries # Array of PSCustomObjects with: Color ([System.Drawing.Color]), Name ([string])
    )
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $count = $ColorEntries.Count
    if ($count -eq 0) { return }

    # 1. 1xN pixel strip PNG (ideal for importing directly into Aseprite / Blockbench / GIMP)
    $stripBmp = New-Object System.Drawing.Bitmap($count, 1, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($i = 0; $i -lt $count; $i++) {
        $stripBmp.SetPixel($i, 0, $ColorEntries[$i].Color)
    }
    $stripPath = "$OutDir\${BaseName}_1xN.png"
    $stripBmp.Save($stripPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $stripBmp.Dispose()

    # 2. Swatch sheet PNG (32x32 per color, max 8 columns, with checkerboard background for alpha < 255)
    $cols = [Math]::Min(8, $count)
    $rows = [int][Math]::Ceiling($count / [double]$cols)
    $cellSize = 32
    $sheetBmp = New-Object System.Drawing.Bitmap(($cols * $cellSize), ($rows * $cellSize), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($sheetBmp)
    $bgLight = [System.Drawing.Color]::FromArgb(255, 220, 220, 220)
    $bgDark  = [System.Drawing.Color]::FromArgb(255, 170, 170, 170)

    for ($idx = 0; $idx -lt $count; $idx++) {
        $c = $ColorEntries[$idx].Color
        $colIdx = $idx % $cols
        $rowIdx = [int][Math]::Floor($idx / $cols)
        $ox = $colIdx * $cellSize
        $oy = $rowIdx * $cellSize

        # Draw 8x8 checkerboard underneath translucent swatches
        for ($py = 0; $py -lt $cellSize; $py++) {
            for ($px = 0; $px -lt $cellSize; $px++) {
                $isBorder = ($px -eq 0 -or $py -eq 0 -or $px -eq ($cellSize - 1) -or $py -eq ($cellSize - 1))
                if ($isBorder) {
                    $sheetBmp.SetPixel($ox + $px, $oy + $py, [System.Drawing.Color]::FromArgb(255, 32, 32, 32))
                } else {
                    $chk = if (([int][Math]::Floor($px / 8) + [int][Math]::Floor($py / 8)) % 2 -eq 0) { $bgLight } else { $bgDark }
                    $a = $c.A / 255.0
                    $blendedR = [int][Math]::Round($c.R * $a + $chk.R * (1.0 - $a))
                    $blendedG = [int][Math]::Round($c.G * $a + $chk.G * (1.0 - $a))
                    $blendedB = [int][Math]::Round($c.B * $a + $chk.B * (1.0 - $a))
                    $sheetBmp.SetPixel($ox + $px, $oy + $py, [System.Drawing.Color]::FromArgb(255, $blendedR, $blendedG, $blendedB))
                }
            }
        }
    }
    $g.Dispose()
    $sheetPath = "$OutDir\${BaseName}_swatches.png"
    $sheetBmp.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $sheetBmp.Dispose()

    # 3. GIMP / Aseprite / LibreSprite (.gpl)
    $gplLines = New-Object System.Collections.Generic.List[string]
    $gplLines.Add("GIMP Palette")
    $gplLines.Add("Name: $PaletteTitle")
    $gplLines.Add("Columns: $cols")
    $gplLines.Add("# Generated by HoneycombPlus scripts/generate_palette.ps1")
    foreach ($entry in $ColorEntries) {
        $c = $entry.Color
        $gplLines.Add(("{0,3} {1,3} {2,3}`t{3}" -f $c.R, $c.G, $c.B, $entry.Name))
    }
    Write-Utf8File "$OutDir\${BaseName}.gpl" ($gplLines -join "`n")

    # 4. Raw Hex List (.hex) for Blockbench / Lospec / Pyxel Edit (deduplicated RGB hexes)
    $hexLines = New-Object System.Collections.Generic.List[string]
    $seenHex = @{}
    foreach ($entry in $ColorEntries) {
        $h = (ConvertTo-HexRgb $entry.Color).TrimStart('#')
        if (-not $seenHex.ContainsKey($h)) {
            $seenHex[$h] = $true
            $hexLines.Add($h)
        }
    }
    Write-Utf8File "$OutDir\${BaseName}.hex" ($hexLines -join "`n")

    # 5. Paint.NET Palette (.txt) with full AARRGGBB support
    $pdnLines = New-Object System.Collections.Generic.List[string]
    $pdnLines.Add("; paint.net Palette File")
    $pdnLines.Add("; Palette Name: $PaletteTitle")
    $pdnLines.Add("; Colors: $count")
    foreach ($entry in $ColorEntries) {
        $pdnLines.Add((ConvertTo-HexArgb $entry.Color))
    }
    Write-Utf8File "$OutDir\${BaseName}_paintnet.txt" ($pdnLines -join "`n")
}

# ==============================================================================
# MODE 1: EXPORT ACTIVE SHARED PALETTE (palettes/palette.json)
# ==============================================================================
function Invoke-ExportActivePalette {
    Initialize-DefaultSharedPalette
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $raw = [System.IO.File]::ReadAllText($sharedPalettePath)
    $data = $serializer.DeserializeObject($raw)
    $colorsDict = $data["colors"]

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($key in $colorsDict.Keys) {
        $item = $colorsDict[$key]
        $alpha = if ($item.ContainsKey("alpha")) { [int]$item["alpha"] } else { 255 }
        $col = ConvertFrom-HexColor $item["hex"] $alpha
        $entries.Add([PSCustomObject]@{
            Name  = "$key ($($item['hex']), A=$alpha)"
            Key   = $key
            Color = $col
            Role  = $item["role"]
        })
    }

    Export-PaletteBundle -OutDir $palettesRoot -BaseName "active_palette" -PaletteTitle "HoneycombPlus Active" -ColorEntries $entries
    Write-Host "[ExportActive] Exported $($entries.Count) colors from palettes/palette.json -> palettes/active_palette.*"
}

# ==============================================================================
# MODE 2: AUDIT EXISTING MOD TEXTURES (palettes/mod_audit/)
# ==============================================================================
function Invoke-AuditModTextures([string]$scanDir) {
    Initialize-DefaultSharedPalette
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $sharedData = $serializer.DeserializeObject([System.IO.File]::ReadAllText($sharedPalettePath))["colors"]

    # Map known (A,R,G,B) and (R,G,B) to shared role names
    $knownArgbRoles = @{}
    $knownRgbRoles  = @{}
    foreach ($k in $sharedData.Keys) {
        $item = $sharedData[$k]
        $a = if ($item.ContainsKey("alpha")) { [int]$item["alpha"] } else { 255 }
        $c = ConvertFrom-HexColor $item["hex"] $a
        $argbKey = ConvertTo-HexArgb $c
        $rgbKey  = ConvertTo-HexRgb $c
        if (-not $knownArgbRoles.ContainsKey($argbKey)) { $knownArgbRoles[$argbKey] = $k }
        if (-not $knownRgbRoles.ContainsKey($rgbKey))   { $knownRgbRoles[$rgbKey] = $k }
    }

    $targetDir = if ($scanDir) { $scanDir } else { $modTexturesRoot }
    $pngFiles = Get-ChildItem -Path $targetDir -Recurse -Filter "*.png" | Sort-Object FullName

    $colorStats = @{} # key: AARRGGBB -> PSCustomObject
    $perFileColors = [ordered]@{}

    foreach ($file in $pngFiles) {
        $relName = $file.FullName.Substring($targetDir.Length).TrimStart('\', '/').Replace('\', '/')
        $bmp = New-Object System.Drawing.Bitmap($file.FullName)
        $fileColorMap = @{}

        for ($y = 0; $y -lt $bmp.Height; $y++) {
            for ($x = 0; $x -lt $bmp.Width; $x++) {
                $px = $bmp.GetPixel($x, $y)
                if ($px.A -eq 0) { continue } # Ignore fully transparent pixels
                $argb = ConvertTo-HexArgb $px
                if (-not $fileColorMap.ContainsKey($argb)) {
                    $fileColorMap[$argb] = 0
                }
                $fileColorMap[$argb]++

                if (-not $colorStats.ContainsKey($argb)) {
                    $hexRgb = ConvertTo-HexRgb $px
                    $hsl = ConvertTo-Hsl $px
                    $role = if ($knownArgbRoles.ContainsKey($argb)) {
                        "Shared Role: `$($knownArgbRoles[$argb])"
                    } elseif ($knownRgbRoles.ContainsKey($hexRgb)) {
                        "Shared RGB (`$($knownRgbRoles[$hexRgb])) with custom alpha $($px.A)"
                    } else {
                        "Custom / Hand-Edited Color"
                    }
                    $colorStats[$argb] = [PSCustomObject]@{
                        Argb       = $argb
                        Hex        = $hexRgb
                        Alpha      = [int]$px.A
                        Color      = $px
                        Hsl        = $hsl
                        Role       = $role
                        PixelCount = 0
                        Files      = New-Object System.Collections.Generic.List[string]
                    }
                }
                $colorStats[$argb].PixelCount++
                if (-not $colorStats[$argb].Files.Contains($relName)) {
                    $colorStats[$argb].Files.Add($relName)
                }
            }
        }
        $bmp.Dispose()
        $perFileColors[$relName] = $fileColorMap
    }

    # Sort colors by Hue, then Lightness, then Alpha descending
    $sortedColors = $colorStats.Values | Sort-Object { $_.Alpha -lt 255 }, { $_.Hsl.H }, { $_.Hsl.L }

    $outDir = "$palettesRoot\mod_audit"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $bundleEntries = foreach ($sc in $sortedColors) {
        [PSCustomObject]@{
            Name  = "$($sc.Hex) (A=$($sc.Alpha)) - $($sc.Role)"
            Color = $sc.Color
        }
    }
    Export-PaletteBundle -OutDir $outDir -BaseName "mod_palette" -PaletteTitle "HoneycombPlus Audited Mod Palette" -ColorEntries $bundleEntries

    # Generate Markdown Audit Report
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# HoneycombPlus - Texture Palette Audit Report")
    $md.Add("")
    $md.Add("- **Scanned Directory:** ``$targetDir``")
    $md.Add("- **Textures Scanned:** $($pngFiles.Count)")
    $md.Add("- **Unique Non-Transparent Colors (ARGB):** $($sortedColors.Count)")
    $md.Add("")
    $md.Add("## 1. All Colors Used Across Mod Textures")
    $md.Add("")
    $md.Add("| Hex (RGB) | Alpha | ARGB | RGB | HSL | Total Pixels | Source / Role | Used In |")
    $md.Add("| :--- | :---: | :--- | :--- | :--- | :---: | :--- | :--- |")
    foreach ($sc in $sortedColors) {
        $c = $sc.Color
        $hslStr = "$($sc.Hsl.H) deg, $($sc.Hsl.S)%, $($sc.Hsl.L)%"
        $filesStr = ($sc.Files | ForEach-Object { "``$_``" }) -join ", "
        $md.Add("| ``$($sc.Hex)`` | $($sc.Alpha) | ``#$($sc.Argb)`` | ``($($c.R), $($c.G), $($c.B))`` | $hslStr | $($sc.PixelCount) | $($sc.Role) | $filesStr |")
    }
    $md.Add("")
    $md.Add("## 2. Per-Texture Color Breakdown")
    $md.Add("")
    foreach ($relName in $perFileColors.Keys) {
        $fMap = $perFileColors[$relName]
        $md.Add("### ``$relName`` ($($fMap.Count) unique colors)")
        $md.Add("")
        $md.Add("| Hex | Alpha | Pixels | Role |")
        $md.Add("| :--- | :---: | :---: | :--- |")
        foreach ($argb in ($fMap.Keys | Sort-Object)) {
            $stat = $colorStats[$argb]
            $md.Add("| ``$($stat.Hex)`` | $($stat.Alpha) | $($fMap[$argb]) | $($stat.Role) |")
        }
        $md.Add("")
    }

    Write-Utf8File "$outDir\mod_palette_audit.md" ($md -join "`n")
    Write-Host "[AuditMod] Audited $($pngFiles.Count) textures ($($sortedColors.Count) unique ARGB colors) -> palettes/mod_audit/mod_palette_audit.md"
}

# ==============================================================================
# MODE 3: EXTRACT VANILLA REFERENCE PALETTES FROM CACHED MINECRAFT 26.3 JAR
# ==============================================================================
function Invoke-ExtractVanillaReference {
    $clientJar = Get-ChildItem -Path "$env:USERPROFILE\.gradle\caches\fabric-loom" -Recurse -Filter "*clientonly*26.3*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $clientJar) {
        Write-Warning "[ExtractVanilla] Could not find cached minecraft-clientonly-deobf-26.3.jar in ~/.gradle/caches/fabric-loom."
        return
    }

    $vanillaTargets = @(
        "assets/minecraft/textures/block/honeycomb_block.png",
        "assets/minecraft/textures/block/honey_block_top.png",
        "assets/minecraft/textures/block/honey_block_side.png",
        "assets/minecraft/textures/block/honey_block_bottom.png",
        "assets/minecraft/textures/block/copper_bulb.png",
        "assets/minecraft/textures/block/copper_bulb_lit.png",
        "assets/minecraft/textures/block/lantern.png"
    )

    $outDir = "$palettesRoot\vanilla_reference"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $zip = [System.IO.Compression.ZipFile]::OpenRead($clientJar.FullName)
    $allVanillaColors = @{}
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# Vanilla Minecraft 26.3 - Reference Texture Palettes")
    $md.Add("")
    $md.Add("Extracted directly from ``$($clientJar.Name)`` for side-by-side comparison and eyedropper sampling.")
    $md.Add("")

    try {
        foreach ($entryPath in $vanillaTargets) {
            $entry = $zip.GetEntry($entryPath)
            if (-not $entry) { continue }
            $shortName = [System.IO.Path]::GetFileNameWithoutExtension($entryPath)
            $stream = $entry.Open()
            $bmp = New-Object System.Drawing.Bitmap($stream)

            $texColors = @{}
            for ($y = 0; $y -lt $bmp.Height; $y++) {
                for ($x = 0; $x -lt $bmp.Width; $x++) {
                    $px = $bmp.GetPixel($x, $y)
                    if ($px.A -eq 0) { continue }
                    $argb = ConvertTo-HexArgb $px
                    if (-not $texColors.ContainsKey($argb)) {
                        $texColors[$argb] = [PSCustomObject]@{
                            Argb  = $argb
                            Hex   = ConvertTo-HexRgb $px
                            Alpha = [int]$px.A
                            Color = $px
                            Hsl   = ConvertTo-Hsl $px
                            Count = 0
                        }
                    }
                    $texColors[$argb].Count++

                    if (-not $allVanillaColors.ContainsKey($argb)) {
                        $allVanillaColors[$argb] = [PSCustomObject]@{
                            Name  = "$shortName $(ConvertTo-HexRgb $px)"
                            Color = $px
                            Hsl   = ConvertTo-Hsl $px
                        }
                    }
                }
            }
            $bmp.Dispose()
            $stream.Close()

            $sortedTex = $texColors.Values | Sort-Object { $_.Hsl.L }
            $md.Add("## ``$entryPath`` ($($sortedTex.Count) colors)")
            $md.Add("")
            $md.Add("| Hex (RGB) | Alpha | RGB | HSL | Pixel Count |")
            $md.Add("| :--- | :---: | :--- | :--- | :---: |")
            foreach ($tc in $sortedTex) {
                $c = $tc.Color
                $md.Add("| ``$($tc.Hex)`` | $($tc.Alpha) | ``($($c.R), $($c.G), $($c.B))`` | $($tc.Hsl.H) deg, $($tc.Hsl.S)%, $($tc.Hsl.L)% | $($tc.Count) |")
            }
            $md.Add("")
        }
    } finally {
        $zip.Dispose()
    }

    $sortedAll = $allVanillaColors.Values | Sort-Object { $_.Hsl.H }, { $_.Hsl.L }
    Export-PaletteBundle -OutDir $outDir -BaseName "vanilla_reference" -PaletteTitle "Vanilla 26.3 Honeycomb & Lighting Reference" -ColorEntries $sortedAll
    Write-Utf8File "$outDir\vanilla_reference.md" ($md -join "`n")
    Write-Host "[ExtractVanilla] Extracted $($sortedAll.Count) unique vanilla reference colors -> palettes/vanilla_reference/"
}

# ==============================================================================
# MODE 4: MATHEMATICAL HUE-SHIFTED RAMP GENERATOR
# ==============================================================================
function Invoke-GenerateMathematicalRamp {
    $seedColor = ConvertFrom-HexColor $BaseHex 255
    $seedHsl = ConvertTo-Hsl $seedColor

    # 8-step wax ramp from Darkest (-30% L, +ShadowHueShift) to GlowCore (+38% L, +HighlightHueShift)
    $rampSpec = @(
        @{ Key = "Darkest";  LDelta = -26.0; SDelta = -4.0;  HFactor =  1.00; Role = "Deep amber border, mortar lines, and recessed shadow" },
        @{ Key = "Dark";     LDelta = -14.0; SDelta =  0.0;  HFactor =  0.65; Role = "Rich amber secondary shadow and bevel edge" },
        @{ Key = "MidDark";  LDelta =  -6.0; SDelta =  2.0;  HFactor =  0.35; Role = "Warm honey-orange lower midtone for wax grain" },
        @{ Key = "Mid";      LDelta =   0.0; SDelta =  0.0;  HFactor =  0.00; Role = "Base honeycomb gold primary surface fill" },
        @{ Key = "MidLight"; LDelta =  +7.0; SDelta = +6.0;  HFactor = -0.35; Role = "Bright honey gold upper midtone and inner bevel" },
        @{ Key = "Light";    LDelta = +15.0; SDelta = +12.0; HFactor = -0.70; Role = "Top/left lit wax bevel highlight" },
        @{ Key = "Bright";   LDelta = +25.0; SDelta = +16.0; HFactor = -1.00; Role = "Specular wax highlight and outer lamp/lantern glow" },
        @{ Key = "GlowCore"; LDelta = +36.0; SDelta = +18.0; HFactor = -1.30; Role = "Incandescent light core for lantern and lit lamp" }
    )

    $generatedEntries = New-Object System.Collections.Generic.List[object]
    $rampMap = [ordered]@{}

    foreach ($step in $rampSpec) {
        $hueOffset = if ($step.HFactor -ge 0) { $step.HFactor * $ShadowHueShift } else { (-$step.HFactor) * $HighlightHueShift }
        $newH = $seedHsl.H + $hueOffset
        $newS = [Math]::Max(10.0, [Math]::Min(100.0, $seedHsl.S + $step.SDelta))
        $newL = [Math]::Max(8.0,  [Math]::Min(95.0,  $seedHsl.L + $step.LDelta))
        $col = ConvertFrom-Hsl $newH $newS $newL 255
        $hex = ConvertTo-HexRgb $col

        $rampMap[$step.Key] = @{
            hex   = $hex
            alpha = 255
            role  = $step.Role
        }
        $generatedEntries.Add([PSCustomObject]@{
            Name  = "$($step.Key) ($hex)"
            Color = $col
        })
    }

    $outDir = "$palettesRoot\generated_ramp"
    Export-PaletteBundle -OutDir $outDir -BaseName "generated_ramp" -PaletteTitle "HoneycombPlus Generated Ramp ($BaseHex)" -ColorEntries $generatedEntries
    Write-Host "[GenerateRamp] Generated 8-step hue-shifted ramp from $BaseHex -> palettes/generated_ramp/"

    if ($UpdateSharedPalette) {
        Initialize-DefaultSharedPalette
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $sharedObj = $serializer.DeserializeObject([System.IO.File]::ReadAllText($sharedPalettePath))
        foreach ($k in $rampMap.Keys) {
            $sharedObj["colors"][$k]["hex"] = $rampMap[$k].hex
        }
        # Also sync glass derived colors with the new ramp
        $sharedObj["colors"]["GlassBorderLight"]["hex"] = $rampMap["MidLight"].hex
        $sharedObj["colors"]["GlassBorderDark"]["hex"]  = $rampMap["Dark"].hex
        $sharedObj["colors"]["GlassStreak"]["hex"]      = $rampMap["Bright"].hex
        $sharedObj["colors"]["GlassGridDot"]["hex"]     = $rampMap["Mid"].hex
        $sharedObj["colors"]["GlassFill"]["hex"]        = $rampMap["MidLight"].hex
        $sharedObj["colors"]["GlassPaneEdge"]["hex"]    = $rampMap["Mid"].hex

        # Format clean JSON back to palettes/palette.json
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("{")
        $lines.Add("  `"name`": `"$($sharedObj['name'])`",")
        $lines.Add("  `"description`": `"$($sharedObj['description'])`",")
        $lines.Add("  `"colors`": {")
        $keys = @($sharedObj["colors"].Keys)
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k = $keys[$i]
            $item = $sharedObj["colors"][$k]
            $comma = if ($i -lt ($keys.Count - 1)) { "," } else { "" }
            $padKey = ("`"$k`":").PadRight(20)
            $padAlpha = ("$($item['alpha']),").PadRight(4)
            $lines.Add("    $padKey { `"hex`": `"$($item['hex'])`", `"alpha`": $padAlpha `"role`": `"$($item['role'])`" }$comma")
        }
        $lines.Add("  }")
        $lines.Add("}")
        Write-Utf8File $sharedPalettePath ($lines -join "`n")
        Write-Host "[GenerateRamp] Updated shared palette at $sharedPalettePath"
        Invoke-ExportActivePalette
    }
}

# ==============================================================================
# DISPATCH REQUESTED MODE
# ==============================================================================
switch ($Mode) {
    "ExportActive"   { Invoke-ExportActivePalette }
    "AuditMod"       { Invoke-AuditModTextures $InputPath }
    "ExtractVanilla" { Invoke-ExtractVanillaReference }
    "GenerateRamp"   { Invoke-GenerateMathematicalRamp }
    "All" {
        Invoke-ExportActivePalette
        Invoke-ExtractVanillaReference
        Invoke-AuditModTextures $InputPath
    }
}
