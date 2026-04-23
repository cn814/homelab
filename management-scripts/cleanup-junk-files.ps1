# Unified cleanup script for torrent junk files
# Removes junk extensions, sample videos, screenshot folders, and empty dirs
# Note: Keeps .nfo files as Jellyfin uses them for metadata
#
# Usage:
#   Full library scan:   cleanup-junk-files.ps1
#   Single path:         cleanup-junk-files.ps1 -Path "D:\Movies\SomeMovie (2024)"
#   Recent downloads:    cleanup-junk-files.ps1 -RecentHours 2

param(
    [string]$Path,
    [int]$RecentHours = 0
)

$LogFile = "C:\jellyfin-stack\logs\post-download-cleanup.log"
$null = New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

# Junk file extensions (lowercase)
$junkExtensions = @(".txt", ".url", ".exe", ".lnk", ".html")

# Screenshot/proof folder names (matched case-insensitively)
$screenFolderNames = @("Screens", "Screenshots", "Screen", "Proof", "Proofs", "Sample", "Samples")

$totalRemoved = 0
$totalFailed = 0
$totalBytes = [long]0

# Determine which directories to scan
if ($Path) {
    if (-not (Test-Path $Path)) {
        Write-Log "Path does not exist: $Path"
        exit 0
    }
    $scanDirs = @(Get-Item $Path)
    Write-Log "Cleanup triggered for: $Path"
} else {
    $libraryPaths = @("D:\Movies", "D:\TV", "E:\Movies", "E:\TV")

    if ($RecentHours -gt 0) {
        $cutoffTime = (Get-Date).AddHours(-$RecentHours)
        $scanDirs = @()
        foreach ($basePath in $libraryPaths) {
            if (Test-Path $basePath) {
                $scanDirs += Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $cutoffTime }
            }
        }
        Write-Log "Starting recent cleanup (last $RecentHours hours, $($scanDirs.Count) directories)..."
    } else {
        $scanDirs = @()
        foreach ($basePath in $libraryPaths) {
            if (Test-Path $basePath) {
                $scanDirs += Get-Item $basePath
            }
        }
        Write-Log "Starting full library cleanup..."
    }
}

if ($scanDirs.Count -eq 0) {
    Write-Log "No directories to scan"
    exit 0
}

# === PHASE 1: Collect everything to delete in a single pass ===
$filesToDelete = [System.Collections.Generic.List[object]]::new()
$dirsToDelete = [System.Collections.Generic.List[string]]::new()

foreach ($dir in $scanDirs) {
    # Single recursive pass - collect all files and directories
    $allFiles = @(Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue)
    $allDirs = @(Get-ChildItem -Path $dir.FullName -Recurse -Directory -ErrorAction SilentlyContinue)

    foreach ($file in $allFiles) {
        # Check junk extension
        if ($junkExtensions -contains $file.Extension.ToLower()) {
            $filesToDelete.Add($file)
            continue
        }

        # Check sample video
        if ($file.Extension -match "\.(avi|mkv|mp4|wmv)$") {
            if ($file.Name -match "^sample\." -or $file.Directory.Name -eq "Sample") {
                $filesToDelete.Add($file)
                continue
            }
        }
    }

    # Collect screen/sample/proof directories (deepest first so children are removed before parents)
    $allDirs | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if ($screenFolderNames -contains $_.Name) {
            $dirsToDelete.Add($_.FullName)
        }
    }
}

Write-Log "Found $($filesToDelete.Count) junk files and $($dirsToDelete.Count) junk directories"

# === PHASE 2: Delete everything ===

foreach ($file in $filesToDelete) {
    if (Test-Path $file.FullName) {
        try {
            $totalBytes += $file.Length
            Remove-Item $file.FullName -Force -ErrorAction Stop
            Write-Log "  Removed: $($file.FullName)"
            $totalRemoved++
        } catch {
            $totalBytes -= $file.Length
            Write-Log "  Failed: $($file.FullName)"
            $totalFailed++
        }
    }
}

foreach ($dirPath in $dirsToDelete) {
    if (Test-Path $dirPath) {
        $remaining = @(Get-ChildItem $dirPath -File -Recurse -ErrorAction SilentlyContinue)
        $dirBytes = ($remaining | Measure-Object -Property Length -Sum).Sum
        try {
            Remove-Item $dirPath -Recurse -Force -ErrorAction Stop
            Write-Log "  Removed dir: $dirPath ($($remaining.Count) files)"
            $totalRemoved += $remaining.Count
            $totalBytes += $dirBytes
        } catch {
            Write-Log "  Failed dir: $dirPath"
            $totalFailed++
        }
    }
}

if ($totalBytes -ge 1GB) {
    $sizeStr = "$([math]::Round($totalBytes / 1GB, 2)) GB"
} elseif ($totalBytes -ge 1MB) {
    $sizeStr = "$([math]::Round($totalBytes / 1MB, 1)) MB"
} else {
    $sizeStr = "$([math]::Round($totalBytes / 1KB, 0)) KB"
}
Write-Log "Cleanup complete: removed $totalRemoved items, reclaimed $sizeStr$(if ($totalFailed) {", $totalFailed failed"})"
