$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$headers = @{ "X-Api-Key" = $sonarrApi }

# Get current series
$current = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Headers $headers -TimeoutSec 60
$currentTitles = @{}
foreach ($s in $current) { $currentTitles[$s.tvdbId] = $s.title }

# Find the latest backup with a sonarr.db
$backupDirs = Get-ChildItem "c:\jellyfin-stack\backups" -Directory |
    Where-Object { $_.Name -match "^arr-stack-backup-" } |
    Sort-Object CreationTime -Descending

$backupDb = $null
foreach ($dir in $backupDirs) {
    $dbPath = Join-Path $dir.FullName "sonarr\sonarr.db"
    if (Test-Path $dbPath) {
        $backupDb = $dbPath
        Write-Output "Using backup: $($dir.Name)"
        break
    }
}

if (-not $backupDb) {
    Write-Output "No backup with sonarr.db found!"
    exit 1
}

# Copy DB to temp so we don't lock the backup
$tempDb = "c:\jellyfin-stack\scripts\temp_sonarr_backup.db"
Copy-Item $backupDb $tempDb -Force

# Query the backup database for series
# Use sqlite3 if available, otherwise use Python
$pythonCode = @"
import sqlite3, json
conn = sqlite3.connect(r'$tempDb')
cursor = conn.execute('SELECT TvdbId, Title, Path, QualityProfileId FROM Series ORDER BY Title')
rows = cursor.fetchall()
conn.close()
for tvdb_id, title, path, profile in rows:
    print(f'{tvdb_id}|{title}|{path}|{profile}')
"@

$pythonCode | Out-File "c:\jellyfin-stack\scripts\temp_query.py" -Encoding UTF8
$backupSeries = python "c:\jellyfin-stack\scripts\temp_query.py"

Write-Output ""
Write-Output "=== MISSING SERIES (in backup but not in Sonarr) ==="
Write-Output ""

$missing = @()
foreach ($line in $backupSeries) {
    $parts = $line -split '\|', 4
    $tvdbId = [int]$parts[0]
    $title = $parts[1]
    $path = $parts[2]
    $profileId = $parts[3]

    if (-not $currentTitles.ContainsKey($tvdbId)) {
        Write-Output "  MISSING: $title (tvdbId: $tvdbId, path: $path)"
        $missing += @{ tvdbId = $tvdbId; title = $title; path = $path; profileId = $profileId }
    }
}

Write-Output ""
Write-Output "Total missing: $($missing.Count)"
Write-Output "Current series: $($currentTitles.Count)"

# Cleanup temp files
Remove-Item $tempDb -ErrorAction SilentlyContinue
Remove-Item "c:\jellyfin-stack\scripts\temp_query.py" -ErrorAction SilentlyContinue
