$qbtUrl = "http://localhost:8090"
$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json

$missing = $torrents | Where-Object { $_.state -eq "missingFiles" }
Write-Output "=== Missing Files: $($missing.Count) ==="
foreach ($t in $missing) {
    Write-Output "  $($t.name)"
    Write-Output "    Save path: $($t.save_path)"
}
