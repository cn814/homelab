$prowlarrUrl = "http://localhost:9696"
$prowlarrApi = "adfe7f603b3542a09eb2ebd09ad51a16"
$h = @{ "X-Api-Key" = $prowlarrApi }

Write-Output "=== Current Indexers ==="
$indexers = Invoke-RestMethod -Uri "$prowlarrUrl/api/v1/indexer" -Headers $h -TimeoutSec 30
foreach ($idx in $indexers) {
    Write-Output "  $($idx.name) (ID: $($idx.id)) - Enabled: $($idx.enable) - Protocol: $($idx.protocol)"
}

Write-Output ""
Write-Output "=== Available Indexer Schemas (searching for targets) ==="
$schemas = Invoke-RestMethod -Uri "$prowlarrUrl/api/v1/indexer/schema" -Headers $h -TimeoutSec 60
$targets = $schemas | Where-Object { $_.name -match "Nyaa|RARBG|RuTracker|Rutracker" }
foreach ($s in $targets) {
    Write-Output "  $($s.name) - implementation: $($s.implementation) - protocol: $($s.protocol)"
}
