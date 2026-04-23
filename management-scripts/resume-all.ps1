$qbtUrl = "http://localhost:8090"
# Disable alternative speed limits to restore full bandwidth
$mode = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/transfer/speedLimitsMode" -UseBasicParsing -TimeoutSec 10).Content
if ($mode -eq "1") {
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/transfer/toggleSpeedLimitsMode" -Method POST -UseBasicParsing -TimeoutSec 10 | Out-Null
}
Write-Output "Speed limits OFF - full bandwidth restored."
