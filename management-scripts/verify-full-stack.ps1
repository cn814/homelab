Write-Output "=== Full Stack Verification ==="
Write-Output ""

# 1. Jellyfin native
Write-Output "1. Jellyfin (native Windows):"
$jfStatus = (Get-Service JellyfinServer).Status
Write-Output "   Service: $jfStatus"
try {
    $info = Invoke-RestMethod -Uri "http://localhost:8096/System/Info/Public" -TimeoutSec 5
    Write-Output "   Server: $($info.ServerName) v$($info.Version)"
    Write-Output "   OK"
} catch {
    Write-Output "   FAILED: $($_.Exception.Message)"
}

# 2. Caddy proxy
Write-Output ""
Write-Output "2. Caddy reverse proxy (port 8080 -> 8096):"
try {
    $r = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Write-Output "   Status: $($r.StatusCode) - OK"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -gt 0) {
        Write-Output "   Status: $code (response received - proxy working)"
    } else {
        Write-Output "   FAILED: $($_.Exception.Message)"
    }
}

# 3. Jellyseerr
Write-Output ""
Write-Output "3. Jellyseerr:"
try {
    $r = Invoke-WebRequest -Uri "http://localhost:5055/api/v1/status" -UseBasicParsing -TimeoutSec 5
    Write-Output "   Status: $($r.StatusCode) - OK"
} catch {
    Write-Output "   FAILED: $($_.Exception.Message)"
}

# 4. Docker containers
Write-Output ""
Write-Output "4. Docker containers:"
$containers = docker ps --format "{{.Names}}: {{.Status}}" 2>&1
foreach ($c in $containers) {
    Write-Output "   $c"
}

Write-Output ""
Write-Output "5. Hardware transcoding:"
try {
    $apiKey = "f9407b9c41714b209e69a497fdcb33f6"
    $sysInfo = Invoke-RestMethod -Uri "http://localhost:8096/System/Info" -Headers @{"X-Emby-Token"=$apiKey} -TimeoutSec 5
    Write-Output "   Transcoding path: $($sysInfo.TranscodingTempPath)"
} catch {
    Write-Output "   Could not query (need API key)"
}
