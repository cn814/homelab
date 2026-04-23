$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$h = @{ "X-Api-Key" = $sonarrApi }

# Get episode file IDs for the 3 broken episodes
$series = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Headers $h -TimeoutSec 60

# Family Guy S06E11
$fg = $series | Where-Object { $_.title -match "Family Guy" }
$fgFiles = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episodefile?seriesId=$($fg.id)" -Headers $h -TimeoutSec 60
$fgBroken = $fgFiles | Where-Object { $_.path -match "S06E11.*\.avi" }

# West Wing S07E18 and S07E19
$ww = $series | Where-Object { $_.title -match "West Wing" }
$wwFiles = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episodefile?seriesId=$($ww.id)" -Headers $h -TimeoutSec 60
$wwBroken = $wwFiles | Where-Object { $_.path -match "S7 E18|S7 E19" }

$toDelete = @()
if ($fgBroken) { $toDelete += $fgBroken }
if ($wwBroken) { $toDelete += $wwBroken }

foreach ($f in $toDelete) {
    Write-Output "Deleting: $($f.path)"
    Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episodefile/$($f.id)" -Method DELETE -Headers $h -TimeoutSec 30 | Out-Null
}
Write-Output ""
Write-Output "Deleted $($toDelete.Count) broken files."

# Trigger search for those episodes
Write-Output "Searching for replacements..."
$fgEpisodes = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episode?seriesId=$($fg.id)" -Headers $h -TimeoutSec 60
$s06e11 = $fgEpisodes | Where-Object { $_.seasonNumber -eq 6 -and $_.episodeNumber -eq 11 }

$wwEpisodes = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episode?seriesId=$($ww.id)" -Headers $h -TimeoutSec 60
$s07e18 = $wwEpisodes | Where-Object { $_.seasonNumber -eq 7 -and $_.episodeNumber -eq 18 }
$s07e19 = $wwEpisodes | Where-Object { $_.seasonNumber -eq 7 -and $_.episodeNumber -eq 19 }

$episodeIds = @()
if ($s06e11) { $episodeIds += $s06e11.id }
if ($s07e18) { $episodeIds += $s07e18.id }
if ($s07e19) { $episodeIds += $s07e19.id }

$searchBody = @{
    name = "EpisodeSearch"
    episodeIds = $episodeIds
} | ConvertTo-Json

$searchHeaders = @{ "X-Api-Key" = $sonarrApi; "Content-Type" = "application/json" }
Invoke-RestMethod -Uri "$sonarrUrl/api/v3/command" -Method POST -Headers $searchHeaders -Body $searchBody -TimeoutSec 30 | Out-Null
Write-Output "Search triggered for $($episodeIds.Count) episodes."
