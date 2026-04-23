$qbtUrl = "http://localhost:8090"
$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 60).Content | ConvertFrom-Json
$active = $torrents | Where-Object { $_.state -match "downloading|uploading|stalledDL|stalledUP|metaDL|forcedDL|forcedUP" }
$paused = $torrents | Where-Object { $_.state -match "paused|stopped" }
$transfer = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/transfer/info" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
Write-Output "Active: $($active.Count)  Paused: $($paused.Count)  Total: $($torrents.Count)"
Write-Output "DL: $([math]::Round($transfer.dl_info_speed / 1KB, 0)) KB/s  UL: $([math]::Round($transfer.up_info_speed / 1KB, 0)) KB/s"
