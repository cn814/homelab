# Overnight move: Gold Rush + Friends only, then fix remaining series paths
# Run with: powershell -ExecutionPolicy Bypass -File c:\jellyfin-stack\scripts\overnight-move.ps1

$logFile = "c:\jellyfin-stack\logs\overnight-move.log"
$null = New-Item -ItemType Directory -Path (Split-Path $logFile) -Force -ErrorAction SilentlyContinue

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $msg" | Tee-Object -FilePath $logFile -Append
}

$apiKey = "2ac6994b6a224d5d84ebd4c7abd7381c"
$headers = @{"X-Api-Key"=$apiKey; "Content-Type"="application/json"}

Log "=== Overnight Move Started ==="

# --- Step 1: Move Gold Rush and Friends ---
$seriesToMove = @("Gold Rush", "Friends")

foreach ($name in $seriesToMove) {
    $src = "D:\TV\$name"
    $dst = "E:\TV\$name"

    if (-not (Test-Path $src)) {
        Log "[$name] SKIP - source not found (already moved)"
        continue
    }

    $srcFiles = Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue
    $srcGB = [Math]::Round(($srcFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 1)
    Log "[$name] Moving $srcGB GB from D: to E:..."

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    robocopy $src $dst /MOVE /E /R:1 /W:1 /NP /NFL /NDL /NJH /NJS
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    $mins = [Math]::Round($sw.Elapsed.TotalMinutes, 1)

    if ($exitCode -lt 8) {
        Log "[$name] Done in $mins min (exit: $exitCode)"
        # Clean up empty source
        if (Test-Path $src) {
            $remaining = Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue
            if ($remaining.Count -eq 0) {
                Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue
                Log "[$name] Cleaned up empty source directory"
            } else {
                Log "[$name] WARNING: $($remaining.Count) files still on D: (likely locked)"
            }
        }
    } else {
        Log "[$name] ERROR after $mins min (exit: $exitCode)"
    }

    $d = Get-PSDrive D; $e = Get-PSDrive E
    Log "Drive space - D: Free: $([Math]::Round($d.Free/1GB, 1)) GB | E: Free: $([Math]::Round($e.Free/1GB, 1)) GB"
}

# --- Step 2: Revert NOVA, How It's Made, Expedition Unknown, Smallville back to /data/TV ---
Log ""
Log "=== Reverting 4 series paths back to /data/TV ==="

$seriesToRevert = @("NOVA", "How It's Made", "Expedition Unknown", "Smallville")

$allSeries = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 60

foreach ($name in $seriesToRevert) {
    $s = $allSeries | Where-Object { $_.title -eq $name }
    if (-not $s) {
        Log "[$name] Not found in Sonarr"
        continue
    }

    if ($s.path -like "/data/TV*") {
        Log "[$name] Already on /data/TV - no change needed"
        continue
    }

    $oldPath = $s.path
    $s.path = "/data/TV/$name"
    $s.rootFolderPath = "/data/TV"
    $body = $s | ConvertTo-Json -Depth 10 -Compress

    try {
        $null = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series/$($s.id)" -Method PUT -Headers $headers -Body $body -TimeoutSec 30
        Log "[$name] Path reverted: $oldPath -> /data/TV/$name"
    } catch {
        Log "[$name] FAILED to revert path: $($_.Exception.Message)"
    }
}

# --- Step 3: Clean up partial copies on E: for the 4 non-moved series ---
Log ""
Log "=== Cleaning up partial copies on E: ==="

foreach ($name in $seriesToRevert) {
    $ePath = "E:\TV\$name"
    if (Test-Path $ePath) {
        $eSize = [Math]::Round((Get-ChildItem $ePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 1)
        Remove-Item $ePath -Recurse -Force -ErrorAction SilentlyContinue
        Log "[$name] Deleted partial copy on E: ($eSize GB)"
    } else {
        Log "[$name] No partial copy on E:"
    }
}

# --- Step 4: Trigger Sonarr rescan for moved series ---
Log ""
Log "=== Triggering Sonarr rescan ==="

$movedSeries = @("Gold Rush", "Friends")
foreach ($name in $movedSeries) {
    $s = $allSeries | Where-Object { $_.title -eq $name }
    if ($s) {
        $body = "{`"name`":`"RescanSeries`",`"seriesId`":$($s.id)}"
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Method POST -Headers $headers -Body $body -TimeoutSec 15
            Log "[$name] Rescan triggered (ID: $($s.id))"
        } catch {
            Log "[$name] Failed to trigger rescan: $($_.Exception.Message)"
        }
    }
}

# --- Done ---
Log ""
$d = Get-PSDrive D; $e = Get-PSDrive E
Log "=== Overnight Move Complete ==="
Log "D: Free: $([Math]::Round($d.Free/1GB, 1)) GB | Used: $([Math]::Round($d.Used/1GB, 1)) GB"
Log "E: Free: $([Math]::Round($e.Free/1GB, 1)) GB | Used: $([Math]::Round($e.Used/1GB, 1)) GB"
