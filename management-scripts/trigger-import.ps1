$radarrUrl = "http://localhost:7878"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$h = @{ "X-Api-Key" = $radarrApi; "Content-Type" = "application/json" }

# Trigger Radarr to process completed downloads
$body = '{"name":"DownloadedMoviesScan"}'
Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Method POST -Headers $h -Body $body -TimeoutSec 30 | Out-Null
Write-Output "Radarr: Triggered completed download scan"

# Trigger Sonarr too
$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$sh = @{ "X-Api-Key" = $sonarrApi; "Content-Type" = "application/json" }
$body = '{"name":"DownloadedEpisodesScan"}'
Invoke-RestMethod -Uri "$sonarrUrl/api/v3/command" -Method POST -Headers $sh -Body $body -TimeoutSec 30 | Out-Null
Write-Output "Sonarr: Triggered completed download scan"
