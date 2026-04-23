# Sync qBittorrent port with Gluetun forwarded port
# This script automatically updates qBittorrent when ProtonVPN changes the forwarded port

$ErrorActionPreference = "Stop"
$logFile = "c:\jellyfin-stack\logs\port-sync.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $logFile -Append
}

try {
    # Get forwarded port from Gluetun control server API (more reliable than log parsing)
    $portResponse = docker exec gluetun sh -c "wget -qO- http://localhost:8000/v1/openvpn/portforwarded" 2>&1
    $portInfo = $portResponse | ConvertFrom-Json
    $forwardedPort = $portInfo.port

    if (-not $forwardedPort -or $forwardedPort -eq 0) {
        Write-Log "ERROR: Could not get forwarded port from Gluetun API (got: $portResponse)"
        exit 1
    }

    # Get qBittorrent's current listening port
    $response = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/app/preferences" -Method Get -TimeoutSec 10
    $currentPort = $response.listen_port

    Write-Log "Gluetun forwarded port: $forwardedPort | qBittorrent port: $currentPort"

    # Check if ports match
    if ($forwardedPort -eq $currentPort) {
        Write-Log "Ports match - no action needed"
        exit 0
    }

    # Ports don't match - update qBittorrent via API (not config file, which gets overwritten on shutdown)
    Write-Log "Port mismatch detected! Updating qBittorrent from $currentPort to $forwardedPort"

    # Log in to qBittorrent API
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body @{
        username = $env:QBIT_USER; password = $env:QBIT_PASS
    } -WebSession $session -UseBasicParsing -TimeoutSec 10 | Out-Null

    # Update port via API (persists correctly without restart)
    $json = "{`"listen_port`": $forwardedPort}"
    Invoke-WebRequest -Uri "http://localhost:8090/api/v2/app/setPreferences" -Method POST -Body "json=$json" -WebSession $session -UseBasicParsing -TimeoutSec 10 | Out-Null

    Write-Log "Port updated via API"

    # Verify the change
    Start-Sleep -Seconds 2
    $response = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/app/preferences" -Method Get -TimeoutSec 10
    $newPort = $response.listen_port

    if ($newPort -eq $forwardedPort) {
        Write-Log "SUCCESS: qBittorrent now listening on port $newPort"
    } else {
        Write-Log "WARNING: qBittorrent port is $newPort, expected $forwardedPort"
    }

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
