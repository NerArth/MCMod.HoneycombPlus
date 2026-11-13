<#
.SYNOPSIS
    Validates all JSON resources, blockstates, item definitions, models, textures, loot tables, and translations.
.DESCRIPTION
    Run from anywhere: .\scripts\validate_assets.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer

$projectRoot = Split-Path -Parent $PSScriptRoot
$resRoot = "$projectRoot\src\main\resources"
$assetsRoot = "$resRoot\assets\honeycombplus"
$dataRoot = "$resRoot\data\honeycombplus"

$allBlocks = @(
    "honeycomb_stairs", "honeycomb_slab", "honeycomb_wall",
    "polished_honeycomb", "polished_honeycomb_stairs", "polished_honeycomb_slab", "polished_honeycomb_wall",
    "cut_honeycomb", "cut_honeycomb_stairs", "cut_honeycomb_slab", "cut_honeycomb_wall",
    "honeycomb_bricks", "honeycomb_brick_stairs", "honeycomb_brick_slab", "honeycomb_brick_wall",
    "chiseled_honeycomb", "honeycomb_pillar",
    "honeycomb_grate", "honeycomb_bars",
    "honeycomb_door", "honeycomb_trapdoor",
    "honeyed_glass", "honeyed_glass_pane",
    "honeycomb_lantern", "honeycomb_lamp"
)

# 1. Parse all JSON files in src/main/resources
$jsonFiles = Get-ChildItem -Path $resRoot -Recurse -Filter "*.json"
foreach ($f in $jsonFiles) {
    try {
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        $null = $serializer.DeserializeObject($raw)
    } catch {
        Write-Error "Invalid JSON in $($f.FullName): $_"
    }
}
Write-Host "Validated $($jsonFiles.Count) JSON files with zero syntax errors."

# 2. Check every block has blockstate, item definition, loot table, and lang entry
$lang = $serializer.DeserializeObject([System.IO.File]::ReadAllText("$assetsRoot\lang\en_us.json"))
foreach ($b in $allBlocks) {
    if (-not (Test-Path "$assetsRoot\blockstates\$b.json")) { Write-Error "Missing blockstate for $b" }
    if (-not (Test-Path "$assetsRoot\items\$b.json")) { Write-Error "Missing item definition for $b" }
    if (-not (Test-Path "$dataRoot\loot_table\blocks\$b.json")) { Write-Error "Missing loot table for $b" }
    $langKey = "block.honeycombplus.$b"
    if (-not $lang.ContainsKey($langKey)) { Write-Error "Missing lang key $langKey" }
}
if (-not (Test-Path "$assetsRoot\items\wax.json")) { Write-Error "Missing item definition for wax" }
if (-not $lang.ContainsKey("item.honeycombplus.wax")) { Write-Error "Missing lang key item.honeycombplus.wax" }
Write-Host "All $($allBlocks.Count) blocks and Fine Wax item verified for blockstates, items, loot tables, and translations."

# 3. Verify all model references in blockstates/ and items/ exist
foreach ($f in (Get-ChildItem "$assetsRoot\blockstates\*.json", "$assetsRoot\items\*.json")) {
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $matches = [regex]::Matches($raw, '"honeycombplus:(block|item)/([^"]+)"')
    foreach ($m in $matches) {
        $kind = $m.Groups[1].Value
        $name = $m.Groups[2].Value
        $modelFile = "$assetsRoot\models\$kind\$name.json"
        if (-not (Test-Path $modelFile)) {
            Write-Error "Missing model $modelFile referenced in $($f.Name)"
        }
    }
}
Write-Host "All model references in blockstates and item definitions verified."

# 4. Verify all texture references in models/ exist
foreach ($f in (Get-ChildItem "$assetsRoot\models" -Recurse -Filter "*.json")) {
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $matches = [regex]::Matches($raw, '"honeycombplus:(block|item)/([^"]+)"')
    foreach ($m in $matches) {
        $kind = $m.Groups[1].Value
        $name = $m.Groups[2].Value
        $texFile = "$assetsRoot\textures\$kind\$name.png"
        if (-not (Test-Path $texFile)) {
            Write-Error "Missing texture $texFile referenced in $($f.Name)"
        }
    }
}
Write-Host "All texture references in models verified."
