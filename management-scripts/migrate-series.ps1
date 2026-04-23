# Migrate biggest series from /data/TV (D:) to /data2/TV (E:)
# This frees up D: drive space so remaining series can continue importing

$apiKey = "2ac6994b6a224d5d84ebd4c7abd7381c"
$headers = @{"X-Api-Key"=$apiKey; "Content-Type"="application/json"}

# Get all series on D:
$series = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 60
$onDataTV = $series | Where-Object { $_.path -like "/data/TV*" }
$sorted = $onDataTV | Sort-Object -Property @{E={$_.statistics.sizeOnDisk}} -Descending

# Move the top 6 biggest series (with files)
$toMove = $sorted | Select-Object -First 6
$totalGB = [Math]::Round(($toMove | ForEach-Object { $_.statistics.sizeOnDisk } | Measure-Object -Sum).Sum / 1GB, 0)
Write-Output "=== Moving 6 largest series to E: (~$totalGB GB to free) ==="

foreach ($s in $toMove) {
    $oldPath = $s.path
    $folderName = $oldPath.Replace("/data/TV/", "")
    $newPath = "/data2/TV/$folderName"
    $sizeGB = [Math]::Round($s.statistics.sizeOnDisk / 1GB, 1)

    Write-Output ""
    Write-Output "[$($s.title)] $sizeGB GB"
    Write-Output "  $oldPath -> $newPath"

    $s.path = $newPath
    $s.rootFolderPath = "/data2/TV"
    $body = $s | ConvertTo-Json -Depth 10 -Compress

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series/$($s.id)?moveFiles=true" -Method PUT -Headers $headers -Body $body -TimeoutSec 1800
        $sw.Stop()
        $mins = [Math]::Round($sw.Elapsed.TotalMinutes, 1)
        Write-Output "  Done in $mins min"
    } catch {
        $sw.Stop()
        Write-Output "  FAILED after $([Math]::Round($sw.Elapsed.TotalMinutes, 1)) min: $($_.Exception.Message)"
    }

    # Check free space after each move
    $rf = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/rootfolder" -Headers @{"X-Api-Key"=$apiKey}
    $dFree = ($rf | Where-Object { $_.path -eq "/data/TV" }).freeSpace / 1GB
    $eFree = ($rf | Where-Object { $_.path -eq "/data2/TV" }).freeSpace / 1GB
    Write-Output "  D: free: $([Math]::Round($dFree, 1)) GB | E: free: $([Math]::Round($eFree, 1)) GB"
}

Write-Output ""
Write-Output "=== Migration Complete ==="
Write-Output "Remaining 127 series stay on D: with freed space."
Write-Output "New series should be added with root folder /data2/TV (E:)."
