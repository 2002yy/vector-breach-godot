$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) { throw 'Not inside a Git repository.' }
Set-Location $repoRoot

$branch = (git branch --show-current).Trim()
if ($branch -ne 'pipeline/asset-layers') {
    throw "Run this migration only on pipeline/asset-layers (current: $branch)."
}

& git lfs install
if ($LASTEXITCODE -ne 0) { throw 'git lfs install failed.' }

$moves = [ordered]@{
    'tools/blender/source/core_vault_asset_source.blend' = 'assets-source/blender/maps/core_vault_asset_source.blend'
    'tools/blender/source/foundry_asset_source.blend' = 'assets-source/blender/maps/foundry_asset_source.blend'
    'tools/blender/source/foundry_reforged_source.blend' = 'assets-source/blender/maps/foundry_reforged_source.blend'
    'tools/blender/source/gatehouse_asset_source.blend' = 'assets-source/blender/maps/gatehouse_asset_source.blend'
    'tools/blender/source/tactical_actor_lowpoly_source.blend' = 'assets-source/blender/characters/tactical_actor_lowpoly_source.blend'
    'tools/blender/source/weapon_asset_source.blend' = 'assets-source/blender/weapons/weapon_asset_source.blend'
}

foreach ($entry in $moves.GetEnumerator()) {
    $source = $entry.Key
    $destination = $entry.Value
    $destinationDir = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null

    if ((Test-Path $source) -and -not (Test-Path $destination)) {
        & git mv -- $source $destination
        if ($LASTEXITCODE -ne 0) { throw "git mv failed: $source -> $destination" }
    }
    elseif (-not (Test-Path $destination)) {
        throw "Missing both source and destination for $source"
    }
}

# Local-only Dustline source is ignored by Git but must obey the same source root.
$dustlineOld = 'tools/blender/source/dustline_depths_source.blend'
$dustlineNew = 'assets-source/blender/maps/dustline_depths_source.blend'
if ((Test-Path $dustlineOld) -and -not (Test-Path $dustlineNew)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dustlineNew) | Out-Null
    Move-Item -Path $dustlineOld -Destination $dustlineNew
}

function Replace-Exact([string]$Path, [string]$Old, [string]$New) {
    $fullPath = Join-Path $repoRoot $Path
    $text = [IO.File]::ReadAllText($fullPath)
    if (-not $text.Contains($Old)) {
        if ($text.Contains($New)) { return }
        throw "Expected source text not found in $Path`n$Old"
    }
    $text = $text.Replace($Old, $New)
    [IO.File]::WriteAllText($fullPath, $text, [Text.UTF8Encoding]::new($false))
}

Replace-Exact 'tools/blender/build_core_vault_assets.py' `
    'PROJECT_ROOT / "tools" / "blender" / "source" / "core_vault_asset_source.blend"' `
    'PROJECT_ROOT / "assets-source" / "blender" / "maps" / "core_vault_asset_source.blend"'
Replace-Exact 'tools/blender/build_foundry_assets.py' `
    'PROJECT_ROOT / "tools" / "blender" / "source" / "foundry_asset_source.blend"' `
    'PROJECT_ROOT / "assets-source" / "blender" / "maps" / "foundry_asset_source.blend"'
Replace-Exact 'tools/blender/build_foundry_reforged_assets.py' `
    'PROJECT_ROOT / "tools" / "blender" / "source" / "foundry_reforged_source.blend"' `
    'PROJECT_ROOT / "assets-source" / "blender" / "maps" / "foundry_reforged_source.blend"'
Replace-Exact 'tools/blender/build_gatehouse_assets.py' `
    'PROJECT_ROOT / "tools" / "blender" / "source" / "gatehouse_asset_source.blend"' `
    'PROJECT_ROOT / "assets-source" / "blender" / "maps" / "gatehouse_asset_source.blend"'
Replace-Exact 'tools/blender/build_weapon_assets.py' `
    'PROJECT_ROOT / "tools" / "blender" / "source" / "weapon_asset_source.blend"' `
    'PROJECT_ROOT / "assets-source" / "blender" / "weapons" / "weapon_asset_source.blend"'
Replace-Exact 'tools/blender/build_tactical_actor.py' `
    'r"C:\Users\Zhang\Desktop\3Dgame\godot\tools\blender\source"' `
    'r"C:\Users\Zhang\Desktop\3Dgame\godot\assets-source\blender\characters"'

if (Test-Path 'tools/blender/source/.gdignore') {
    & git rm -- 'tools/blender/source/.gdignore'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove legacy source .gdignore.' }
}

$trackedLfsPaths = @(
    'assets/environment/overcast_soil_puresky_1k.hdr',
    'assets-source/blender/maps/core_vault_asset_source.blend',
    'assets-source/blender/maps/foundry_asset_source.blend',
    'assets-source/blender/maps/foundry_reforged_source.blend',
    'assets-source/blender/maps/gatehouse_asset_source.blend',
    'assets-source/blender/characters/tactical_actor_lowpoly_source.blend',
    'assets-source/blender/weapons/weapon_asset_source.blend'
)

& git add --renormalize -- $trackedLfsPaths
if ($LASTEXITCODE -ne 0) { throw 'Git LFS renormalization failed.' }

& git add -- `
    'tools/blender/build_core_vault_assets.py', `
    'tools/blender/build_foundry_assets.py', `
    'tools/blender/build_foundry_reforged_assets.py', `
    'tools/blender/build_gatehouse_assets.py', `
    'tools/blender/build_weapon_assets.py', `
    'tools/blender/build_tactical_actor.py'
if ($LASTEXITCODE -ne 0) { throw 'Failed to stage Blender builder path changes.' }

$pointerPrefix = 'version https://git-lfs.github.com/spec/v1'
foreach ($path in $trackedLfsPaths) {
    $firstLine = (& git show ":$path" | Select-Object -First 1)
    if ($firstLine -ne $pointerPrefix) {
        throw "LFS pointer verification failed for $path (first line: $firstLine)"
    }
}

Write-Host '--- Git LFS files ---'
& git lfs ls-files
if ($LASTEXITCODE -ne 0) { throw 'git lfs ls-files failed.' }

Write-Host '--- Remaining legacy source references ---'
& git grep -n -E 'tools/blender/source|tools\\blender\\source' -- ':!tools/pipeline/migrate_asset_layers.ps1'
if ($LASTEXITCODE -gt 1) { throw 'git grep failed.' }

Write-Host '--- Staged migration diff ---'
& git status --short
& git diff --cached --stat

Write-Host ''
Write-Host 'MIGRATION_STAGED=PASS'
Write-Host 'Review the staged diff. Do not commit if unexpected files are present.'
