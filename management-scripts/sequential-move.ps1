# Sequential move of 6 series from D:\TV to E:\TV (one at a time)
# Robocopy /MOVE skips already-copied files, so safe to resume partial moves

$series = @(
    "Gold Rush",
    "Friends",
    "NOVA",
    "How It's Made",
    "Expedition Unknown",
    "Smallville"
)

$startTime = Get-Date
Write-Output "=== Sequential Series Move Started: $startTime ==="
Write-Output ""

foreach ($name in $series) {
    $src = "D:\TV\$name"
    $dst = "E:\TV\$name"

    if (-not (Test-Path $src)) {
        Write-Output "[$name] SKIP - source not found (already moved?)"
        Write-Output ""
        continue
    }

    $srcSize = [Math]::Round((Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 1)
    Write-Output "[$name] Starting move: $srcSize GB remaining on D:"
    Write-Output "  $src -> $dst"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    robocopy $src $dst /MOVE /E /R:1 /W:1 /NP /NFL /NDL /NJH /NJS
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    $mins = [Math]::Round($sw.Elapsed.TotalMinutes, 1)

    # Robocopy exit codes: 0=no files copied, 1=files copied, 2=extra files, 4=mismatches, 8+=errors
    if ($exitCode -lt 8) {
        Write-Output "  DONE in $mins min (robocopy exit: $exitCode)"
        # Clean up empty source directory
        if (Test-Path $src) {
            $remaining = Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue
            if ($remaining.Count -eq 0) {
                Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue
                Write-Output "  Cleaned up empty source directory"
            } else {
                Write-Output "  WARNING: $($remaining.Count) files still in source"
            }
        }
    } else {
        Write-Output "  ERROR after $mins min (robocopy exit: $exitCode)"
    }

    # Report drive space after each move
    $d = Get-PSDrive D; $e = Get-PSDrive E
    Write-Output "  D: Free: $([Math]::Round($d.Free/1GB, 1)) GB | E: Free: $([Math]::Round($e.Free/1GB, 1)) GB"
    Write-Output ""
}

$elapsed = (Get-Date) - $startTime
Write-Output "=== All Moves Complete: $(Get-Date) (took $([Math]::Round($elapsed.TotalHours, 1)) hours) ==="
