## restore-stack.ps1
## Automated full rebuild of the Jellyfin media stack from backup.
## Run from the backup folder or pass the backup path as a parameter.
##
## Usage:
##   powershell -ExecutionPolicy Bypass -File restore-stack.ps1
##   powershell -ExecutionPolicy Bypass -File restore-stack.ps1 -BackupPath "G:\My Drive\jellyfin-backup"

param(
    [string]$BackupPath = "",
    [string]$InstallPath = "c:\jellyfin-stack",
    [switch]$SkipDocker,
    [switch]$SkipTasks
)

function Write-Step($num, $msg) {
    Write-Host "`n[$num] $msg" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Test-BackupValid($path) {
    $required = @("compose", "sonarr", "radarr", "prowlarr", "scripts", "MANIFEST.txt")
    foreach ($item in $required) {
        if (-not (Test-Path (Join-Path $path $item))) {
            return $false
        }
    }
    return $true
}

# ─── Determine backup location ───
if (-not $BackupPath) {
    # Check if script is running from a backup folder
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (Test-BackupValid $scriptDir) {
        $BackupPath = $scriptDir
    } elseif (Test-BackupValid (Join-Path $scriptDir "..")) {
        $BackupPath = (Resolve-Path (Join-Path $scriptDir "..")).Path
    } else {
        Write-Host "ERROR: No backup path specified and script is not in a backup folder." -ForegroundColor Red
        Write-Host "Usage: restore-stack.ps1 -BackupPath 'path\to\backup'" -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-BackupValid $BackupPath)) {
    Write-Host "ERROR: $BackupPath does not look like a valid backup (missing required folders)." -ForegroundColor Red
    exit 1
}

Write-Host "=============================================" -ForegroundColor Green
Write-Host "  JELLYFIN STACK RESTORE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host "Backup source: $BackupPath"
Write-Host "Install target: $InstallPath"
Write-Host ""

# ─── Step 0: Prerequisites check ───
Write-Step 0 "Checking prerequisites"

$dockerOk = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerOk -and -not $SkipDocker) {
    Write-Host "Docker is not installed!" -ForegroundColor Red
    Write-Host "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
    Write-Host "After installing, restart this script." -ForegroundColor Yellow
    exit 1
}

if ($dockerOk -and -not $SkipDocker) {
    $dockerRunning = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker is installed but not running. Starting Docker Desktop..." -ForegroundColor Yellow
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
        Write-Host "Waiting for Docker to start (this can take 1-2 minutes)..."
        $timeout = 120
        $elapsed = 0
        while ($elapsed -lt $timeout) {
            Start-Sleep -Seconds 5
            $elapsed += 5
            docker info 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Write-Host "  Waiting... ($elapsed s)" -ForegroundColor Gray
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Docker failed to start within $timeout seconds." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "Docker is running." -ForegroundColor Green
}

# ─── Step 1: Create directory structure ───
Write-Step 1 "Creating directory structure"

$dirs = @(
    $InstallPath,
    "$InstallPath\config\sonarr",
    "$InstallPath\config\radarr",
    "$InstallPath\config\prowlarr",
    "$InstallPath\config\bazarr\config",
    "$InstallPath\config\bazarr\db",
    "$InstallPath\config\jellyseerr\db",
    "$InstallPath\config\qbittorrent\qBittorrent",
    "$InstallPath\config\config\ScheduledTasks",
    "$InstallPath\caddy",
    "$InstallPath\cache",
    "$InstallPath\scripts",
    "$InstallPath\scheduled-tasks",
    "$InstallPath\backups"
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Gray
    }
}
Write-Host "Directory structure ready." -ForegroundColor Green

# ─── Step 2: Restore Docker Compose and env files ───
Write-Step 2 "Restoring Docker Compose configuration"

if (Test-Path "$BackupPath\compose\docker-compose.yml") {
    Copy-Item "$BackupPath\compose\docker-compose.yml" "$InstallPath\" -Force
    Write-Host "  docker-compose.yml restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\compose\.env.vpn") {
    Copy-Item "$BackupPath\compose\.env.vpn" "$InstallPath\" -Force
    Write-Host "  .env.vpn restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\compose\.gitignore") {
    Copy-Item "$BackupPath\compose\.gitignore" "$InstallPath\" -Force
    Write-Host "  .gitignore restored" -ForegroundColor Green
}

# ─── Step 3: Restore Caddy ───
Write-Step 3 "Restoring Caddy configuration"

if (Test-Path "$BackupPath\caddy") {
    Copy-Item "$BackupPath\caddy\*" "$InstallPath\caddy\" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Caddy config restored" -ForegroundColor Green
}

# ─── Step 4: Restore Sonarr ───
Write-Step 4 "Restoring Sonarr (TV)"

if (Test-Path "$BackupPath\sonarr\config.xml") {
    Copy-Item "$BackupPath\sonarr\config.xml" "$InstallPath\config\sonarr\" -Force
    Write-Host "  config.xml restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\sonarr\sonarr.db") {
    Copy-Item "$BackupPath\sonarr\sonarr.db" "$InstallPath\config\sonarr\" -Force
    Write-Host "  sonarr.db restored" -ForegroundColor Green
}

# ─── Step 5: Restore Radarr ───
Write-Step 5 "Restoring Radarr (Movies)"

if (Test-Path "$BackupPath\radarr\config.xml") {
    Copy-Item "$BackupPath\radarr\config.xml" "$InstallPath\config\radarr\" -Force
    Write-Host "  config.xml restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\radarr\radarr.db") {
    Copy-Item "$BackupPath\radarr\radarr.db" "$InstallPath\config\radarr\" -Force
    Write-Host "  radarr.db restored" -ForegroundColor Green
}

# ─── Step 6: Restore Prowlarr ───
Write-Step 6 "Restoring Prowlarr (Indexers)"

if (Test-Path "$BackupPath\prowlarr\config.xml") {
    Copy-Item "$BackupPath\prowlarr\config.xml" "$InstallPath\config\prowlarr\" -Force
    Write-Host "  config.xml restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\prowlarr\prowlarr.db") {
    Copy-Item "$BackupPath\prowlarr\prowlarr.db" "$InstallPath\config\prowlarr\" -Force
    Write-Host "  prowlarr.db restored" -ForegroundColor Green
}

# ─── Step 7: Restore Bazarr ───
Write-Step 7 "Restoring Bazarr (Subtitles)"

if (Test-Path "$BackupPath\bazarr\config.yaml") {
    Copy-Item "$BackupPath\bazarr\config.yaml" "$InstallPath\config\bazarr\config\" -Force
    Write-Host "  config.yaml restored" -ForegroundColor Green
}
if (Test-Path "$BackupPath\bazarr\bazarr.db") {
    Copy-Item "$BackupPath\bazarr\bazarr.db" "$InstallPath\config\bazarr\db\" -Force
    Write-Host "  bazarr.db restored" -ForegroundColor Green
}

# ─── Step 8: Restore Jellyseerr ───
Write-Step 8 "Restoring Jellyseerr (Requests)"

if (Test-Path "$BackupPath\jellyseerr") {
    Copy-Item "$BackupPath\jellyseerr\*" "$InstallPath\config\jellyseerr\" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Jellyseerr config and database restored" -ForegroundColor Green
}

# ─── Step 9: Restore qBittorrent ───
Write-Step 9 "Restoring qBittorrent"

if (Test-Path "$BackupPath\qbittorrent\qBittorrent.conf") {
    Copy-Item "$BackupPath\qbittorrent\qBittorrent.conf" "$InstallPath\config\qbittorrent\qBittorrent\" -Force
    Write-Host "  qBittorrent.conf restored" -ForegroundColor Green
}

# ─── Step 10: Restore Jellyfin config ───
Write-Step 10 "Restoring Jellyfin configuration"

if (Test-Path "$BackupPath\jellyfin-config") {
    $jellyfinFiles = Get-ChildItem "$BackupPath\jellyfin-config\*" -ErrorAction SilentlyContinue
    foreach ($f in $jellyfinFiles) {
        if ($f.Extension -eq ".js") {
            Copy-Item $f.FullName "$InstallPath\config\config\ScheduledTasks\" -Force
        } else {
            Copy-Item $f.FullName "$InstallPath\config\config\" -Force
        }
        Write-Host "  $($f.Name) restored" -ForegroundColor Green
    }
}

# ─── Step 11: Restore scripts ───
Write-Step 11 "Restoring automation scripts"

if (Test-Path "$BackupPath\scripts") {
    $scriptFiles = Get-ChildItem "$BackupPath\scripts\*" -ErrorAction SilentlyContinue
    foreach ($f in $scriptFiles) {
        if ($f.Name -match '\.(ps1|py|json)$') {
            $dest = if ($f.Name -match '\.(py|json)$') { "$InstallPath\" } else { "$InstallPath\scripts\" }
            Copy-Item $f.FullName $dest -Force
        }
    }
    Write-Host "  $($scriptFiles.Count) scripts restored" -ForegroundColor Green
}

# ─── Step 12: Restore scheduled task XMLs ───
Write-Step 12 "Restoring scheduled task definitions"

if (Test-Path "$BackupPath\scheduled-tasks") {
    Copy-Item "$BackupPath\scheduled-tasks\*" "$InstallPath\scheduled-tasks\" -Force -ErrorAction SilentlyContinue
    $taskCount = (Get-ChildItem "$BackupPath\scheduled-tasks\*.xml" -ErrorAction SilentlyContinue).Count
    Write-Host "  $taskCount task XML files copied" -ForegroundColor Green
}

# ─── Step 13: Start Docker containers ───
if (-not $SkipDocker) {
    Write-Step 13 "Starting Docker containers"

    Set-Location $InstallPath
    docker-compose up -d 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    Write-Host "`nWaiting 30 seconds for containers to initialize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30

    # Check container status
    $containers = docker ps --format "{{.Names}}: {{.Status}}" 2>&1
    Write-Host "`nContainer status:" -ForegroundColor Cyan
    foreach ($c in $containers) {
        $color = if ($c -match "Up") { "Green" } else { "Red" }
        Write-Host "  $c" -ForegroundColor $color
    }
} else {
    Write-Step 13 "Skipping Docker (--SkipDocker flag set)"
}

# ─── Step 14: Import scheduled tasks ───
if (-not $SkipTasks) {
    Write-Step 14 "Importing scheduled tasks"

    $taskXmls = Get-ChildItem "$InstallPath\scheduled-tasks\*.xml" -ErrorAction SilentlyContinue
    $imported = 0
    $skipped = 0
    foreach ($xml in $taskXmls) {
        $taskName = $xml.BaseName -replace '_', ' '
        # Skip non-jellyfin tasks
        if ($taskName -match 'AMDLink') { $skipped++; continue }
        try {
            $content = Get-Content $xml.FullName | Out-String
            Register-ScheduledTask -Xml $content -TaskName $taskName -Force | Out-Null
            Write-Host "  Imported: $taskName" -ForegroundColor Green
            $imported++
        } catch {
            Write-Host "  Failed: $taskName - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`n  $imported tasks imported, $skipped skipped" -ForegroundColor Green
} else {
    Write-Step 14 "Skipping scheduled tasks (--SkipTasks flag set)"
}

# ─── Step 15: Verify services ───
Write-Step 15 "Verifying services"

$services = @(
    @{ Name = "Jellyfin";    Url = "http://localhost:8096" },
    @{ Name = "Sonarr";      Url = "http://localhost:8989" },
    @{ Name = "Radarr";      Url = "http://localhost:7878" },
    @{ Name = "Prowlarr";    Url = "http://localhost:9696" },
    @{ Name = "Bazarr";      Url = "http://localhost:6767" },
    @{ Name = "qBittorrent"; Url = "http://localhost:8090" },
    @{ Name = "Jellyseerr";  Url = "http://localhost:5055" }
)

$healthy = 0
foreach ($svc in $services) {
    try {
        $response = Invoke-WebRequest -Uri $svc.Url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Host "  $($svc.Name): OK ($($svc.Url))" -ForegroundColor Green
        $healthy++
    } catch {
        Write-Host "  $($svc.Name): NOT RESPONDING ($($svc.Url))" -ForegroundColor Red
    }
}

# ─── Summary ───
Write-Host "`n=============================================" -ForegroundColor Green
Write-Host "  RESTORE COMPLETE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host "Services responding: $healthy / $($services.Count)"
Write-Host ""

if ($healthy -lt $services.Count) {
    Write-Host "Some services are not responding yet. They may still be starting up." -ForegroundColor Yellow
    Write-Host "Wait a few minutes and check manually, or run:" -ForegroundColor Yellow
    Write-Host "  powershell -File $InstallPath\scripts\health-check.ps1" -ForegroundColor White
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Open Jellyfin (http://localhost:8096) and trigger a library scan"
Write-Host "  2. Check VPN: docker exec gluetun sh -c 'wget -qO- https://ipinfo.io/ip'"
Write-Host "  3. Verify downloads: powershell -File $InstallPath\scripts\check-active.ps1"
Write-Host "  4. Check media drives D:\ and E:\ are connected"
Write-Host ""
Write-Host "GitHub repo: https://github.com/cn814/jellyfin-stack.git" -ForegroundColor Gray
