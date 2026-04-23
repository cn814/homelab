$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$qbtUrl = "http://localhost:8090"

# Login to qBittorrent
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$upgradeHashes = @{}
$totalUpgrades = 0

# Check Sonarr queue for upgrades
Write-Output "Checking Sonarr queue..."
$sonarrHeaders = @{ "X-Api-Key" = $sonarrApi }
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $sonarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        # Items with an existing episodeFile are upgrades
        if ($item.episodeHasFile) {
            $title = $item.title
            if ($title.Length -gt 60) { $title = $title.Substring(0, 60) + "..." }
            Write-Output "  UPGRADE: $title"
            if ($item.downloadId) {
                $upgradeHashes[$item.downloadId.ToLower()] = $item.id
            }
            $totalUpgrades++
        }
    }
    $page++
} while ($q.records.Count -eq 500)

# Check Radarr queue for upgrades
Write-Output ""
Write-Output "Checking Radarr queue..."
$radarrHeaders = @{ "X-Api-Key" = $radarrApi }
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $radarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.movieHasFile) {
            $title = $item.title
            if ($title.Length -gt 60) { $title = $title.Substring(0, 60) + "..." }
            Write-Output "  UPGRADE: $title"
            if ($item.downloadId) {
                $upgradeHashes[$item.downloadId.ToLower()] = $item.id
            }
            $totalUpgrades++
        }
    }
    $page++
} while ($q.records.Count -eq 500)

Write-Output ""
Write-Output "Found $totalUpgrades upgrades in queue"

if ($totalUpgrades -eq 0) {
    Write-Output "Nothing to remove."
    exit
}

# Remove from qBittorrent in batches
$hashes = @($upgradeHashes.Keys)
Write-Output ""
Write-Output "Removing $($hashes.Count) torrents from qBittorrent..."
for ($i = 0; $i -lt $hashes.Count; $i += 10) {
    $batch = $hashes[$i..[Math]::Min($i + 9, $hashes.Count - 1)]
    $hashStr = $batch -join '|'
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashStr&deleteFiles=true" -WebSession $session -UseBasicParsing -ContentType "application/x-www-form-urlencoded" | Out-Null
    $count = [Math]::Min($i + 10, $hashes.Count)
    Write-Output "  Deleted $count / $($hashes.Count)"
    if ($i + 10 -lt $hashes.Count) { Start-Sleep -Seconds 2 }
}

# Remove from Sonarr/Radarr queues
Write-Output ""
Write-Output "Removing from Sonarr queue..."
$sonarrRemoved = 0
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $sonarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.downloadId -and $upgradeHashes.ContainsKey($item.downloadId.ToLower())) {
            try {
                Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue/$($item.id)?removeFromClient=false&blocklist=false" -Method DELETE -Headers $sonarrHeaders -TimeoutSec 30 | Out-Null
                $sonarrRemoved++
            } catch {}
        }
    }
    $page++
} while ($q.records.Count -eq 500)
Write-Output "  Removed $sonarrRemoved items"

Write-Output ""
Write-Output "Removing from Radarr queue..."
$radarrRemoved = 0
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $radarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.downloadId -and $upgradeHashes.ContainsKey($item.downloadId.ToLower())) {
            try {
                Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue/$($item.id)?removeFromClient=false&blocklist=false" -Method DELETE -Headers $radarrHeaders -TimeoutSec 30 | Out-Null
                $radarrRemoved++
            } catch {}
        }
    }
    $page++
} while ($q.records.Count -eq 500)
Write-Output "  Removed $radarrRemoved items"

Write-Output ""
Write-Output "Done. Removed $totalUpgrades upgrades. Queue now focused on missing files only."
