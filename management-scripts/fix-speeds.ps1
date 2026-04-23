$qbtUrl = "http://localhost:8090"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$json = '{"max_active_uploads":8,"max_seeding_time":180,"max_ratio":1.0,"max_ratio_enabled":true,"max_seeding_time_enabled":true}'

Invoke-WebRequest -Uri "$qbtUrl/api/v2/app/setPreferences" -Method POST -Body "json=$json" -WebSession $session -UseBasicParsing -ContentType "application/x-www-form-urlencoded" | Out-Null

$prefs = Invoke-RestMethod -Uri "$qbtUrl/api/v2/app/preferences" -WebSession $session
Write-Output "=== Updated ==="
Write-Output "  Max active uploads: $($prefs.max_active_uploads)"
Write-Output "  Max seed time: $($prefs.max_seeding_time) min"
Write-Output "  Max ratio: $($prefs.max_ratio)"
