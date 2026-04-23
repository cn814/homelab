$radarrUrl = "http://localhost:7878"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"
$h = @{ "X-Api-Key" = $radarrApi }

$page = 1
$removed = 0
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500" -Headers $h -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.status -eq "completed") {
            Write-Output "Removing: $($item.title)"
            try {
                Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=false&skipRedownload=true" -Method DELETE -Headers $h -TimeoutSec 30 | Out-Null
                $removed++
            } catch {
                Write-Output "  Error: $($_.Exception.Message)"
            }
        }
    }
    $page++
} while ($q.records.Count -eq 500)

Write-Output ""
Write-Output "Removed $removed completed items from Radarr queue."
