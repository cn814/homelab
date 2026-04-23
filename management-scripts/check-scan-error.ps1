# Check Sonarr logs for errors around the time of the failed scan
Write-Output "=== Sonarr Log Errors ==="
$logs = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/log?pageSize=100&sortKey=time&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
$errors = $logs.records | Where-Object { $_.level -eq "error" -or $_.level -eq "fatal" }
Write-Output "Error/Fatal entries: $($errors.Count)"
$errors | ForEach-Object {
    Write-Output "  [$($_.level)] $($_.time): $($_.message)"
    if ($_.exception) {
        $excLen = [Math]::Min(500, $_.exception.Length)
        Write-Output "    Exception: $($_.exception.Substring(0, $excLen))"
    }
}

# Check all log entries around the scan time
Write-Output ""
Write-Output "=== Log entries containing 'Download' or 'import' or 'scan' ==="
$scanLogs = $logs.records | Where-Object {
    $_.message -like "*DownloadedEpisodesScan*" -or
    $_.message -like "*Failed to import*" -or
    $_.message -like "*import failed*" -or
    $_.message -like "*Cannot import*" -or
    $_.message -like "*download path*"
}
Write-Output "Found: $($scanLogs.Count)"
$scanLogs | ForEach-Object {
    Write-Output "  [$($_.level)] $($_.time): $($_.message)"
    if ($_.exception) {
        $excLen = [Math]::Min(500, $_.exception.Length)
        Write-Output "    Exception: $($_.exception.Substring(0, $excLen))"
    }
}

# Also try the log file directly
Write-Output ""
Write-Output "=== Container log file (last import-related entries) ==="
$logContent = docker exec sonarr cat /config/logs/sonarr.txt 2>&1
$lines = $logContent -split "`n"
$importLines = $lines | Where-Object { $_ -like "*DownloadedEpisodes*" -or $_ -like "*Failed to import*" -or $_ -like "*import path*" }
Write-Output "Found: $($importLines.Count)"
$importLines | Select-Object -Last 10 | ForEach-Object {
    Write-Output "  $_"
}
