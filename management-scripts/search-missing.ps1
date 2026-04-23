# Search for missing media in Sonarr and Radarr
# Run this script to trigger searches for all missing TV episodes and movies

$SonarrUrl = "http://localhost:8989"
$SonarrApiKey = "2ac6994b6a224d5d84ebd4c7abd7381c"

$RadarrUrl = "http://localhost:7878"
$RadarrApiKey = "a63000fb63a240a8bcb5e7d750926379"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Trigger Sonarr missing episode search
try {
    $body = @{ name = "MissingEpisodeSearch" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$SonarrUrl/api/v3/command" -Method Post -Body $body -ContentType "application/json" -Headers @{ "X-Api-Key" = $SonarrApiKey }
    Write-Host "[$timestamp] Sonarr: Missing episode search triggered (ID: $($response.id))"
} catch {
    Write-Host "[$timestamp] Sonarr: Failed to trigger search - $_"
}

# Trigger Radarr missing movie search
try {
    $body = @{ name = "MissingMoviesSearch" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$RadarrUrl/api/v3/command" -Method Post -Body $body -ContentType "application/json" -Headers @{ "X-Api-Key" = $RadarrApiKey }
    Write-Host "[$timestamp] Radarr: Missing movie search triggered (ID: $($response.id))"
} catch {
    Write-Host "[$timestamp] Radarr: Failed to trigger search - $_"
}
