$qbtUrl = "http://localhost:8090"
$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
$now = [int](Get-Date -UFormat %s)

$meta = $torrents | Where-Object { $_.state -eq "metaDL" }
Write-Output "=== Stuck on Metadata: $($meta.Count) ==="
Write-Output ""
foreach ($t in ($meta | Sort-Object added_on)) {
    $age = [math]::Round(($now - $t.added_on) / 3600, 1)
    Write-Output "  [$($age)h ago] $($t.name.Substring(0, [Math]::Min(90, $t.name.Length)))"
}

# Also check for any other unusual states
$states = $torrents | Group-Object state | Sort-Object Count -Descending
Write-Output ""
Write-Output "=== All States ==="
foreach ($s in $states) {
    Write-Output "  $($s.Name): $($s.Count)"
}
