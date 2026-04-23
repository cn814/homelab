$radarrUrl = "http://localhost:7878"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$h = @{ "X-Api-Key" = $radarrApi }

# Find both Little Mermaid entries
$movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers $h -TimeoutSec 60
$mermaids = $movies | Where-Object { $_.title -match "Little Mermaid" -and $_.year -eq 2023 }

Write-Output "Found $($mermaids.Count) Little Mermaid (2023) entries:"
foreach ($m in $mermaids) {
    Write-Output "  ID: $($m.id) | TMDB: $($m.tmdbId) | IMDB: $($m.imdbId) | HasFile: $($m.hasFile) | Path: $($m.path)"
}

# TMDB 447277 is the main Disney live-action one, 1136767 is the duplicate
# Remove the duplicate (1136767)
$duplicate = $mermaids | Where-Object { $_.tmdbId -eq 1136767 }
$keep = $mermaids | Where-Object { $_.tmdbId -eq 447277 }

if ($duplicate) {
    Write-Output ""
    Write-Output "Removing duplicate (TMDB 1136767, ID $($duplicate.id))..."
    Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie/$($duplicate.id)?deleteFiles=false&addImportExclusion=false" -Method DELETE -Headers $h -TimeoutSec 30 | Out-Null
    Write-Output "  Removed."
}

if ($keep) {
    Write-Output "Keeping: TMDB $($keep.tmdbId), ID $($keep.id)"
}

# Also clear stuck Little Mermaid queue items
Write-Output ""
Write-Output "Clearing Little Mermaid queue items..."
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $h -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.title -match "Little.Mermaid.2023") {
            try {
                Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue/$($item.id)?removeFromClient=false&blocklist=false&skipRedownload=false" -Method DELETE -Headers $h -TimeoutSec 30 | Out-Null
                Write-Output "  Removed queue item: $($item.title)"
            } catch {
                Write-Output "  Error: $($_.Exception.Message)"
            }
        }
    }
    $page++
} while ($q.records.Count -eq 500)

# Trigger fresh download scan
Write-Output ""
$rh = @{ "X-Api-Key" = $radarrApi; "Content-Type" = "application/json" }
Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Method POST -Headers $rh -Body '{"name":"DownloadedMoviesScan"}' -TimeoutSec 30 | Out-Null
Write-Output "Triggered Radarr download scan."
