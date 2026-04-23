param(
    [ValidateSet("on","off")]
    [string]$State = "off"
)

$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"

$upgradeAllowed = if ($State -eq "on") { $true } else { $false }

foreach ($svc in @(
    @{ Name = "Sonarr"; Url = $sonarrUrl; Api = $sonarrApi },
    @{ Name = "Radarr"; Url = $radarrUrl; Api = $radarrApi }
)) {
    $headers = @{ "X-Api-Key" = $svc.Api; "Content-Type" = "application/json" }
    $profiles = Invoke-RestMethod -Uri "$($svc.Url)/api/v3/qualityprofile" -Headers @{ "X-Api-Key" = $svc.Api }

    foreach ($p in $profiles) {
        $p.upgradeAllowed = $upgradeAllowed
        $body = $p | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "$($svc.Url)/api/v3/qualityprofile/$($p.id)" -Method PUT -Headers $headers -Body $body | Out-Null
        Write-Output "$($svc.Name) - $($p.name): upgrades $State"
    }
}

Write-Output ""
if ($State -eq "off") {
    Write-Output "Upgrades PAUSED. Only missing files will be downloaded."
    Write-Output "To re-enable: toggle-upgrades.ps1 -State on"
} else {
    Write-Output "Upgrades ENABLED. Higher quality replacements will be downloaded."
}
