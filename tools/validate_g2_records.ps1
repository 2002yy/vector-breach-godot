[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidenceRoot,

    [ValidateRange(1, 10000)]
    [int]$ExpectedCount = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Failure {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [void]$Failures.Add($Message)
}

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-RequiredPropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$Name]) {
        Add-Failure -Failures $Failures -Message "$Context missing required field '$Name'"
        return $null
    }

    return $InputObject.PSObject.Properties[$Name].Value
}

function Convert-ToRequiredInt {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $Value) {
        Add-Failure -Failures $Failures -Message "$Context field '$Name' must be an integer"
        return $null
    }

    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed)) {
        Add-Failure -Failures $Failures -Message "$Context field '$Name' must be an integer (actual=$Value)"
        return $null
    }

    return $parsed
}

function Convert-ToMarkdownCell {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", '<br>')
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8WithoutBom)
}

function Test-MatchRecord {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $failures = New-Object 'System.Collections.Generic.List[string]'
    $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $record = $null

    try {
        $record = Get-Content -Raw -Encoding UTF8 -LiteralPath $File.FullName | ConvertFrom-Json
    }
    catch {
        Add-Failure -Failures $failures -Message "invalid JSON: $($_.Exception.Message)"
    }

    $matchSerial = $null
    $initialTeam = $null
    $result = $null
    $playerScore = $null
    $opponentScore = $null
    $regulationRounds = $null
    $overtimeRounds = $null
    $rounds = @()
    $reasonCounts = @{}

    if ($null -ne $record) {
        $context = $File.Name
        $schemaVersion = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'schema_version' -Failures $failures -Context $context) -Name 'schema_version' -Failures $failures -Context $context
        $matchSerial = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'match_serial' -Failures $failures -Context $context) -Name 'match_serial' -Failures $failures -Context $context
        $levelId = [string](Get-RequiredPropertyValue -InputObject $record -Name 'level_id' -Failures $failures -Context $context)
        $active = Get-RequiredPropertyValue -InputObject $record -Name 'active' -Failures $failures -Context $context
        $phase = [string](Get-RequiredPropertyValue -InputObject $record -Name 'phase' -Failures $failures -Context $context)
        $result = [string](Get-RequiredPropertyValue -InputObject $record -Name 'result' -Failures $failures -Context $context)
        $initialTeam = [string](Get-RequiredPropertyValue -InputObject $record -Name 'initial_player_team' -Failures $failures -Context $context)
        $finalPlayerTeam = [string](Get-RequiredPropertyValue -InputObject $record -Name 'player_team' -Failures $failures -Context $context)
        $playerScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'player_score' -Failures $failures -Context $context) -Name 'player_score' -Failures $failures -Context $context
        $opponentScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'opponent_score' -Failures $failures -Context $context) -Name 'opponent_score' -Failures $failures -Context $context
        $ctScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'ct_score' -Failures $failures -Context $context) -Name 'ct_score' -Failures $failures -Context $context
        $tScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 't_score' -Failures $failures -Context $context) -Name 't_score' -Failures $failures -Context $context
        $regulationRounds = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'regulation_rounds' -Failures $failures -Context $context) -Name 'regulation_rounds' -Failures $failures -Context $context
        $overtimeRounds = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $record -Name 'overtime_rounds' -Failures $failures -Context $context) -Name 'overtime_rounds' -Failures $failures -Context $context
        $roundsValue = Get-RequiredPropertyValue -InputObject $record -Name 'rounds' -Failures $failures -Context $context
        $scoreboard = Get-RequiredPropertyValue -InputObject $record -Name 'scoreboard' -Failures $failures -Context $context
        $rounds = @($roundsValue)

        if ($schemaVersion -ne 1) {
            Add-Failure -Failures $failures -Message "schema_version must be 1 (actual=$schemaVersion)"
        }
        if ($null -ne $matchSerial -and $matchSerial -lt 1) {
            Add-Failure -Failures $failures -Message "match_serial must be positive (actual=$matchSerial)"
        }
        if ($levelId -ne 'gatehouse') {
            Add-Failure -Failures $failures -Message "level_id must be 'gatehouse' (actual='$levelId')"
        }
        if ($active -isnot [bool] -or [bool]$active) {
            Add-Failure -Failures $failures -Message "active must be false at export (actual=$active)"
        }
        if ($phase -ne 'complete') {
            Add-Failure -Failures $failures -Message "phase must be 'complete' (actual='$phase')"
        }
        if ($result -notin @('player_win', 'opponent_win', 'draw')) {
            Add-Failure -Failures $failures -Message "result is invalid (actual='$result')"
        }
        if ($initialTeam -notin @('T', 'CT')) {
            Add-Failure -Failures $failures -Message "initial_player_team must be T or CT (actual='$initialTeam')"
        }
        if ($finalPlayerTeam -notin @('T', 'CT')) {
            Add-Failure -Failures $failures -Message "player_team must be T or CT (actual='$finalPlayerTeam')"
        }
        if ($null -ne $playerScore -and $playerScore -lt 0) {
            Add-Failure -Failures $failures -Message "player_score must be non-negative (actual=$playerScore)"
        }
        if ($null -ne $opponentScore -and $opponentScore -lt 0) {
            Add-Failure -Failures $failures -Message "opponent_score must be non-negative (actual=$opponentScore)"
        }
        if ($null -ne $regulationRounds -and $regulationRounds -lt 0) {
            Add-Failure -Failures $failures -Message "regulation_rounds must be non-negative (actual=$regulationRounds)"
        }
        if ($null -ne $overtimeRounds -and $overtimeRounds -lt 0) {
            Add-Failure -Failures $failures -Message "overtime_rounds must be non-negative (actual=$overtimeRounds)"
        }

        if ($null -ne $playerScore -and $null -ne $opponentScore -and $null -ne $ctScore -and $null -ne $tScore -and $finalPlayerTeam -in @('T', 'CT')) {
            $expectedCtScore = if ($finalPlayerTeam -eq 'CT') { $playerScore } else { $opponentScore }
            $expectedTScore = if ($finalPlayerTeam -eq 'T') { $playerScore } else { $opponentScore }
            if ($ctScore -ne $expectedCtScore -or $tScore -ne $expectedTScore) {
                Add-Failure -Failures $failures -Message "ct_score/t_score do not match the final side display mapping (expected CT=$expectedCtScore T=$expectedTScore; actual CT=$ctScore T=$tScore)"
            }
        }

        if ($null -ne $regulationRounds -and $null -ne $overtimeRounds -and $rounds.Count -ne ($regulationRounds + $overtimeRounds)) {
            Add-Failure -Failures $failures -Message "round array length must equal regulation_rounds + overtime_rounds (rounds=$($rounds.Count) regulation=$regulationRounds overtime=$overtimeRounds)"
        }

        $previousPlayerScore = 0
        $previousOpponentScore = 0
        $previousRoundSerial = $null
        $allowedReasons = @('ELIMINATION', 'TIME', 'BOMB EXPLODED', 'BOMB DEFUSED')
        $oppositeInitialTeam = if ($initialTeam -eq 'T') { 'CT' } elseif ($initialTeam -eq 'CT') { 'T' } else { '' }

        for ($index = 0; $index -lt $rounds.Count; $index++) {
            $round = $rounds[$index]
            $roundNumber = $index + 1
            $roundContext = "$($File.Name) round $roundNumber"
            $recordedRoundNumber = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $round -Name 'round_number' -Failures $failures -Context $roundContext) -Name 'round_number' -Failures $failures -Context $roundContext
            $roundSerial = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $round -Name 'round_serial' -Failures $failures -Context $roundContext) -Name 'round_serial' -Failures $failures -Context $roundContext
            $stage = [string](Get-RequiredPropertyValue -InputObject $round -Name 'stage' -Failures $failures -Context $roundContext)
            $roundPlayerTeam = [string](Get-RequiredPropertyValue -InputObject $round -Name 'player_team' -Failures $failures -Context $roundContext)
            $winnerSide = [string](Get-RequiredPropertyValue -InputObject $round -Name 'winner_side' -Failures $failures -Context $roundContext)
            $winnerSquad = [string](Get-RequiredPropertyValue -InputObject $round -Name 'winner_squad' -Failures $failures -Context $roundContext)
            $reason = [string](Get-RequiredPropertyValue -InputObject $round -Name 'reason' -Failures $failures -Context $roundContext)
            $roundPlayerScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $round -Name 'player_score' -Failures $failures -Context $roundContext) -Name 'player_score' -Failures $failures -Context $roundContext
            $roundOpponentScore = Convert-ToRequiredInt -Value (Get-RequiredPropertyValue -InputObject $round -Name 'opponent_score' -Failures $failures -Context $roundContext) -Name 'opponent_score' -Failures $failures -Context $roundContext
            $sideSwap = Get-RequiredPropertyValue -InputObject $round -Name 'side_swap' -Failures $failures -Context $roundContext
            $matchComplete = Get-RequiredPropertyValue -InputObject $round -Name 'match_complete' -Failures $failures -Context $roundContext

            if ($recordedRoundNumber -ne $roundNumber) {
                Add-Failure -Failures $failures -Message "$roundContext round_number must be $roundNumber (actual=$recordedRoundNumber)"
            }
            if ($null -ne $roundSerial) {
                if ($roundSerial -lt 1) {
                    Add-Failure -Failures $failures -Message "$roundContext round_serial must be positive (actual=$roundSerial)"
                }
                if ($null -ne $previousRoundSerial -and $roundSerial -le $previousRoundSerial) {
                    Add-Failure -Failures $failures -Message "$roundContext round_serial must strictly increase (previous=$previousRoundSerial actual=$roundSerial)"
                }
                $previousRoundSerial = $roundSerial
            }

            $expectedStage = if ($roundNumber -le 6) { 'first_half' } elseif ($roundNumber -le 12) { 'second_half' } else { 'overtime' }
            if ($stage -ne $expectedStage) {
                Add-Failure -Failures $failures -Message "$roundContext stage must be '$expectedStage' (actual='$stage')"
            }

            $expectedRoundPlayerTeam = if ($roundNumber -le 6) {
                $initialTeam
            }
            elseif ($roundNumber -le 13) {
                $oppositeInitialTeam
            }
            else {
                $initialTeam
            }
            if ($roundPlayerTeam -ne $expectedRoundPlayerTeam) {
                Add-Failure -Failures $failures -Message "$roundContext player_team must be '$expectedRoundPlayerTeam' (actual='$roundPlayerTeam')"
            }

            if ($winnerSide -notin @('T', 'CT')) {
                Add-Failure -Failures $failures -Message "$roundContext winner_side must be T or CT (actual='$winnerSide')"
            }
            if ($winnerSquad -notin @('player', 'opponent')) {
                Add-Failure -Failures $failures -Message "$roundContext winner_squad is invalid (actual='$winnerSquad')"
            }
            if ($winnerSide -in @('T', 'CT') -and $roundPlayerTeam -in @('T', 'CT')) {
                $expectedWinnerSquad = if ($winnerSide -eq $roundPlayerTeam) { 'player' } else { 'opponent' }
                if ($winnerSquad -ne $expectedWinnerSquad) {
                    Add-Failure -Failures $failures -Message "$roundContext winner_squad must be '$expectedWinnerSquad' for winner_side '$winnerSide' and player_team '$roundPlayerTeam' (actual='$winnerSquad')"
                }
            }
            if ($reason -notin $allowedReasons) {
                Add-Failure -Failures $failures -Message "$roundContext reason is not a legal runtime outcome (actual='$reason')"
            }
            elseif ($reasonCounts.ContainsKey($reason)) {
                $reasonCounts[$reason] = [int]$reasonCounts[$reason] + 1
            }
            else {
                $reasonCounts[$reason] = 1
            }

            if ($null -ne $roundPlayerScore -and $null -ne $roundOpponentScore) {
                $playerDelta = $roundPlayerScore - $previousPlayerScore
                $opponentDelta = $roundOpponentScore - $previousOpponentScore
                if ($playerDelta -lt 0 -or $opponentDelta -lt 0 -or ($playerDelta + $opponentDelta) -ne 1) {
                    Add-Failure -Failures $failures -Message "$roundContext score must advance by exactly one point (previous=${previousPlayerScore}:$previousOpponentScore actual=${roundPlayerScore}:$roundOpponentScore)"
                }
                if (($winnerSquad -eq 'player' -and $playerDelta -ne 1) -or ($winnerSquad -eq 'opponent' -and $opponentDelta -ne 1)) {
                    Add-Failure -Failures $failures -Message "$roundContext score increment does not match winner_squad '$winnerSquad'"
                }
                $previousPlayerScore = $roundPlayerScore
                $previousOpponentScore = $roundOpponentScore
            }

            $expectedSideSwap = ($roundNumber -eq 6) -or ($roundNumber -eq 13 -and $rounds.Count -eq 14)
            if ($sideSwap -isnot [bool] -or [bool]$sideSwap -ne $expectedSideSwap) {
                Add-Failure -Failures $failures -Message "$roundContext side_swap must be $expectedSideSwap (actual=$sideSwap)"
            }

            $expectedMatchComplete = $roundNumber -eq $rounds.Count
            if ($matchComplete -isnot [bool] -or [bool]$matchComplete -ne $expectedMatchComplete) {
                Add-Failure -Failures $failures -Message "$roundContext match_complete must be $expectedMatchComplete (actual=$matchComplete)"
            }
        }

        if ($null -ne $playerScore -and $null -ne $opponentScore) {
            if ($previousPlayerScore -ne $playerScore -or $previousOpponentScore -ne $opponentScore) {
                Add-Failure -Failures $failures -Message "top-level score must equal the final round score (top=${playerScore}:$opponentScore rounds=${previousPlayerScore}:$previousOpponentScore)"
            }
            if ($null -ne $regulationRounds -and $null -ne $overtimeRounds -and ($playerScore + $opponentScore) -ne ($regulationRounds + $overtimeRounds)) {
                Add-Failure -Failures $failures -Message "final score sum must equal total rounds"
            }
        }

        if ($null -ne $overtimeRounds -and $overtimeRounds -eq 0) {
            if ($null -ne $regulationRounds -and ($regulationRounds -lt 7 -or $regulationRounds -gt 12)) {
                Add-Failure -Failures $failures -Message "regulation-only match must contain 7 through 12 rounds (actual=$regulationRounds)"
            }
            if ($null -ne $playerScore -and $null -ne $opponentScore) {
                if (-not (($playerScore -eq 7 -and $opponentScore -le 5) -or ($opponentScore -eq 7 -and $playerScore -le 5))) {
                    Add-Failure -Failures $failures -Message "regulation-only match must finish 7:0 through 7:5"
                }
                $expectedResult = if ($playerScore -gt $opponentScore) { 'player_win' } else { 'opponent_win' }
                if ($result -ne $expectedResult) {
                    Add-Failure -Failures $failures -Message "result must be '$expectedResult' for final score ${playerScore}:$opponentScore (actual='$result')"
                }
            }
        }
        elseif ($null -ne $overtimeRounds) {
            if ($regulationRounds -ne 12 -or $overtimeRounds -ne 2 -or $rounds.Count -ne 14) {
                Add-Failure -Failures $failures -Message "overtime match must contain 12 regulation and 2 overtime rounds"
            }
            if ($rounds.Count -ge 12) {
                $roundTwelvePlayerScore = Convert-ToRequiredInt -Value (Get-PropertyValue -InputObject $rounds[11] -Name 'player_score') -Name 'player_score' -Failures $failures -Context "$($File.Name) round 12"
                $roundTwelveOpponentScore = Convert-ToRequiredInt -Value (Get-PropertyValue -InputObject $rounds[11] -Name 'opponent_score') -Name 'opponent_score' -Failures $failures -Context "$($File.Name) round 12"
                if ($roundTwelvePlayerScore -ne 6 -or $roundTwelveOpponentScore -ne 6) {
                    Add-Failure -Failures $failures -Message "overtime must begin from a 6:6 regulation score"
                }
            }
            if ($null -ne $playerScore -and $null -ne $opponentScore) {
                $legalOvertimeScore = ($playerScore -eq 8 -and $opponentScore -eq 6) -or ($playerScore -eq 6 -and $opponentScore -eq 8) -or ($playerScore -eq 7 -and $opponentScore -eq 7)
                if (-not $legalOvertimeScore) {
                    Add-Failure -Failures $failures -Message "overtime final score must be 8:6, 6:8, or 7:7 (actual=${playerScore}:$opponentScore)"
                }
                $expectedResult = if ($playerScore -gt $opponentScore) { 'player_win' } elseif ($opponentScore -gt $playerScore) { 'opponent_win' } else { 'draw' }
                if ($result -ne $expectedResult) {
                    Add-Failure -Failures $failures -Message "result must be '$expectedResult' for overtime score ${playerScore}:$opponentScore (actual='$result')"
                }
            }
        }

        if ($null -eq $scoreboard) {
            Add-Failure -Failures $failures -Message "scoreboard must contain the six final combatants"
        }
        else {
            $scoreboardProperties = @($scoreboard.PSObject.Properties)
            if ($scoreboardProperties.Count -ne 6) {
                Add-Failure -Failures $failures -Message "scoreboard must contain exactly six combatants (actual=$($scoreboardProperties.Count))"
            }
            $stablePlayerIdentity = [string][char]0x4F60
            if ($null -eq $scoreboard.PSObject.Properties[$stablePlayerIdentity]) {
                Add-Failure -Failures $failures -Message "scoreboard must contain the stable player identity U+4F60"
            }

            $friendlyCount = 0
            $opponentCount = 0
            foreach ($scoreboardProperty in $scoreboardProperties) {
                $entry = $scoreboardProperty.Value
                $entryTeam = [string](Get-PropertyValue -InputObject $entry -Name 'team')
                if ($entryTeam -notin @('T', 'CT')) {
                    Add-Failure -Failures $failures -Message "scoreboard entry '$($scoreboardProperty.Name)' has invalid team '$entryTeam'"
                }
                elseif ($entryTeam -eq $finalPlayerTeam) {
                    $friendlyCount++
                }
                else {
                    $opponentCount++
                }
            }
            if ($finalPlayerTeam -in @('T', 'CT') -and ($friendlyCount -ne 3 -or $opponentCount -ne 3)) {
                Add-Failure -Failures $failures -Message "scoreboard must resolve to final 3v3 teams (friendly=$friendlyCount opponent=$opponentCount)"
            }
        }
    }

    return [pscustomobject]@{
        file = $File.Name
        relative_path = "raw/$($File.Name)"
        sha256 = $hash
        match_serial = $matchSerial
        initial_player_team = $initialTeam
        result = $result
        player_score = $playerScore
        opponent_score = $opponentScore
        regulation_rounds = $regulationRounds
        overtime_rounds = $overtimeRounds
        round_count = $rounds.Count
        verdict = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
        failures = @($failures)
        reason_counts = [pscustomobject]$reasonCounts
    }
}

$resolvedEvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$rawRoot = Join-Path $resolvedEvidenceRoot 'raw'
if (-not (Test-Path -LiteralPath $rawRoot -PathType Container)) {
    throw "Evidence raw directory does not exist: $rawRoot"
}

$rawFiles = @(Get-ChildItem -LiteralPath $rawRoot -File -Filter '*.json' | Sort-Object Name)
$globalFailures = New-Object 'System.Collections.Generic.List[string]'
$matchResults = @()

foreach ($rawFile in $rawFiles) {
    $matchResults += Test-MatchRecord -File $rawFile
}

if ($rawFiles.Count -ne $ExpectedCount) {
    Add-Failure -Failures $globalFailures -Message "expected exactly $ExpectedCount raw JSON records, found $($rawFiles.Count)"
}

$duplicateHashGroups = @($matchResults | Group-Object sha256 | Where-Object Count -gt 1)
foreach ($duplicateHashGroup in $duplicateHashGroups) {
    $duplicateNames = @($duplicateHashGroup.Group | ForEach-Object file) -join ', '
    Add-Failure -Failures $globalFailures -Message "duplicate SHA256 $($duplicateHashGroup.Name): $duplicateNames"
}

$recordsWithSerial = @($matchResults | Where-Object { $null -ne $_.match_serial } | Sort-Object match_serial, file)
if ($recordsWithSerial.Count -ne $matchResults.Count) {
    Add-Failure -Failures $globalFailures -Message 'every record must expose a valid match_serial before continuity can be proven'
}
elseif ($recordsWithSerial.Count -gt 0) {
    for ($index = 1; $index -lt $recordsWithSerial.Count; $index++) {
        $previous = [int]$recordsWithSerial[$index - 1].match_serial
        $current = [int]$recordsWithSerial[$index].match_serial
        if ($current -ne ($previous + 1)) {
            Add-Failure -Failures $globalFailures -Message "match_serial values must be consecutive in one process (previous=$previous current=$current)"
        }
    }
}

$tStarts = @($matchResults | Where-Object initial_player_team -eq 'T').Count
$ctStarts = @($matchResults | Where-Object initial_player_team -eq 'CT').Count
if ($tStarts -eq 0 -or $ctStarts -eq 0) {
    Add-Failure -Failures $globalFailures -Message "batch must cover both T and CT starts (T=$tStarts CT=$ctStarts)"
}
if ([Math]::Abs($tStarts - $ctStarts) -gt 1) {
    Add-Failure -Failures $globalFailures -Message "T/CT starts must be balanced (T=$tStarts CT=$ctStarts)"
}

# Outcome coverage (regulation wins/losses, 6:6 overtime) is informational only.
# These boundaries are covered by deterministic probes; see docs/PROJECT_STATUS.md G2.
$regulationPlayerWins = @($matchResults | Where-Object { $_.overtime_rounds -eq 0 -and $_.result -eq 'player_win' }).Count
$regulationOpponentWins = @($matchResults | Where-Object { $_.overtime_rounds -eq 0 -and $_.result -eq 'opponent_win' }).Count
$overtimeMatches = @($matchResults | Where-Object { $_.overtime_rounds -eq 2 }).Count
$draws = @($matchResults | Where-Object result -eq 'draw').Count

$reasonHistogram = [ordered]@{
    ELIMINATION = 0
    TIME = 0
    'BOMB EXPLODED' = 0
    'BOMB DEFUSED' = 0
}
foreach ($matchResult in $matchResults) {
    foreach ($reasonProperty in @($matchResult.reason_counts.PSObject.Properties)) {
        if ($reasonHistogram.Contains($reasonProperty.Name)) {
            $reasonHistogram[$reasonProperty.Name] = [int]$reasonHistogram[$reasonProperty.Name] + [int]$reasonProperty.Value
        }
    }
}

$perMatchFailureCount = @($matchResults | Where-Object verdict -eq 'FAIL').Count
$batchVerdict = if ($globalFailures.Count -eq 0 -and $perMatchFailureCount -eq 0) { 'PASS' } else { 'FAIL' }
$totalRounds = ($matchResults | Measure-Object -Property round_count -Sum).Sum
if ($null -eq $totalRounds) {
    $totalRounds = 0
}

$aggregate = [ordered]@{
    schema_version = 1
    generated_at = [DateTime]::Now.ToString('o')
    evidence_root = $resolvedEvidenceRoot
    expected_count = $ExpectedCount
    actual_count = $rawFiles.Count
    verdict = $batchVerdict
    coverage = [ordered]@{
        t_starts = $tStarts
        ct_starts = $ctStarts
        regulation_player_wins = $regulationPlayerWins
        regulation_opponent_wins = $regulationOpponentWins
        overtime_matches = $overtimeMatches
        draws = $draws
        total_rounds = [int]$totalRounds
        round_reason_histogram = $reasonHistogram
    }
    failures = @($globalFailures)
    matches = @($recordsWithSerial)
}

$aggregateJsonPath = Join-Path $resolvedEvidenceRoot 'aggregate.json'
$aggregateMarkdownPath = Join-Path $resolvedEvidenceRoot 'aggregate.md'
$hashListPath = Join-Path $resolvedEvidenceRoot 'SHA256SUMS.txt'

$aggregateJson = $aggregate | ConvertTo-Json -Depth 20
Write-Utf8File -Path $aggregateJsonPath -Content ($aggregateJson + "`n")

$hashLines = @($matchResults | Sort-Object file | ForEach-Object { "$($_.sha256)  $($_.relative_path)" })
$hashContent = if ($hashLines.Count -gt 0) { ($hashLines -join "`n") + "`n" } else { '' }
Write-Utf8File -Path $hashListPath -Content $hashContent

$markdown = New-Object 'System.Collections.Generic.List[string]'
[void]$markdown.Add('# Gatehouse G2 record validation')
[void]$markdown.Add('')
[void]$markdown.Add("- Verdict: **$batchVerdict**")
[void]$markdown.Add("- Records: $($rawFiles.Count) / $ExpectedCount")
[void]$markdown.Add("- Starts: T $tStarts, CT $ctStarts")
[void]$markdown.Add("- Regulation outcomes: player $regulationPlayerWins, opponent $regulationOpponentWins")
[void]$markdown.Add("- Overtime matches: $overtimeMatches; draws: $draws")
[void]$markdown.Add("- Total rounds: $totalRounds")
[void]$markdown.Add('')
[void]$markdown.Add('## Matches')
[void]$markdown.Add('')
[void]$markdown.Add('| Serial | File | Start | Result | Score | Reg | OT | Rounds | Verdict | Failures |')
[void]$markdown.Add('|---:|---|:---:|---|---:|---:|---:|---:|:---:|---|')
foreach ($matchResult in $recordsWithSerial) {
    $failureText = @($matchResult.failures) -join '; '
    [void]$markdown.Add("| $(Convert-ToMarkdownCell $matchResult.match_serial) | $(Convert-ToMarkdownCell $matchResult.file) | $(Convert-ToMarkdownCell $matchResult.initial_player_team) | $(Convert-ToMarkdownCell $matchResult.result) | $(Convert-ToMarkdownCell "$($matchResult.player_score):$($matchResult.opponent_score)") | $(Convert-ToMarkdownCell $matchResult.regulation_rounds) | $(Convert-ToMarkdownCell $matchResult.overtime_rounds) | $(Convert-ToMarkdownCell $matchResult.round_count) | $(Convert-ToMarkdownCell $matchResult.verdict) | $(Convert-ToMarkdownCell $failureText) |")
}

[void]$markdown.Add('')
[void]$markdown.Add('## Round reasons')
[void]$markdown.Add('')
foreach ($reason in $reasonHistogram.Keys) {
    [void]$markdown.Add("- $reason`: $($reasonHistogram[$reason])")
}

[void]$markdown.Add('')
[void]$markdown.Add('## Batch failures')
[void]$markdown.Add('')
if ($globalFailures.Count -eq 0) {
    [void]$markdown.Add('- None')
}
else {
    foreach ($failure in $globalFailures) {
        [void]$markdown.Add("- $failure")
    }
}

Write-Utf8File -Path $aggregateMarkdownPath -Content (($markdown -join "`n") + "`n")

if ($batchVerdict -eq 'PASS') {
    Write-Host "G2_RECORDS_PASS records=$($rawFiles.Count) overtime=$overtimeMatches evidence=$resolvedEvidenceRoot"
    exit 0
}

Write-Host "G2_RECORDS_FAIL records=$($rawFiles.Count) batch_failures=$($globalFailures.Count) match_failures=$perMatchFailureCount evidence=$resolvedEvidenceRoot"
exit 1
