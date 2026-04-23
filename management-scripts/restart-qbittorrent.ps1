# Restart qBittorrent and Gluetun to clear memory leaks
# Should be run every 3 days

$ErrorActionPreference = "Continue"  # Don't stop on errors, we'll handle them
$logFile = "c:\jellyfin-stack\logs\qbittorrent-restart.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $logFile -Append
}

try {
    Write-Log "=== qBittorrent Restart Started ==="

    # Check memory before restart
    $beforeMem = docker stats --no-stream qbittorrent --format "{{.MemUsage}}" 2>&1
    Write-Log "Memory before restart: $beforeMem"

    # Try graceful stop first
    Write-Log "Stopping containers gracefully..."
    docker stop qbittorrent gluetun 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    # Force remove (ignore errors - container might already be gone)
    Write-Log "Removing containers..."
    docker rm -f qbittorrent 2>&1 | Out-Null
    docker rm -f gluetun 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    # Recreate containers (always run this, even if rm failed)
    Write-Log "Starting containers..."
    Set-Location "c:\jellyfin-stack"
    $composeOutput = docker-compose up -d gluetun qbittorrent 2>&1
    Write-Log "Compose output: $composeOutput"

    # Wait for services to be ready
    Write-Log "Waiting for services to start..."
    Start-Sleep -Seconds 30

    # Verify qBittorrent is responding
    $maxAttempts = 6
    $attempt = 0
    $success = $false

    while ($attempt -lt $maxAttempts) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/app/version" -TimeoutSec 5 -ErrorAction Stop
            Write-Log "qBittorrent is responding (version: $response)"
            $success = $true
            break
        } catch {
            $attempt++
            if ($attempt -lt $maxAttempts) {
                Write-Log "Waiting for qBittorrent... (attempt $attempt/$maxAttempts)"
                Start-Sleep -Seconds 10
            }
        }
    }

    if (-not $success) {
        Write-Log "WARNING: qBittorrent did not respond after restart"
        exit 1
    }

    # Check port forwarding
    $portLogs = docker logs gluetun --tail 20 2>&1 | Select-String "port forwarded"
    if ($portLogs) {
        Write-Log "Port forwarding: $($portLogs | Select-Object -Last 1)"
    } else {
        Write-Log "WARNING: Could not verify port forwarding"
    }

    # Check memory after restart
    Start-Sleep -Seconds 5
    $afterMem = docker stats --no-stream qbittorrent --format "{{.MemUsage}}" 2>&1
    Write-Log "Memory after restart: $afterMem"

    Write-Log "=== Restart completed successfully ==="

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
