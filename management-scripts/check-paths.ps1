# Check root folders and free space
Write-Output "=== Sonarr Root Folders ==="
$rf = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/rootfolder" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$rf | ForEach-Object {
    Write-Output "  ID: $($_.id) | Path: $($_.path) | Free: $([Math]::Round($_.freeSpace / 1GB, 1)) GB"
}

# Check where Modern Marvels and Mysteries of the Abandoned are assigned
Write-Output ""
Write-Output "=== Series on /data (D:) ==="
$series = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 60
$onData = $series | Where-Object { $_.path -like "/data/TV*" }
$onData2 = $series | Where-Object { $_.path -like "/data2/TV*" }
Write-Output "Series on /data/TV (D:): $($onData.Count)"
Write-Output "Series on /data2/TV (E:): $($onData2.Count)"

# Show D: drive series and their sizes
Write-Output ""
Write-Output "=== Series on D: drive (/data/TV) ==="
$onData | Sort-Object -Property @{E={$_.statistics.sizeOnDisk}} -Descending | ForEach-Object {
    $sizeGB = [Math]::Round($_.statistics.sizeOnDisk / 1GB, 1)
    Write-Output "  $($_.title) - $sizeGB GB ($($_.statistics.episodeFileCount) files) - $($_.path)"
}

# Check D: drive actual free space
Write-Output ""
Write-Output "=== Windows Drive Space ==="
$dDrive = Get-PSDrive D -ErrorAction SilentlyContinue
$eDrive = Get-PSDrive E -ErrorAction SilentlyContinue
if ($dDrive) { Write-Output "  D: Free: $([Math]::Round($dDrive.Free / 1GB, 1)) GB / Used: $([Math]::Round($dDrive.Used / 1GB, 1)) GB" }
if ($eDrive) { Write-Output "  E: Free: $([Math]::Round($eDrive.Free / 1GB, 1)) GB / Used: $([Math]::Round($eDrive.Used / 1GB, 1)) GB" }
