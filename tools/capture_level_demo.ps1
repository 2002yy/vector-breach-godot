param(
    [string]$GodotExe = "E:\Godot\Godot_\Godot_console.exe",
    [string]$FfmpegExe = "E:\ffmpeg-8.1-essentials_build\bin\ffmpeg.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot "assets\demo"
$aviPath = Join-Path $outputDirectory "vector-breach-foundry-demo.avi"
$mp4Path = Join-Path $outputDirectory "vector-breach-foundry-demo.mp4"

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

& $GodotExe `
    --path $projectRoot `
    --write-movie $aviPath `
    --fixed-fps 30 `
    --scene res://scenes/tests/LevelDemoCapture.tscn
if ($LASTEXITCODE -ne 0) {
    throw "Godot demo capture failed with exit code $LASTEXITCODE"
}

& $FfmpegExe `
    -y `
    -i $aviPath `
    -vf "scale=1280:-2" `
    -c:v libx264 `
    -preset medium `
    -crf 23 `
    -pix_fmt yuv420p `
    -c:a aac `
    -b:a 128k `
    -movflags +faststart `
    $mp4Path
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg demo transcode failed with exit code $LASTEXITCODE"
}

Remove-Item -LiteralPath $aviPath
Write-Host "LEVEL_DEMO_READY=$mp4Path"
