$qbtUrl = "http://localhost:8090"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

# Current speeds
$transfer = Invoke-RestMethod -Uri "$qbtUrl/api/v2/transfer/info" -WebSession $session
Write-Output "=== Current Transfer ==="
Write-Output "  Download: $([math]::Round($transfer.dl_info_speed / 1MB, 2)) MB/s"
Write-Output "  Upload: $([math]::Round($transfer.up_info_speed / 1MB, 2)) MB/s"
Write-Output ""

# Check disk info from qBittorrent
Write-Output "=== Download Locations ==="
$torrents = Invoke-RestMethod -Uri "$qbtUrl/api/v2/torrents/info" -WebSession $session
$dl = $torrents | Where-Object { $_.state -match "downloading|stalledDL" }
$paths = $dl | Group-Object save_path | Sort-Object Count -Descending
foreach ($p in $paths) {
    Write-Output "  $($p.Name): $($p.Count) torrents"
}

Write-Output ""
Write-Output "=== Drive Info ==="
# Check D: and E: drive types and free space
Get-WmiObject Win32_DiskDrive | ForEach-Object {
    $disk = $_
    $model = $disk.Model
    $mediaType = $disk.MediaType
    $size = [math]::Round($disk.Size / 1GB, 0)
    Write-Output "  $model ($size GB) - $mediaType"
}

Write-Output ""
Write-Output "=== Free Space ==="
Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $free = [math]::Round($_.FreeSpace / 1GB, 1)
    $total = [math]::Round($_.Size / 1GB, 1)
    $pct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
    Write-Output "  $($_.DeviceID) $free GB free / $total GB ($pct%)"
}

Write-Output ""
Write-Output "=== Drive Type (SSD vs HDD) ==="
Get-PhysicalDisk | ForEach-Object {
    Write-Output "  $($_.FriendlyName) - $($_.MediaType) - $([math]::Round($_.Size / 1GB, 0)) GB"
}
