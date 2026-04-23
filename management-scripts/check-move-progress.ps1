$d = Get-PSDrive D
$e = Get-PSDrive E
Write-Output "D: Free: $([Math]::Round($d.Free/1GB, 1)) GB / Used: $([Math]::Round($d.Used/1GB, 1)) GB"
Write-Output "E: Free: $([Math]::Round($e.Free/1GB, 1)) GB / Used: $([Math]::Round($e.Used/1GB, 1)) GB"

$folders = @("Gold Rush","Friends","NOVA","How It's Made","Expedition Unknown","Smallville")
Write-Output ""
foreach ($f in $folders) {
    $dPath = "D:\TV\$f"
    $ePath = "E:\TV\$f"
    $dExists = Test-Path $dPath
    $eExists = Test-Path $ePath
    $dSize = 0; $eSize = 0
    if ($dExists) { $dSize = [Math]::Round((Get-ChildItem $dPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 1) }
    if ($eExists) { $eSize = [Math]::Round((Get-ChildItem $ePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 1) }
    $status = if (-not $dExists -or $dSize -eq 0) { "DONE" } elseif ($eSize -gt 0) { "IN PROGRESS" } else { "PENDING" }
    Write-Output "$status | $f | D: $dSize GB | E: $eSize GB"
}
