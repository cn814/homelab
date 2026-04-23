$radarrUrl = "http://localhost:7878"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$h = @{ "X-Api-Key" = $radarrApi; "Content-Type" = "application/json" }

# Trigger a disk scan for The Little Mermaid to pick up the existing file
$movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{ "X-Api-Key" = $radarrApi } -TimeoutSec 120
$mermaid = $movies | Where-Object { $_.title -match "Little Mermaid" -and $_.year -eq 2023 }

if ($mermaid) {
    Write-Output "Movie: $($mermaid.title) (ID: $($mermaid.id), TMDB: $($mermaid.tmdbId))"
    Write-Output "HasFile: $($mermaid.hasFile)"
    Write-Output "Path: $($mermaid.path)"

    # Update path to where the file actually is (D: drive, not E:)
    if ($mermaid.path -ne "/data/Movies/The Little Mermaid (2023)") {
        Write-Output "Updating path to /data/Movies/The Little Mermaid (2023)..."
        $mermaid.path = "/data/Movies/The Little Mermaid (2023)"
        $body = $mermaid | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie/$($mermaid.id)" -Method PUT -Headers $h -Body $body -TimeoutSec 30 | Out-Null
    }

    # Trigger rescan
    $scanBody = @{ name = "RescanMovie"; movieId = $mermaid.id } | ConvertTo-Json
    Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Method POST -Headers $h -Body $scanBody -TimeoutSec 30 | Out-Null
    Write-Output "Triggered disk rescan for Little Mermaid."
}
