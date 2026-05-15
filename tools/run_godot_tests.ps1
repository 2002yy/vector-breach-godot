param(
    [string]$GodotExe = ""
)

$ErrorActionPreference = "Stop"

function Resolve-GodotExe {
    param([string]$Preferred)

    if ($Preferred -and (Test-Path $Preferred)) {
        return (Resolve-Path $Preferred).Path
    }

    if ($env:GODOT_EXE -and (Test-Path $env:GODOT_EXE)) {
        return (Resolve-Path $env:GODOT_EXE).Path
    }

    $command = Get-Command Godot.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $fallbacks = @(
        "C:\Program Files\Godot\Godot.exe",
        "C:\Program Files (x86)\Godot\Godot.exe"
    )

    foreach ($candidate in $fallbacks) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Unable to locate Godot.exe. Pass -GodotExe <path>, set GODOT_EXE, or add Godot.exe to PATH."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$godot = Resolve-GodotExe -Preferred $GodotExe
$scenes = @(
    "res://scenes/tests/LevelDataLoaderTestRunner.tscn",
    "res://scenes/tests/WeaponSystemTestRunner.tscn",
    "res://scenes/tests/GrayboxLevelTestRunner.tscn",
    "res://scenes/tests/HitFeedbackLayerTestRunner.tscn",
    "res://scenes/tests/MainStateFlowTestRunner.tscn"
)

Write-Host "Using Godot: $godot"
Write-Host "Project: $projectRoot"

foreach ($scene in $scenes) {
    Write-Host ""
    Write-Host "==> Running $scene"
    & $godot --headless --path $projectRoot --scene $scene
    if ($LASTEXITCODE -ne 0) {
        throw "Test suite failed: $scene"
    }
}

Write-Host ""
Write-Host "All Godot test suites passed."
