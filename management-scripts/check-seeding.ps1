$qbtUrl = "http://localhost:8090"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$torrents = Invoke-RestMethod -Uri "$qbtUrl/api/v2/torrents/info" -WebSession $session

$seeding = $torrents | Where-Object { $_.state -match "uploading|stalledUP|queuedUP" }
$activeUp = $torrents | Where-Object { $_.state -eq "uploading" }

Write-Output "=== Seeding Stats ==="
Write-Output "  Total seeding: $($seeding.Count)"
Write-Output "  Actively uploading: $($activeUp.Count)"
Write-Output ""

# Ratio breakdown
$ratios = $seeding | ForEach-Object { $_.ratio }
$avgRatio = if ($ratios.Count -gt 0) { [math]::Round(($ratios | Measure-Object -Average).Average, 2) } else { 0 }
$above1 = ($seeding | Where-Object { $_.ratio -ge 1.0 }).Count
$below1 = ($seeding | Where-Object { $_.ratio -lt 1.0 }).Count

Write-Output "=== Ratio Breakdown ==="
Write-Output "  Average ratio: $avgRatio"
Write-Output "  Ratio >= 1.0: $above1"
Write-Output "  Ratio < 1.0: $below1"
Write-Output ""

# Total uploaded
$totalUploaded = ($torrents | Measure-Object -Property uploaded -Sum).Sum
$totalDownloaded = ($torrents | Measure-Object -Property downloaded -Sum).Sum
$overallRatio = if ($totalDownloaded -gt 0) { [math]::Round($totalUploaded / $totalDownloaded, 2) } else { 0 }

Write-Output "=== Overall ==="
Write-Output "  Total downloaded: $([math]::Round($totalDownloaded / 1GB, 1)) GB"
Write-Output "  Total uploaded: $([math]::Round($totalUploaded / 1GB, 1)) GB"
Write-Output "  Overall ratio: $overallRatio"
Write-Output ""

# Current settings
$prefs = Invoke-RestMethod -Uri "$qbtUrl/api/v2/app/preferences" -WebSession $session
Write-Output "=== Settings ==="
Write-Output "  Max ratio: $($prefs.max_ratio)"
Write-Output "  Max seed time: $($prefs.max_seeding_time) min"
Write-Output "  Max active uploads: $($prefs.max_active_uploads)"

# Transfer
$transfer = Invoke-RestMethod -Uri "$qbtUrl/api/v2/transfer/info" -WebSession $session
Write-Output ""
Write-Output "=== Current Upload Speed ==="
Write-Output "  Upload: $([math]::Round($transfer.up_info_speed / 1KB, 0)) KB/s"
