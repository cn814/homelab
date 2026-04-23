$prowlarrUrl = "http://localhost:9696"
$prowlarrApi = "adfe7f603b3542a09eb2ebd09ad51a16"
$h = @{ "X-Api-Key" = $prowlarrApi; "Content-Type" = "application/json" }

$schemas = Invoke-RestMethod -Uri "$prowlarrUrl/api/v1/indexer/schema" -Headers @{ "X-Api-Key" = $prowlarrApi } -TimeoutSec 60

# Indexers to add - good public ones for movies/TV
$toAdd = @("RuTracker.RU", "Knaben", "TorrentDownload", "Torrent Downloads", "BitSearch")

foreach ($name in $toAdd) {
    Write-Output "Adding $name..."
    $schema = $schemas | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $schema) {
        Write-Output "  Schema not found, skipping."
        continue
    }

    $schema.enable = $true
    $schema.appProfileId = 1
    $schema.priority = 25

    # Strip Cyrillic for RuTracker to help Sonarr/Radarr matching
    if ($name -match "RuTracker") {
        foreach ($f in $schema.fields) {
            if ($f.name -eq "stripcyrillic") { $f.value = $true }
        }
    }

    $body = $schema | ConvertTo-Json -Depth 20
    try {
        $result = Invoke-RestMethod -Uri "$prowlarrUrl/api/v1/indexer" -Method POST -Headers $h -Body $body -TimeoutSec 30
        Write-Output "  Added (ID: $($result.id))"
    } catch {
        $err = $_.ErrorDetails.Message
        if (-not $err) { $err = $_.Exception.Message }
        Write-Output "  Error: $err"
    }
}

Write-Output ""
Write-Output "=== Updated Indexer List ==="
$indexers = Invoke-RestMethod -Uri "$prowlarrUrl/api/v1/indexer" -Headers @{ "X-Api-Key" = $prowlarrApi } -TimeoutSec 30
foreach ($idx in ($indexers | Sort-Object name)) {
    Write-Output "  $($idx.name) - Enabled: $($idx.enable)"
}
Write-Output ""
Write-Output "Total: $($indexers.Count) indexers"
