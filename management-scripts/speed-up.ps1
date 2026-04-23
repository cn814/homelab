# 1. Increase qBittorrent download limits
$login = Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -SessionVariable qbSession -UseBasicParsing

# Set new limits
$prefs = @{
    max_active_downloads = 30
    max_active_torrents = 50
    max_active_uploads = 10
}
$body = "json=" + ($prefs | ConvertTo-Json -Compress)
Invoke-WebRequest -Uri "http://localhost:8090/api/v2/app/setPreferences" -Method POST -Body $body -WebSession $qbSession -UseBasicParsing | Out-Null
Write-Output "=== qBittorrent limits updated ==="
Write-Output "  max_active_downloads: 15 -> 30"
Write-Output "  max_active_torrents: 25 -> 50"
Write-Output "  max_active_uploads: 8 -> 10"

# 2. Remove metaDL torrents
Write-Output ""
Write-Output "=== Cleaning metaDL torrents ==="
$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession
$metaDL = $torrents | Where-Object { $_.state -eq "metaDL" }
Write-Output "metaDL torrents: $($metaDL.Count)"
$metaDL | ForEach-Object {
    $hash = $_.hash
    Invoke-WebRequest -Uri "http://localhost:8090/api/v2/torrents/delete" -Method POST -Body "hashes=$hash&deleteFiles=true" -WebSession $qbSession -UseBasicParsing | Out-Null
    Write-Output "  Removed: $($_.name)"
}

# 3. Remove 2 warning items from Sonarr queue (not enough free space)
Write-Output ""
Write-Output "=== Removing Sonarr warning items ==="
$page = 1
$allRecs = @()
do {
    $sq = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=200&page=$page" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
    $allRecs += $sq.records
    $page++
} while ($allRecs.Count -lt $sq.totalRecords -and $sq.records.Count -eq 200)

$warnings = $allRecs | Where-Object { $_.trackedDownloadStatus -eq "warning" }
Write-Output "Warning items: $($warnings.Count)"
$warnings | ForEach-Object {
    $id = $_.id
    try {
        Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue/$id`?removeFromClient=true&blocklist=false" -Method DELETE -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 10 | Out-Null
        Write-Output "  Removed: $($_.title)"
    } catch {
        Write-Output "  Failed: $($_.title) - $($_.Exception.Message)"
    }
}

# Verify new state
Start-Sleep -Seconds 5
Write-Output ""
Write-Output "=== New qBittorrent State ==="
$prefs2 = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/app/preferences" -WebSession $qbSession
Write-Output "  max_active_downloads: $($prefs2.max_active_downloads)"
Write-Output "  max_active_torrents: $($prefs2.max_active_torrents)"

$torrents2 = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession
$tvT = $torrents2 | Where-Object { $_.category -eq "tv-sonarr" }
$dl = $tvT | Where-Object { $_.state -eq "downloading" }
$dlSpeed = ($dl | Measure-Object -Property dlspeed -Sum).Sum / 1MB
Write-Output "  Downloading: $($dl.Count) at $([Math]::Round($dlSpeed, 1)) MB/s"
$tvT | Group-Object -Property state | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}
