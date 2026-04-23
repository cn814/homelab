$qbtUrl = "http://localhost:8090"
$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json

$stalled = $torrents | Where-Object { $_.state -eq "stalledDL" }
$now = [int](Get-Date -UFormat %s)

Write-Output "=== Stalled Torrents: $($stalled.Count) ==="
Write-Output ""

# Group by progress
$noProgress = $stalled | Where-Object { $_.progress -eq 0 }
$partial = $stalled | Where-Object { $_.progress -gt 0 -and $_.progress -lt 1 }
$complete = $stalled | Where-Object { $_.progress -eq 1 }

Write-Output "--- 0% progress (no data received): $($noProgress.Count) ---"
foreach ($t in ($noProgress | Sort-Object added_on)) {
    $age = [math]::Round(($now - $t.added_on) / 3600, 1)
    $seeds = $t.num_complete
    $peers = $t.num_incomplete
    Write-Output "  [$($age)h] Seeds:$seeds Peers:$peers  $($t.name.Substring(0, [Math]::Min(80, $t.name.Length)))"
}

Write-Output ""
Write-Output "--- Partial progress: $($partial.Count) ---"
foreach ($t in ($partial | Sort-Object progress)) {
    $pct = [math]::Round($t.progress * 100, 1)
    $age = [math]::Round(($now - $t.added_on) / 3600, 1)
    $seeds = $t.num_complete
    $peers = $t.num_incomplete
    $dlSpeed = [math]::Round($t.dlspeed / 1KB, 0)
    Write-Output "  [$pct%] [$($age)h] Seeds:$seeds Peers:$peers Speed:${dlSpeed}KB/s  $($t.name.Substring(0, [Math]::Min(70, $t.name.Length)))"
}

Write-Output ""
Write-Output "--- 100% (stuck completing): $($complete.Count) ---"
foreach ($t in $complete) {
    Write-Output "  $($t.name.Substring(0, [Math]::Min(80, $t.name.Length)))"
}

Write-Output ""
Write-Output "=== Summary ==="
$total = $torrents.Count
$downloading = ($torrents | Where-Object { $_.state -eq "downloading" }).Count
$queued = ($torrents | Where-Object { $_.state -match "queued" }).Count
$seeding = ($torrents | Where-Object { $_.state -match "uploading|stalledUP|queuedUP" }).Count
Write-Output "  Total torrents: $total"
Write-Output "  Downloading: $downloading"
Write-Output "  Stalled DL: $($stalled.Count)"
Write-Output "  Queued: $queued"
Write-Output "  Seeding: $seeding"
