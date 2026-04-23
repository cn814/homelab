$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$headers = @{ "X-Api-Key" = $sonarrApi; "Content-Type" = "application/json" }

# Get current root folders and quality profiles to map correctly
$rootFolders = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/rootfolder" -Headers @{ "X-Api-Key" = $sonarrApi }
Write-Output "Root folders:"
foreach ($rf in $rootFolders) { Write-Output "  $($rf.id): $($rf.path)" }

$profiles = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/qualityprofile" -Headers @{ "X-Api-Key" = $sonarrApi }
Write-Output "Quality profiles:"
foreach ($p in $profiles) { Write-Output "  $($p.id): $($p.name)" }
Write-Output ""

# Series to restore from backup database
$missing = @(
    @{ tvdbId = 287036; title = "Blaze and the Monster Machines"; path = "/data/TV/Blaze and the Monster Machines"; profileId = 1 },
    @{ tvdbId = 302938; title = "Letterkenny"; path = "/data/TV/Letterkenny"; profileId = 1 },
    @{ tvdbId = 72468;  title = "Lois & Clark: The New Adventures of Superman"; path = "/data/TV/Lois and Clark The New Adventures of Superman"; profileId = 1 },
    @{ tvdbId = 95011;  title = "Modern Family"; path = "/data/TV/Modern Family"; profileId = 1 },
    @{ tvdbId = 71697;  title = "Modern Marvels"; path = "/data/TV/Modern Marvels"; profileId = 1 },
    @{ tvdbId = 73388;  title = "MythBusters"; path = "/data/TV/Mythbusters"; profileId = 1 },
    @{ tvdbId = 366924; title = "Reacher"; path = "/data/TV/Reacher"; profileId = 1 },
    @{ tvdbId = 176941; title = "Sherlock"; path = "/data/TV/Sherlock"; profileId = 1 },
    @{ tvdbId = 449872; title = "The Paper (2025)"; path = "/data/TV/Paper"; profileId = 1 }
)

# Look up actual profile IDs from the backup DB
$tempDb = "c:\jellyfin-stack\scripts\temp_sonarr_backup.db"
$backupDirs = Get-ChildItem "c:\jellyfin-stack\backups" -Directory |
    Where-Object { $_.Name -match "^arr-stack-backup-" } |
    Sort-Object CreationTime -Descending
foreach ($dir in $backupDirs) {
    $dbPath = Join-Path $dir.FullName "sonarr\sonarr.db"
    if (Test-Path $dbPath) { Copy-Item $dbPath $tempDb -Force; break }
}

if (Test-Path $tempDb) {
    $pyCode = @"
import sqlite3
conn = sqlite3.connect(r'$tempDb')
cursor = conn.execute('SELECT TvdbId, QualityProfileId FROM Series')
for row in cursor.fetchall():
    print(f'{row[0]}|{row[1]}')
conn.close()
"@
    $pyCode | Out-File "c:\jellyfin-stack\scripts\temp_profiles.py" -Encoding UTF8
    $profileMap = @{}
    python "c:\jellyfin-stack\scripts\temp_profiles.py" | ForEach-Object {
        $parts = $_ -split '\|'
        $profileMap[[int]$parts[0]] = [int]$parts[1]
    }
    # Update profile IDs from backup
    foreach ($s in $missing) {
        if ($profileMap.ContainsKey($s.tvdbId)) {
            $s.profileId = $profileMap[$s.tvdbId]
        }
    }
    Remove-Item $tempDb -ErrorAction SilentlyContinue
    Remove-Item "c:\jellyfin-stack\scripts\temp_profiles.py" -ErrorAction SilentlyContinue
}

$restored = 0
foreach ($s in $missing) {
    Write-Output "Restoring: $($s.title)..."

    # Look up the series on TVDB via Sonarr
    $lookup = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series/lookup?term=tvdb:$($s.tvdbId)" -Headers @{ "X-Api-Key" = $sonarrApi } -TimeoutSec 30

    if (-not $lookup -or $lookup.Count -eq 0) {
        Write-Output "  FAILED: Could not find tvdbId $($s.tvdbId) - skipping"
        continue
    }

    $seriesData = $lookup[0]

    # Build add request
    $addBody = @{
        tvdbId = $s.tvdbId
        title = $seriesData.title
        qualityProfileId = $s.profileId
        rootFolderPath = Split-Path $s.path -Parent
        path = $s.path
        monitored = $true
        seasonFolder = $true
        seriesType = $seriesData.seriesType
        addOptions = @{
            monitor = "all"
            searchForMissingEpisodes = $true
            searchForCutoffUnmetEpisodes = $false
        }
    } | ConvertTo-Json -Depth 10

    try {
        $result = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Method POST -Headers $headers -Body $addBody -TimeoutSec 30
        Write-Output "  RESTORED: $($result.title) (id: $($result.id), profile: $($s.profileId))"
        $restored++
    } catch {
        $err = $_.Exception.Message
        Write-Output "  FAILED: $err"
    }

    Start-Sleep -Seconds 1
}

Write-Output ""
Write-Output "Restored $restored / $($missing.Count) series"
