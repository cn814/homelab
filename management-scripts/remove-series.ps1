param(
    [string[]]$SeriesNames,
    [switch]$DryRun,
    [switch]$Force,
    [int]$MaxDelete = 2
)

$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$qbtUrl = "http://localhost:8090"
$headers = @{ "X-Api-Key" = $sonarrApi }

if (-not $SeriesNames -or $SeriesNames.Count -eq 0) {
    Write-Output "Usage: remove-series.ps1 -SeriesNames 'Show Name'"
    Write-Output "  -DryRun     : Preview what would be deleted without deleting"
    Write-Output "  -Force      : Skip confirmation prompt"
    Write-Output "  -MaxDelete  : Max series to delete in one run (default: 3)"
    exit 0
}

# ─── SAFEGUARD 1: Hard limit on deletions per run ───
if ($SeriesNames.Count -gt $MaxDelete -and -not $Force) {
    Write-Output "ERROR: Refusing to delete $($SeriesNames.Count) series (max is $MaxDelete per run)."
    Write-Output "Use -MaxDelete $($SeriesNames.Count) to override, or run in smaller batches."
    exit 1
}

# Get all series from Sonarr
$allSeries = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Headers $headers -TimeoutSec 60

# ─── SAFEGUARD 2: Exact match only, collect and preview before deleting ───
$toDelete = @()
foreach ($name in $SeriesNames) {
    $match = $allSeries | Where-Object { $_.title -eq $name }
    if (-not $match) {
        Write-Output "NOT FOUND: '$name' - skipping (exact match required)"
        continue
    }
    foreach ($s in $match) {
        $toDelete += $s
    }
}

if ($toDelete.Count -eq 0) {
    Write-Output "No matching series found. Nothing to delete."
    exit 0
}

# ─── SAFEGUARD 3: Percentage check ───
$totalSeries = $allSeries.Count
$pct = [math]::Round(($toDelete.Count / $totalSeries) * 100, 1)
if ($pct -gt 5 -and -not $Force) {
    Write-Output "ERROR: This would delete $($toDelete.Count) of $totalSeries series ($pct% of library)."
    Write-Output "This exceeds the 5% safety threshold. Use -Force to override."
    exit 1
}

# ─── SAFEGUARD 4: Preview what will be deleted ───
Write-Output ""
Write-Output "═══════════════════════════════════════════"
Write-Output "  SERIES TO BE DELETED ($($toDelete.Count) of $totalSeries total)"
Write-Output "═══════════════════════════════════════════"
foreach ($s in $toDelete) {
    $epCount = ($s.statistics.episodeFileCount)
    $sizeGB = [math]::Round($s.statistics.sizeOnDisk / 1GB, 2)
    Write-Output "  • $($s.title) — $epCount episodes, $sizeGB GB on disk"
}
Write-Output "═══════════════════════════════════════════"

if ($DryRun) {
    Write-Output ""
    Write-Output "DRY RUN — nothing was deleted."
    exit 0
}

# ─── SAFEGUARD 5: Require confirmation ───
if (-not $Force) {
    Write-Output ""
    $confirm = Read-Host "Type YES to confirm deletion"
    if ($confirm -ne "YES") {
        Write-Output "Cancelled. Nothing was deleted."
        exit 0
    }
}

# ─── Proceed with deletion ───
# Login to qBittorrent
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

# Get Sonarr queue
$allQueue = @()
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownSeriesItems=true" -Headers $headers -TimeoutSec 60
    $allQueue += $q.records
    $page++
} while ($allQueue.Count -lt $q.totalRecords)

foreach ($s in $toDelete) {
    Write-Output ""
    Write-Output "Removing: $($s.title)..."

    # Find and remove queued items for this series
    $queueItems = $allQueue | Where-Object { $_.seriesId -eq $s.id }
    if ($queueItems) {
        Write-Output "  Clearing $($queueItems.Count) queued downloads..."
        foreach ($item in $queueItems) {
            if ($item.downloadId) {
                Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$($item.downloadId)&deleteFiles=true" -WebSession $session -UseBasicParsing -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue | Out-Null
            }
            try {
                Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=false" -Method DELETE -Headers $headers -TimeoutSec 30 | Out-Null
            } catch {}
        }
    }

    # Delete series from Sonarr with files
    Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series/$($s.id)?deleteFiles=true" -Method DELETE -Headers $headers -TimeoutSec 120 | Out-Null
    Write-Output "  DELETED: $($s.title)"
}

Write-Output ""
Write-Output "Done. Removed $($toDelete.Count) series."
