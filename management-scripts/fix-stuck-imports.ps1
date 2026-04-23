$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$sh = @{ "X-Api-Key" = $sonarrApi; "Content-Type" = "application/json" }
$rh = @{ "X-Api-Key" = $radarrApi; "Content-Type" = "application/json" }

# ============================================================
# ISSUE 1: ER episodes - "www.UIndex.org" prefix causing title mismatch
# Fix: Rename download folders to strip the prefix
# ============================================================
Write-Output "=== Fixing ER download folder names ==="
$erFolders = Get-ChildItem "E:\Downloads" -Directory | Where-Object { $_.Name -match "^www\.UIndex\.org.*ER S\d" }
foreach ($f in $erFolders) {
    $newName = $f.Name -replace "^www\.UIndex\.org\s*-\s*", ""
    $newPath = Join-Path $f.Parent.FullName $newName
    if (-not (Test-Path $newPath)) {
        Rename-Item -Path $f.FullName -NewName $newName
        Write-Output "  Renamed: $($f.Name) -> $newName"
    } else {
        Write-Output "  Already exists: $newName"
    }
}

# Also fix Mythbusters with same prefix
$mythFolders = Get-ChildItem "E:\Downloads" -Directory | Where-Object { $_.Name -match "^www\.UIndex\.org" }
foreach ($f in $mythFolders) {
    $newName = $f.Name -replace "^www\.UIndex\.org\s*-\s*", ""
    $newPath = Join-Path $f.Parent.FullName $newName
    if (-not (Test-Path $newPath)) {
        Rename-Item -Path $f.FullName -NewName $newName
        Write-Output "  Renamed: $($f.Name) -> $newName"
    } else {
        Write-Output "  Already exists: $newName"
    }
}

# ============================================================
# ISSUE 2: Little Mermaid - duplicate TMDB match
# Fix: Remove from queue with blocklist=false, then manually import
# ============================================================
Write-Output ""
Write-Output "=== Fixing Little Mermaid duplicate match ==="
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownMovieItems=true" -Headers @{ "X-Api-Key" = $radarrApi } -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.title -match "Little.Mermaid.2023") {
            # Find the correct movie (TMDB 447277 is the Disney live-action)
            $movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{ "X-Api-Key" = $radarrApi } -TimeoutSec 60
            $mermaid = $movies | Where-Object { $_.title -match "Little Mermaid" -and $_.year -eq 2023 }
            if ($mermaid) {
                Write-Output "  Found movie: $($mermaid.title) (TMDB: $($mermaid.tmdbId))"
                # Trigger manual import
                $importBody = @{
                    name = "DownloadedMoviesScan"
                    path = "/data2/Downloads/The.Little.Mermaid.2023.1080p.BluRay.DDP.5.1.H.265.-iVy"
                    downloadClientId = $item.downloadId
                    importMode = "move"
                    movieId = $mermaid.id
                } | ConvertTo-Json
                try {
                    Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Method POST -Headers $rh -Body $importBody -TimeoutSec 30 | Out-Null
                    Write-Output "  Triggered manual import scan"
                } catch {
                    Write-Output "  Import trigger error: $($_.Exception.Message)"
                }
            } else {
                Write-Output "  Little Mermaid (2023) not found in library"
            }
        }
    }
    $page++
} while ($q.records.Count -eq 500)

# ============================================================
# ISSUE 3: Trigger rescan for everything else
# Selma, Incredibles, Furious 7 - permissions now fixed
# Blaze, MythBusters, Modern Marvels, Phineas and Ferb - may just need rescan
# ============================================================
Write-Output ""
Write-Output "=== Triggering import rescans ==="

$radarrScan = '{"name":"DownloadedMoviesScan"}'
Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Method POST -Headers $rh -Body $radarrScan -TimeoutSec 30 | Out-Null
Write-Output "  Radarr: Download scan triggered"

$sonarrScan = '{"name":"DownloadedEpisodesScan"}'
Invoke-RestMethod -Uri "$sonarrUrl/api/v3/command" -Method POST -Headers $sh -Body $sonarrScan -TimeoutSec 30 | Out-Null
Write-Output "  Sonarr: Download scan triggered"

Write-Output ""
Write-Output "Done. Check Sonarr/Radarr Activity queue in a few minutes."
