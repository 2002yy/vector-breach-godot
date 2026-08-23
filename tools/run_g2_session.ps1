[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$EvidenceBase = '',
    [string]$BatchName = '',
    [switch]$RecordingConfirmed,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Variable -Name EXPECTED_MATCHES -Value 10 -Option Constant

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-JsonLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::AppendAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        [void]$candidates.Add($RequestedPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_EXE)) {
        [void]$candidates.Add($env:GODOT_EXE)
    }
    [void]$candidates.Add('D:\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe')
    [void]$candidates.Add('D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe')

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($commandName in @('godot', 'godot4', 'Godot.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw 'Godot executable was not found. Pass -GodotExe or set GODOT_EXE.'
}

function Get-ProjectName {
    param([string]$ProjectFile)

    $text = [System.IO.File]::ReadAllText($ProjectFile, [System.Text.Encoding]::UTF8)
    $match = [System.Text.RegularExpressions.Regex]::Match($text, '(?m)^config/name="(?<name>[^"]+)"\s*$')
    if (-not $match.Success) {
        throw "Could not resolve config/name from $ProjectFile"
    }
    return $match.Groups['name'].Value
}

function Get-GitValue {
    param(
        [string]$RepositoryRoot,
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
    return ($output | Out-String).Trim()
}

function Get-CompleteMatchRecord {
    param([string]$Path)

    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $record = $text | ConvertFrom-Json
        if ($null -eq $record -or [string]$record.phase -ne 'complete') {
            return $null
        }
        if ([string]$record.level_id -ne 'gatehouse') {
            return $null
        }
        if ([int]$record.match_serial -le 0 -or @($record.rounds).Count -le 0) {
            return $null
        }
        return $record
    }
    catch {
        return $null
    }
}

function Get-NewRecordFiles {
    param(
        [string]$SourceRoot,
        [System.Collections.Generic.HashSet[string]]$BaselinePaths,
        [System.Collections.Generic.HashSet[string]]$CapturedPaths
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.json' |
            Where-Object {
                -not $BaselinePaths.Contains($_.FullName) -and
                -not $CapturedPaths.Contains($_.FullName)
            } |
            Sort-Object LastWriteTimeUtc, Name
    )
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectFile = Join-Path $repositoryRoot 'project.godot'
$validatorPath = Join-Path $PSScriptRoot 'validate_g2_records.ps1'
$resolvedGodotExe = Resolve-GodotExecutable -RequestedPath $GodotExe
$godotExecutableHash = (Get-FileHash -LiteralPath $resolvedGodotExe -Algorithm SHA256).Hash.ToLowerInvariant()
$projectName = Get-ProjectName -ProjectFile $projectFile
$recordSource = Join-Path $env:APPDATA (Join-Path 'Godot\app_userdata' (Join-Path $projectName 'match-records'))
$commit = Get-GitValue -RepositoryRoot $repositoryRoot -Arguments @('rev-parse', 'HEAD')
$branch = Get-GitValue -RepositoryRoot $repositoryRoot -Arguments @('branch', '--show-current')
$dirty = Get-GitValue -RepositoryRoot $repositoryRoot -Arguments @('status', '--porcelain')

if (-not [string]::IsNullOrWhiteSpace($dirty)) {
    throw 'G2 must run from a clean checkout so the recorded commit identifies the tested build.'
}
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Validator not found: $validatorPath"
}

if ([string]::IsNullOrWhiteSpace($EvidenceBase)) {
    $EvidenceBase = if (Test-Path -LiteralPath 'D:\') {
        'D:\VectorBreach\g2-evidence'
    }
    else {
        Join-Path (Split-Path $repositoryRoot -Parent) 'g2-evidence'
    }
}

$existingRecords = @()
if (Test-Path -LiteralPath $recordSource -PathType Container) {
    $existingRecords = @(Get-ChildItem -LiteralPath $recordSource -File -Filter '*.json')
}

Write-Host "G2_CHECK commit=$commit branch=$branch"
Write-Host "G2_CHECK godot=$resolvedGodotExe"
Write-Host "G2_CHECK source=$recordSource existing_records=$($existingRecords.Count)"
Write-Host "G2_CHECK evidence_base=$EvidenceBase expected_matches=$EXPECTED_MATCHES"

if ($CheckOnly) {
    Write-Host 'G2_SESSION_CHECK_OK'
    exit 0
}

if (-not $RecordingConfirmed) {
    throw 'Start one continuous external screen recording, then rerun with -RecordingConfirmed.'
}

$runningGodot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -Match '^Godot')
if ($runningGodot.Count -gt 0) {
    $processList = @($runningGodot | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', '
    throw "Close every existing Godot process before G2 so record provenance is isolated: $processList"
}

if ([string]::IsNullOrWhiteSpace($BatchName)) {
    $shortCommit = $commit.Substring(0, [Math]::Min(8, $commit.Length))
    $BatchName = 'G2-{0}-{1}-A' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $shortCommit
}

$evidenceRoot = Join-Path $EvidenceBase $BatchName
if (Test-Path -LiteralPath $evidenceRoot) {
    throw "Evidence batch already exists; refusing to overwrite: $evidenceRoot"
}

$rawRoot = Join-Path $evidenceRoot 'raw'
$videoRoot = Join-Path $evidenceRoot 'video'
$screenshotsRoot = Join-Path $evidenceRoot 'screenshots'
$logsRoot = Join-Path $evidenceRoot 'logs'
foreach ($directory in @($rawRoot, $videoRoot, $screenshotsRoot, $logsRoot)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
}

$baselinePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$baseline = @()
foreach ($file in $existingRecords) {
    [void]$baselinePaths.Add($file.FullName)
    $baseline += [ordered]@{
        name = $file.Name
        length = $file.Length
        last_write_utc = $file.LastWriteTimeUtc.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$startedAt = (Get-Date).ToUniversalTime()
$sessionLogPath = Join-Path $logsRoot 'session.jsonl'
$manifestPath = Join-Path $evidenceRoot 'session.json'
$manifest = [ordered]@{
    schema_version = 1
    session_id = [guid]::NewGuid().ToString()
    batch_name = $BatchName
    status = 'prepared'
    created_at_utc = $startedAt.ToString('o')
    repository = '2002yy/vector-breach-godot'
    commit = $commit
    branch = $branch
    project_name = $projectName
    godot_executable = $resolvedGodotExe
    godot_executable_sha256 = $godotExecutableHash
    record_source = $recordSource
    expected_matches = $EXPECTED_MATCHES
    required_start_teams = [ordered]@{ T = 5; CT = 5 }
    recording_confirmed = $true
    operator_plan_valid = $true
    baseline_records = $baseline
    process_id = $null
    process_started_at_utc = $null
    process_exit_code = $null
    captured_records = @()
    validator_exit_code = $null
}
Write-JsonFile -Path $manifestPath -Value $manifest

$checklist = @'
# Gatehouse G2 operator checklist

- Keep one continuous screen recording running from before launch until after the tenth conclusion page.
- Use Gatehouse only. Start matches 1,3,5,7,9 as T and 2,4,6,8,10 as CT.
- Every match must begin from the menu, cross halftime, reach a legal terminal result, and show the conclusion page.
- Play naturally; win/loss/overtime outcomes are recorded for information only and are covered by separate deterministic probes.
- Do not use debug controls, probes, scripted input, or skip rounds.
- Do not launch another Godot process or run automated tests during this session.
- After the tenth conclusion page, keep the recording running, exit the game normally, and retain the uncut video in this batch's video directory.
- Any crash, soft lock, unrecoverable C4, permanent AI stall, or state leak is a G2 FAIL; retain the partial evidence and start a new batch rather than editing raw JSON.
'@
[System.IO.File]::WriteAllText((Join-Path $evidenceRoot 'OPERATOR_CHECKLIST.md'), $checklist, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "G2_SESSION_PREPARED evidence=$evidenceRoot"
Write-Host 'Launch is visible and interactive. Play exactly ten complete matches, then exit the game normally.'

$process = Start-Process -FilePath $resolvedGodotExe -ArgumentList @('--path', $repositoryRoot) -PassThru
$processStartedAtUtc = $process.StartTime.ToUniversalTime()
$manifest.status = 'running'
$manifest.process_id = $process.Id
$manifest.process_started_at_utc = $processStartedAtUtc.ToString('o')
Write-JsonFile -Path $manifestPath -Value $manifest
Add-JsonLine -Path $sessionLogPath -Value ([ordered]@{
    event = 'process_started'
    at_utc = (Get-Date).ToUniversalTime().ToString('o')
    process_id = $process.Id
    process_started_at_utc = $processStartedAtUtc.ToString('o')
    commit = $commit
})

$capturedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$candidateSignatures = @{}
$captured = New-Object 'System.Collections.Generic.List[object]'
$warnedComplete = $false
$finalDrainPolls = 0
$operatorPlanValid = $true

while ($true) {
    $process.Refresh()
    $newFiles = Get-NewRecordFiles -SourceRoot $recordSource -BaselinePaths $baselinePaths -CapturedPaths $capturedPaths
    foreach ($file in $newFiles) {
        $signature = "$($file.Length)|$($file.LastWriteTimeUtc.Ticks)"
        if (-not $candidateSignatures.ContainsKey($file.FullName) -or $candidateSignatures[$file.FullName] -ne $signature) {
            $candidateSignatures[$file.FullName] = $signature
            continue
        }

        $record = Get-CompleteMatchRecord -Path $file.FullName
        if ($null -eq $record) {
            continue
        }

        $destination = Join-Path $rawRoot $file.Name
        if (Test-Path -LiteralPath $destination) {
            throw "Raw evidence destination already exists; refusing to overwrite: $destination"
        }

        [System.IO.File]::Copy($file.FullName, $destination, $false)
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -ne $destinationHash) {
            throw "Copied record hash mismatch: $($file.Name)"
        }

        [void]$capturedPaths.Add($file.FullName)
        $entry = [ordered]@{
            index = $captured.Count + 1
            name = $file.Name
            captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            match_serial = [int]$record.match_serial
            initial_player_team = [string]$record.initial_player_team
            result = [string]$record.result
            player_score = [int]$record.player_score
            opponent_score = [int]$record.opponent_score
            round_count = @($record.rounds).Count
            sha256 = $destinationHash
        }
        $expectedTeam = if ((($captured.Count + 1) % 2) -eq 1) { 'T' } else { 'CT' }
        if ($entry.initial_player_team -ne $expectedTeam) {
            $operatorPlanValid = $false
            Add-JsonLine -Path $sessionLogPath -Value ([ordered]@{
                event = 'operator_plan_violation'
                at_utc = (Get-Date).ToUniversalTime().ToString('o')
                process_id = $process.Id
                match_index = $captured.Count + 1
                expected_team = $expectedTeam
                actual_team = $entry.initial_player_team
            })
            Write-Warning ("G2 operator plan violation at match {0}: expected {1}, got {2}. Retain evidence and restart the whole batch." -f ($captured.Count + 1), $expectedTeam, $entry.initial_player_team)
        }
        [void]$captured.Add([pscustomobject]$entry)
        Add-JsonLine -Path $sessionLogPath -Value ([ordered]@{
            event = 'record_captured'
            at_utc = (Get-Date).ToUniversalTime().ToString('o')
            process_id = $process.Id
            record = $entry
        })
        Write-Host ("G2_CAPTURED {0}/{1} serial={2} start={3} result={4} score={5}:{6}" -f $captured.Count, $EXPECTED_MATCHES, $entry.match_serial, $entry.initial_player_team, $entry.result, $entry.player_score, $entry.opponent_score)
        if ($captured.Count -gt $EXPECTED_MATCHES) {
            $operatorPlanValid = $false
            Write-Warning 'More than ten completed matches were captured. Retain evidence and restart the whole batch.'
        }
    }

    if ($captured.Count -ge $EXPECTED_MATCHES -and -not $warnedComplete) {
        Write-Host 'G2_CAPTURE_TARGET_REACHED. Show the final conclusion page in the recording, then exit the game normally.'
        $warnedComplete = $true
    }

    if ($process.HasExited) {
        $finalDrainPolls++
        if ($finalDrainPolls -ge 3) {
            break
        }
    }
    else {
        $finalDrainPolls = 0
    }

    Start-Sleep -Milliseconds 750
}

$process.Refresh()
$manifest.status = 'game_exited'
$manifest.process_exit_code = $process.ExitCode
$manifest.captured_records = @($captured)
$manifest.operator_plan_valid = $operatorPlanValid
Write-JsonFile -Path $manifestPath -Value $manifest
Add-JsonLine -Path $sessionLogPath -Value ([ordered]@{
    event = 'process_exited'
    at_utc = (Get-Date).ToUniversalTime().ToString('o')
    process_id = $process.Id
    exit_code = $process.ExitCode
    captured_count = $captured.Count
})

& $validatorPath -EvidenceRoot $evidenceRoot -ExpectedCount $EXPECTED_MATCHES
$validatorExitCode = $LASTEXITCODE
$manifest.status = if ($validatorExitCode -eq 0 -and $operatorPlanValid) { 'validated' } elseif (-not $operatorPlanValid) { 'failed_operator_plan' } else { 'failed_validation' }
$manifest.validator_exit_code = $validatorExitCode
$manifest.captured_records = @($captured)
Write-JsonFile -Path $manifestPath -Value $manifest

if ($validatorExitCode -ne 0 -or -not $operatorPlanValid) {
    Write-Host "G2_SESSION_FAIL evidence=$evidenceRoot captured=$($captured.Count) validator_exit=$validatorExitCode operator_plan_valid=$operatorPlanValid"
    exit 1
}

Write-Host "G2_SESSION_PASS evidence=$evidenceRoot captured=$($captured.Count)"
exit 0
