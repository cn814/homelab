$radarrUrl = "http://localhost:7878"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$h = @{ "X-Api-Key" = $radarrApi }

$movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers $h -TimeoutSec 120
$mermaids = $movies | Where-Object { $_.title -match "Little Mermaid" }

foreach ($m in $mermaids) {
    Write-Output "$($m.title) ($($m.year))"
    Write-Output "  ID: $($m.id) | TMDB: $($m.tmdbId)"
    Write-Output "  HasFile: $($m.hasFile)"
    Write-Output "  Path: $($m.path)"
    if ($m.movieFile) {
        Write-Output "  File: $($m.movieFile.relativePath)"
        Write-Output "  Quality: $($m.movieFile.quality.quality.name)"
    }
    Write-Output ""
}
