# Pre-migration cleanup: disable grabs, remove non-active downloads
$sonarrHeaders = @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"; "Content-Type"="application/json"}
$radarrHeaders = @{"X-Api-Key"="a63000fb63a240a8bcb5e7d750926379"; "Content-Type"="application/json"}

# --- Disable RSS Sync in Sonarr ---
Write-Output "=== Disabling Sonarr RSS/Search ==="
$sonarrIndexers = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/indexer" -Headers $sonarrHeaders -TimeoutSec 30
foreach ($idx in $sonarrIndexers) {
    if ($idx.enableRss -or $idx.enableAutomaticSearch -or $idx.enableInteractiveSearch) {
        $idx.enableRss = $false
        $idx.enableAutomaticSearch = $false
        $idx.enableInteractiveSearch = $false
        $body = $idx | ConvertTo-Json -Depth 10 -Compress
        $null = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/indexer/$($idx.id)" -Method PUT -Headers $sonarrHeaders -Body $body -TimeoutSec 15
        Write-Output "  Disabled: $($idx.name)"
    }
}

# --- Disable RSS Sync in Radarr ---
Write-Output ""
Write-Output "=== Disabling Radarr RSS/Search ==="
$radarrIndexers = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/indexer" -Headers $radarrHeaders -TimeoutSec 30
foreach ($idx in $radarrIndexers) {
    if ($idx.enableRss -or $idx.enableAutomaticSearch -or $idx.enableInteractiveSearch) {
        $idx.enableRss = $false
        $idx.enableAutomaticSearch = $false
        $idx.enableInteractiveSearch = $false
        $body = $idx | ConvertTo-Json -Depth 10 -Compress
        $null = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/indexer/$($idx.id)" -Method PUT -Headers $radarrHeaders -Body $body -TimeoutSec 15
        Write-Output "  Disabled: $($idx.name)"
    }
}

# --- Remove queuedDL, stalledDL, metaDL from qBittorrent ---
Write-Output ""
Write-Output "=== Cleaning qBittorrent ==="
$session = Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -SessionVariable qbSession -UseBasicParsing
$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession

$toRemove = $torrents | Where-Object { $_.state -in @("queuedDL", "stalledDL", "metaDL") }
Write-Output "Removing $($toRemove.Count) non-active downloads..."

$hashes = ($toRemove | ForEach-Object { $_.hash }) -join "|"
if ($hashes) {
    Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=true" -WebSession $qbSession
    Write-Output "Done - removed $($toRemove.Count) torrents"
}

# --- Summary ---
Write-Output ""
Write-Output "=== Remaining Torrents ==="
$remaining = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession
$remaining | Group-Object -Property state | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}
$active = $remaining | Where-Object { $_.state -eq "downloading" }
$dlRemaining = [Math]::Round((($active | ForEach-Object { $_.size * (1 - $_.progress) }) | Measure-Object -Sum).Sum / 1GB, 1)
Write-Output ""
Write-Output "Active downloads: $($active.Count) ($dlRemaining GB remaining)"
