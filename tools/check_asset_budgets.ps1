param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$assetRoot = Join-Path $ProjectRoot "assets"
$modelRoot = Join-Path $assetRoot "models"
$localReferenceRoot = Join-Path $assetRoot "local_reference"

$MiB = 1MB
$budgets = [ordered]@{
    StandardGlbHardBytes = 16 * $MiB
    AllGlbTrendBytes = 100 * $MiB
    AllGlbHardBytes = 112 * $MiB
    TextureTrendBytes = 4 * $MiB
    TextureHardBytes = 8 * $MiB
    TextureTrendDimension = 2048
    TextureHardDimension = 4096
    AudioTrendBytes = 32 * $MiB
    AudioHardBytes = 64 * $MiB
}
$knownGlbDebt = @(
    "assets/models/dustline/dustline_depths.glb"
)
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Get-RelativePath {
    param([System.IO.FileInfo]$File)
    return $File.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/').Replace('\', '/')
}

function Format-MiB {
    param([long]$Bytes)
    return "{0:N2} MiB" -f ($Bytes / $MiB)
}

function Get-RasterDimensions {
    param([System.IO.FileInfo]$File)
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $image = [System.Drawing.Image]::FromFile($File.FullName)
        try {
            return [pscustomobject]@{ Width = $image.Width; Height = $image.Height }
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
        return $null
    }
}

Write-Host "Asset budget check: $ProjectRoot"
Write-Host "Formal assets exclude assets/local_reference."

$glbs = @(Get-ChildItem $modelRoot -Recurse -File -Filter *.glb)
$glbTotal = [long](($glbs | Measure-Object Length -Sum).Sum)
foreach ($glb in $glbs) {
    $relative = Get-RelativePath $glb
    if ($knownGlbDebt -contains $relative) {
        if ($glb.Length -gt $budgets.StandardGlbHardBytes) {
            $warnings.Add("KNOWN_DEBT GLB $relative is $(Format-MiB $glb.Length); standard hard limit is $(Format-MiB $budgets.StandardGlbHardBytes).")
        }
        continue
    }
    if ($glb.Length -gt $budgets.StandardGlbHardBytes) {
        $failures.Add("GLB $relative is $(Format-MiB $glb.Length), above $(Format-MiB $budgets.StandardGlbHardBytes).")
    }
}
if ($glbTotal -gt $budgets.AllGlbHardBytes) {
    $failures.Add("Formal GLB total is $(Format-MiB $glbTotal), above hard limit $(Format-MiB $budgets.AllGlbHardBytes).")
} elseif ($glbTotal -gt $budgets.AllGlbTrendBytes) {
    $warnings.Add("TREND formal GLB total is $(Format-MiB $glbTotal), above $(Format-MiB $budgets.AllGlbTrendBytes).")
}

$textureExtensions = @('.png', '.jpg', '.jpeg', '.webp', '.hdr', '.exr')
$textures = @(Get-ChildItem $assetRoot -Recurse -File | Where-Object {
    -not $_.FullName.StartsWith($localReferenceRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
    $textureExtensions -contains $_.Extension.ToLowerInvariant()
})
foreach ($texture in $textures) {
    $relative = Get-RelativePath $texture
    if ($texture.Length -gt $budgets.TextureHardBytes) {
        $failures.Add("Texture $relative is $(Format-MiB $texture.Length), above $(Format-MiB $budgets.TextureHardBytes).")
    } elseif ($texture.Length -gt $budgets.TextureTrendBytes) {
        $warnings.Add("TREND texture $relative is $(Format-MiB $texture.Length).")
    }
    if ($texture.Extension.ToLowerInvariant() -in @('.png', '.jpg', '.jpeg')) {
        $dimensions = Get-RasterDimensions $texture
        if ($null -eq $dimensions) {
            $failures.Add("Could not read texture dimensions: $relative")
        } elseif ($dimensions.Width -gt $budgets.TextureHardDimension -or $dimensions.Height -gt $budgets.TextureHardDimension) {
            $failures.Add("Texture $relative is $($dimensions.Width)x$($dimensions.Height), above $($budgets.TextureHardDimension).")
        } elseif ($dimensions.Width -gt $budgets.TextureTrendDimension -or $dimensions.Height -gt $budgets.TextureTrendDimension) {
            $warnings.Add("TREND texture $relative is $($dimensions.Width)x$($dimensions.Height).")
        }
    }
}

$audioExtensions = @('.wav', '.ogg', '.mp3')
$audioFiles = @(Get-ChildItem $assetRoot -Recurse -File | Where-Object {
    -not $_.FullName.StartsWith($localReferenceRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
    $audioExtensions -contains $_.Extension.ToLowerInvariant()
})
$audioTotal = [long](($audioFiles | Measure-Object Length -Sum).Sum)
if ($audioTotal -gt $budgets.AudioHardBytes) {
    $failures.Add("Audio total is $(Format-MiB $audioTotal), above hard limit $(Format-MiB $budgets.AudioHardBytes).")
} elseif ($audioTotal -gt $budgets.AudioTrendBytes) {
    $warnings.Add("TREND audio total is $(Format-MiB $audioTotal), above $(Format-MiB $budgets.AudioTrendBytes).")
}

Write-Host "GLB: $($glbs.Count) files, $(Format-MiB $glbTotal) total; standard hard $(Format-MiB $budgets.StandardGlbHardBytes), total hard $(Format-MiB $budgets.AllGlbHardBytes)."
Write-Host "Textures: $($textures.Count) files; hard $($budgets.TextureHardDimension)x$($budgets.TextureHardDimension) and $(Format-MiB $budgets.TextureHardBytes) each."
Write-Host "Audio: $($audioFiles.Count) files, $(Format-MiB $audioTotal) total; hard $(Format-MiB $budgets.AudioHardBytes)."
foreach ($warning in $warnings) {
    Write-Warning $warning
}
foreach ($failure in $failures) {
    Write-Error $failure -ErrorAction Continue
}

if ($failures.Count -gt 0) {
    Write-Host "ASSET_BUDGET_FAIL failures=$($failures.Count) warnings=$($warnings.Count)"
    exit 1
}
Write-Host "ASSET_BUDGET_OK warnings=$($warnings.Count)"
exit 0
