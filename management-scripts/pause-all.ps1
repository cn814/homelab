$qbtUrl = "http://localhost:8090"
# Set alternative speed limits to near-zero and enable them
$json = '{"alt_dl_limit":1,"alt_up_limit":1}'
Invoke-WebRequest -Uri "$qbtUrl/api/v2/app/setPreferences" -Method POST -Body "json=$json" -UseBasicParsing -ContentType "application/x-www-form-urlencoded" -TimeoutSec 10 | Out-Null
# Check current mode
$mode = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/transfer/speedLimitsMode" -UseBasicParsing -TimeoutSec 10).Content
if ($mode -ne "1") {
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/transfer/toggleSpeedLimitsMode" -Method POST -UseBasicParsing -TimeoutSec 10 | Out-Null
}
Write-Output "Speed limits ON - bandwidth throttled to ~0. Run resume-all.ps1 when done streaming."
