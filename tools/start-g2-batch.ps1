[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$EvidenceBase = '',
    [string]$BatchName = '',
    [int]$RecordFps = 30,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ToolPath {
    param([string[]]$Candidates, [string]$CommandName)
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }
    return $null
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sessionScript = Join-Path $PSScriptRoot 'run_g2_session.ps1'

$ffmpegPath = Resolve-ToolPath -Candidates @(
    'D:\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe'
) -CommandName 'ffmpeg'
if ($null -eq $ffmpegPath) {
    throw 'ffmpeg.exe was not found. Install ffmpeg or add it to PATH.'
}

$dirty = & git -C $repositoryRoot status --porcelain
if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String).Trim())) {
    throw 'G2 must run from a clean checkout. Commit or stash first.'
}

$runningGodot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -Match '^Godot')
if ($runningGodot.Count -gt 0) {
    throw 'Close every existing Godot process before starting a G2 batch.'
}

if ([string]::IsNullOrWhiteSpace($EvidenceBase)) {
    $EvidenceBase = if (Test-Path -LiteralPath 'D:\') { 'D:\VectorBreach\g2-evidence' }
        else { Join-Path (Split-Path $repositoryRoot -Parent) 'g2-evidence' }
}
if ($CheckOnly) {
    & $sessionScript -CheckOnly
    Write-Host 'G2_LAUNCHER_CHECK_OK'
    exit $LASTEXITCODE
}
if ([string]::IsNullOrWhiteSpace($BatchName)) {
    $BatchName = 'G2-{0}' -f (Get-Date).ToString('yyyyMMdd-HHmmss')
}
$videoDirectory = Join-Path (Join-Path $EvidenceBase $BatchName) 'video'
if (Test-Path -LiteralPath (Join-Path $EvidenceBase $BatchName)) {
    throw "Evidence batch already exists: $BatchName"
}
[void](New-Item -ItemType Directory -Path $videoDirectory -Force)
$rawVideoPath = Join-Path $videoDirectory 'session-raw.mp4'

Write-Host "G2_LAUNCHER batch=$BatchName"
Write-Host "G2_LAUNCHER ffmpeg=$ffmpegPath fps=$RecordFps"
Write-Host 'G2_LAUNCHER starting desktop recording before the game process launches...'

$ffmpegArgs = @(
    '-y', '-f', 'gdigrab', '-framerate', "$RecordFps", '-i', 'desktop',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
    '-pix_fmt', 'yuv420p', $rawVideoPath
)
$ffmpegProcess = New-Object System.Diagnostics.Process
$ffmpegStartInfo = $ffmpegProcess.StartInfo
$ffmpegStartInfo.FileName = $ffmpegPath
foreach ($argument in $ffmpegArgs) { [void]$ffmpegStartInfo.ArgumentList.Add($argument) }
$ffmpegStartInfo.RedirectStandardInput = $true
$ffmpegStartInfo.RedirectStandardError = $true
$ffmpegStartInfo.UseShellExecute = $false
$ffmpegStartInfo.CreateNoWindow = $true
[void]$ffmpegProcess.Start()
Start-Sleep -Seconds 3
if ($ffmpegProcess.HasExited) {
    throw "ffmpeg exited immediately with code $($ffmpegProcess.ExitCode); recording did not start."
}
Write-Host "G2_LAUNCHER recording pid=$($ffmpegProcess.Id)"

try {
    $sessionArgs = @('-RecordingConfirmed', '-BatchName', $BatchName, '-EvidenceBase', $EvidenceBase)
    if (-not [string]::IsNullOrWhiteSpace($GodotExe)) { $sessionArgs += @('-GodotExe', $GodotExe) }
    if ($CheckOnly) { $sessionArgs += '-CheckOnly' }
    & $sessionScript @sessionArgs
    $sessionExitCode = $LASTEXITCODE
}
finally {
    try {
        $ffmpegProcess.StandardInput.WriteLine('q')
        $ffmpegProcess.StandardInput.Flush()
    } catch {
        Write-Warning 'Could not send quit command to ffmpeg stdin.'
    }
    if (-not $ffmpegProcess.WaitForExit(20000)) {
        Write-Warning 'ffmpeg did not stop gracefully; killing and attempting remux.'
        $ffmpegProcess.Kill()
        $fixedPath = Join-Path $videoDirectory 'session-fixed.mp4'
        & $ffmpegPath -y -i $rawVideoPath -c copy $fixedPath 2>$null
        if ((Test-Path -LiteralPath $fixedPath) -and (Get-Item -LiteralPath $fixedPath).Length -gt 0) {
            Remove-Item -LiteralPath $rawVideoPath -Force
            Move-Item -LiteralPath $fixedPath -Destination $rawVideoPath
        }
    }
    if (-not $ffmpegProcess.HasExited) { $ffmpegProcess.WaitForExit() }
}

$videoInfo = Get-Item -LiteralPath $rawVideoPath -ErrorAction SilentlyContinue
if ($null -ne $videoInfo) {
    Write-Host ("G2_LAUNCHER video={0} size={1:N1} MiB" -f $rawVideoPath, ($videoInfo.Length / 1MB))
}

if ($CheckOnly) {
    Write-Host 'G2_LAUNCHER_CHECK_OK'
    exit 0
}
Write-Host "G2_LAUNCHER_DONE session_exit=$sessionExitCode evidence=$(Join-Path $EvidenceBase $BatchName)"
exit $sessionExitCode


