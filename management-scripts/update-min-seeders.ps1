param(
    [int]$MinSeeders = 3
)

$radarrUrl = "http://localhost:7878"
$radarrKey = "a63000fb63a240a8bcb5e7d750926379"
$sonarrUrl = "http://localhost:8989"
$sonarrKey = "2ac6994b6a224d5d84ebd4c7abd7381c"

function Update-SingleIndexer($url, $apiKey, $id, $minSeeders) {
    $idx = Invoke-RestMethod -Uri "$url/api/v3/indexer/$id" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 15
    $name = $idx.name
    $fields = @($idx.fields)

    $found = $false
    for ($j = 0; $j -lt $fields.Count; $j++) {
        if ($fields[$j].name -eq "minimumSeeders") {
            $found = $true
            $current = $fields[$j].value
            if ($current -eq $minSeeders) {
                return "${name}: already $minSeeders"
            }
            $fields[$j].value = $minSeeders
            $body = $idx | ConvertTo-Json -Depth 10 -Compress
            try {
                Invoke-RestMethod -Uri "$url/api/v3/indexer/$id" -Method PUT -Headers @{"X-Api-Key"=$apiKey; "Content-Type"="application/json"} -Body $body -TimeoutSec 15 | Out-Null
                return "${name}: ${current} -> $minSeeders"
            } catch {
                return "${name}: FAILED"
            }
        }
    }
    if (-not $found) { return "${name}: no minimumSeeders field" }
}

# Radarr
Write-Output "=== Radarr ==="
$radarrIds = @(5,6,9,7,12,11,3,13,10,8,1)
foreach ($id in $radarrIds) {
    try {
        $result = Update-SingleIndexer $radarrUrl $radarrKey $id $MinSeeders
        Write-Output "  $result"
    } catch {
        Write-Output "  ID $id`: ERROR - $($_.Exception.Message)"
    }
}

# Sonarr
Write-Output ""
Write-Output "=== Sonarr ==="
try {
    $sonarrIndexers = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/indexer" -Headers @{"X-Api-Key"=$sonarrKey} -TimeoutSec 30
    $sonarrIds = @($sonarrIndexers | ForEach-Object { $_.id })
    foreach ($id in $sonarrIds) {
        try {
            $result = Update-SingleIndexer $sonarrUrl $sonarrKey $id $MinSeeders
            Write-Output "  $result"
        } catch {
            Write-Output "  ID $id`: ERROR - $($_.Exception.Message)"
        }
    }
} catch {
    Write-Output "  Sonarr API unavailable (busy with search) - try again later"
}
