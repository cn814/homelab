$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri 'http://localhost:8090/api/v2/auth/login' -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$info = Invoke-RestMethod -Uri 'http://localhost:8090/api/v2/transfer/info' -WebSession $session
$prefs = Invoke-RestMethod -Uri 'http://localhost:8090/api/v2/app/preferences' -WebSession $session

Write-Output "=== qBittorrent Network ==="
Write-Output "  Download speed: $([math]::Round($info.dl_info_speed / 1MB, 2)) MB/s"
Write-Output "  DHT nodes: $($info.dht_nodes)"
Write-Output "  Connection status: $($info.connection_status)"
Write-Output "  External IP: $($info.last_external_address_v4)"
Write-Output "  Listening port: $($prefs.listen_port)"
Write-Output "  Interface bound: $($prefs.current_network_interface)"
Write-Output ""

# Check VPN tunnel is still up
Write-Output "=== VPN ==="
$vpnIp = docker exec gluetun sh -c "wget -qO- https://ipinfo.io/ip 2>/dev/null" 2>&1
Write-Output "  VPN IP: $vpnIp"

$fwdPort = docker exec gluetun sh -c "wget -qO- http://127.0.0.1:8000/v1/openvpn/portforwarded 2>/dev/null" 2>&1
Write-Output "  Forwarded port: $fwdPort"
Write-Output ""

# Check Windows network adapters
Write-Output "=== Windows Network Adapters ==="
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
    $speed = if ($_.LinkSpeed) { $_.LinkSpeed } else { "unknown" }
    Write-Output "  $($_.Name): $($_.InterfaceDescription) - $speed"
}
