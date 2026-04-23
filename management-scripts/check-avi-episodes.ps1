$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$h = @{ "X-Api-Key" = $sonarrApi }

$series = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Headers $h -TimeoutSec 60

# Check Family Guy
$fg = $series | Where-Object { $_.title -match "Family Guy" }
if ($fg) {
    Write-Output "Family Guy"
    Write-Output "  ID: $($fg.id)"
    Write-Output "  Monitored: $($fg.monitored)"
    Write-Output "  Path: $($fg.path)"
    $episodes = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episode?seriesId=$($fg.id)" -Headers $h -TimeoutSec 60
    $s06e11 = $episodes | Where-Object { $_.seasonNumber -eq 6 -and $_.episodeNumber -eq 11 }
    if ($s06e11) {
        Write-Output "  S06E11: hasFile=$($s06e11.hasFile), monitored=$($s06e11.monitored)"
    }
    Write-Output ""
}

# Check West Wing
$ww = $series | Where-Object { $_.title -match "West Wing" }
if ($ww) {
    Write-Output "The West Wing"
    Write-Output "  ID: $($ww.id)"
    Write-Output "  Monitored: $($ww.monitored)"
    Write-Output "  Path: $($ww.path)"
    $episodes = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episode?seriesId=$($ww.id)" -Headers $h -TimeoutSec 60
    $s07e18 = $episodes | Where-Object { $_.seasonNumber -eq 7 -and $_.episodeNumber -eq 18 }
    $s07e19 = $episodes | Where-Object { $_.seasonNumber -eq 7 -and $_.episodeNumber -eq 19 }
    if ($s07e18) {
        Write-Output "  S07E18: hasFile=$($s07e18.hasFile), monitored=$($s07e18.monitored)"
    }
    if ($s07e19) {
        Write-Output "  S07E19: hasFile=$($s07e19.hasFile), monitored=$($s07e19.monitored)"
    }
    Write-Output ""
}

# Also check how many total AVI files exist
Write-Output "=== AVI files on D: drive ==="
$aviCount = 0
foreach ($ep in (Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episodefile?seriesId=$($fg.id)" -Headers $h -TimeoutSec 60)) {
    if ($ep.path -match "\.avi$") {
        Write-Output "  $($ep.path)"
        $aviCount++
    }
}
foreach ($ep in (Invoke-RestMethod -Uri "$sonarrUrl/api/v3/episodefile?seriesId=$($ww.id)" -Headers $h -TimeoutSec 60)) {
    if ($ep.path -match "\.avi$") {
        Write-Output "  $($ep.path)"
        $aviCount++
    }
}
Write-Output ""
Write-Output "Total AVI files in these 2 series: $aviCount"
