# Check if prioritize task exists
$task = Get-ScheduledTask -TaskName 'Prioritize Downloads' -ErrorAction SilentlyContinue
if ($task) {
    Write-Output "!! Prioritize Downloads task EXISTS: $($task.State)"
    $info = Get-ScheduledTaskInfo -TaskName 'Prioritize Downloads'
    Write-Output "   Last run: $($info.LastRunTime)"
} else {
    Write-Output "Prioritize Downloads task: GONE (good)"
}

# Check what's actually active in qBittorrent
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri 'http://localhost:8090/api/v2/auth/login' -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$torrents = Invoke-RestMethod -Uri 'http://localhost:8090/api/v2/torrents/info' -WebSession $session
$dl = $torrents | Where-Object { $_.state -in @('downloading','stalledDL','forcedDL','queuedDL','metaDL') }
$active = $dl | Where-Object { $_.dlspeed -gt 0 }
$stalled = $dl | Where-Object { $_.state -eq 'stalledDL' }

$info = Invoke-RestMethod -Uri 'http://localhost:8090/api/v2/transfer/info' -WebSession $session
$speed = [math]::Round($info.dl_info_speed / 1MB, 2)

Write-Output ""
Write-Output "Speed: $speed MB/s"
Write-Output "Queue: $($dl.Count) total, $($active.Count) active, $($stalled.Count) stalled"
Write-Output ""

# Show what's actually downloading
Write-Output "Active transfers:"
foreach ($t in $active | Sort-Object -Property dlspeed -Descending | Select-Object -First 10) {
    $s = [math]::Round($t.dlspeed / 1MB, 2)
    $seeds = $t.num_complete
    $shortName = $t.name
    if ($shortName.Length -gt 50) { $shortName = $shortName.Substring(0, 50) + "..." }
    Write-Output "  $s MB/s | $seeds seeds | $shortName"
}

# Check if any process is hammering qBittorrent API
Write-Output ""
Write-Output "PowerShell processes:"
Get-Process powershell*, pwsh* -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmd -and $cmd -match 'Prioritize|cleanup|dead|remove') {
        Write-Output "  PID $($_.Id): $cmd"
    }
}
