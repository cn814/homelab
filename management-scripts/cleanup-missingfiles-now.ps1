$qbtUrl = "http://localhost:8090"
$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json

$missing = $torrents | Where-Object { $_.state -eq "missingFiles" }
Write-Output "Removing $($missing.Count) orphaned torrents (missingFiles):"
foreach ($t in $missing) {
    Write-Output "  $($t.name)"
}

if ($missing.Count -gt 0) {
    $hashes = ($missing | ForEach-Object { $_.hash }) -join "|"
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=false" -UseBasicParsing -TimeoutSec 60 | Out-Null
    Write-Output ""
    Write-Output "Removed $($missing.Count) orphaned torrents"
}
