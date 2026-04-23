# Clean up junk and analyze seeding load
$session = Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -SessionVariable qbSession -UseBasicParsing
$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession

# --- Clean metaDL ---
$metaDL = $torrents | Where-Object { $_.state -eq "metaDL" }
Write-Output "=== metaDL: $($metaDL.Count) ==="
foreach ($t in $metaDL) {
    Write-Output "  Removing: $($t.name)"
    Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/delete" -Method POST -Body "hashes=$($t.hash)&deleteFiles=true" -WebSession $qbSession
}

# --- Clean missingFiles ---
$missing = $torrents | Where-Object { $_.state -eq "missingFiles" }
Write-Output ""
Write-Output "=== missingFiles: $($missing.Count) ==="
foreach ($t in $missing) {
    Write-Output "  Removing: $($t.name)"
    Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/delete" -Method POST -Body "hashes=$($t.hash)&deleteFiles=true" -WebSession $qbSession
}

# --- Check stalledDL ---
$stalled = $torrents | Where-Object { $_.state -eq "stalledDL" }
Write-Output ""
Write-Output "=== stalledDL: $($stalled.Count) ==="
foreach ($t in $stalled) {
    $addedDate = (Get-Date "1970-01-01").AddSeconds($t.added_on).ToLocalTime()
    $age = [Math]::Round(((Get-Date) - $addedDate).TotalDays, 1)
    Write-Output "  $($t.name) | $([Math]::Round($t.progress * 100, 0))% | $age days old | seeds: $($t.num_seeds)"
}
# Remove stalledDL older than 2 days with 0 seeds
$deadStalled = $stalled | Where-Object {
    $age = ((Get-Date) - (Get-Date "1970-01-01").AddSeconds($_.added_on).ToLocalTime()).TotalDays
    $age -gt 2 -and $_.num_seeds -eq 0
}
if ($deadStalled.Count -gt 0) {
    Write-Output ""
    Write-Output "Removing $($deadStalled.Count) dead stalledDL (>2 days, 0 seeds):"
    foreach ($t in $deadStalled) {
        Write-Output "  $($t.name)"
        Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/delete" -Method POST -Body "hashes=$($t.hash)&deleteFiles=true" -WebSession $qbSession
    }
}

# --- Analyze seeding load ---
Write-Output ""
Write-Output "=== Seeding Analysis ==="
$completed = $torrents | Where-Object { $_.progress -eq 1 }
Write-Output "Total completed torrents: $($completed.Count)"

$completed | Group-Object -Property state | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}

$totalSizeGB = [Math]::Round(($completed | Measure-Object -Property size -Sum).Sum / 1GB, 0)
Write-Output "Total size of completed: $totalSizeGB GB"

$fullySeeded = $completed | Where-Object { $_.ratio -ge 1.0 }
Write-Output "Ratio >= 1.0 (fully seeded): $($fullySeeded.Count)"

$old = $completed | Where-Object {
    $age = ((Get-Date) - (Get-Date "1970-01-01").AddSeconds($_.completion_on).ToLocalTime()).TotalDays
    $age -gt 7
}
Write-Output "Completed >7 days ago: $($old.Count)"

# How many are Sonarr-managed vs not
$sonarrCompleted = $completed | Where-Object { $_.category -eq "tv-sonarr" }
$radarrCompleted = $completed | Where-Object { $_.category -eq "radarr" }
Write-Output "Sonarr completed: $($sonarrCompleted.Count) | Radarr completed: $($radarrCompleted.Count)"

# forcedUP analysis
$forced = $torrents | Where-Object { $_.state -eq "forcedUP" }
Write-Output ""
Write-Output "=== forcedUP: $($forced.Count) ==="
foreach ($t in $forced) {
    $completedDate = (Get-Date "1970-01-01").AddSeconds($t.completion_on).ToLocalTime()
    $age = [Math]::Round(((Get-Date) - $completedDate).TotalDays, 1)
    Write-Output "  $($t.name) | ratio: $([Math]::Round($t.ratio, 2)) | $age days | up: $([Math]::Round($t.uploaded / 1GB, 1)) GB"
}
