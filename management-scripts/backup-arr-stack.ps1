# Arr Stack Backup Script
# Creates a complete backup of your media automation stack configuration

# Set root directory
$rootDir = "c:\jellyfin-stack"
Set-Location $rootDir

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "backups\arr-stack-backup-$timestamp"

Write-Host "Creating backup at: $backupDir" -ForegroundColor Cyan

# Create backup directory structure
New-Item -ItemType Directory -Force -Path "$backupDir\compose" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\prowlarr" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\radarr" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\sonarr" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\jellyseerr" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\qbittorrent" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\caddy" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\bazarr" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\scripts" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\scheduled-tasks" | Out-Null
New-Item -ItemType Directory -Force -Path "$backupDir\jellyfin-config" | Out-Null

# Backup Docker Compose files
Write-Host "Backing up Docker Compose configuration..." -ForegroundColor Yellow
Copy-Item "docker-compose.yml" "$backupDir\compose\"
Copy-Item ".env.vpn" "$backupDir\compose\"
Copy-Item ".gitignore" "$backupDir\compose\"

# Backup Caddy configuration
Write-Host "Backing up Caddy configuration..." -ForegroundColor Yellow
Copy-Item "caddy\*" "$backupDir\caddy\" -Recurse -ErrorAction SilentlyContinue

# Backup Prowlarr
Write-Host "Backing up Prowlarr..." -ForegroundColor Yellow
Copy-Item "config\prowlarr\config.xml" "$backupDir\prowlarr\" -ErrorAction SilentlyContinue
Copy-Item "config\prowlarr\prowlarr.db" "$backupDir\prowlarr\" -ErrorAction SilentlyContinue

# Backup Radarr
Write-Host "Backing up Radarr..." -ForegroundColor Yellow
Copy-Item "config\radarr\config.xml" "$backupDir\radarr\" -ErrorAction SilentlyContinue
Copy-Item "config\radarr\radarr.db" "$backupDir\radarr\" -ErrorAction SilentlyContinue

# Backup Sonarr
Write-Host "Backing up Sonarr..." -ForegroundColor Yellow
Copy-Item "config\sonarr\config.xml" "$backupDir\sonarr\" -ErrorAction SilentlyContinue
Copy-Item "config\sonarr\sonarr.db" "$backupDir\sonarr\" -ErrorAction SilentlyContinue

# Backup Jellyseerr
Write-Host "Backing up Jellyseerr..." -ForegroundColor Yellow
Copy-Item "config\jellyseerr\*" "$backupDir\jellyseerr\" -Recurse -ErrorAction SilentlyContinue

# Backup qBittorrent
Write-Host "Backing up qBittorrent..." -ForegroundColor Yellow
Copy-Item "config\qbittorrent\qBittorrent\qBittorrent.conf" "$backupDir\qbittorrent\" -ErrorAction SilentlyContinue

# Backup Bazarr
Write-Host "Backing up Bazarr..." -ForegroundColor Yellow
Copy-Item "config\bazarr\config\config.yaml" "$backupDir\bazarr\" -ErrorAction SilentlyContinue
Copy-Item "config\bazarr\db\bazarr.db" "$backupDir\bazarr\" -ErrorAction SilentlyContinue

# Backup Jellyfin config (branding, system settings, scheduled tasks)
Write-Host "Backing up Jellyfin config..." -ForegroundColor Yellow
Copy-Item "config\config\branding.xml" "$backupDir\jellyfin-config\" -ErrorAction SilentlyContinue
Copy-Item "config\config\system.xml" "$backupDir\jellyfin-config\" -ErrorAction SilentlyContinue
Copy-Item "config\config\database.xml" "$backupDir\jellyfin-config\" -ErrorAction SilentlyContinue
if (Test-Path "config\config\ScheduledTasks") {
    Copy-Item "config\config\ScheduledTasks\*" "$backupDir\jellyfin-config\" -ErrorAction SilentlyContinue
}

# Backup all automation scripts
Write-Host "Backing up scripts..." -ForegroundColor Yellow
Copy-Item "scripts\*.ps1" "$backupDir\scripts\" -ErrorAction SilentlyContinue
Copy-Item "discord-bot.py" "$backupDir\scripts\" -ErrorAction SilentlyContinue
Copy-Item "discord-bot-config.json" "$backupDir\scripts\" -ErrorAction SilentlyContinue

# Copy restore script to backup root so it's easy to find and run
Copy-Item "scripts\restore-stack.ps1" "$backupDir\RESTORE.ps1" -ErrorAction SilentlyContinue

# Export and backup scheduled tasks
Write-Host "Exporting scheduled tasks..." -ForegroundColor Yellow
& "$rootDir\scripts\export-scheduled-tasks.ps1" | Out-Null
if (Test-Path "scheduled-tasks") {
    Copy-Item "scheduled-tasks\*" "$backupDir\scheduled-tasks\" -ErrorAction SilentlyContinue
}

# Create backup manifest
$manifest = @"
ARR STACK BACKUP MANIFEST
=========================
Backup Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Backup Location: $backupDir

CONTENTS:
---------
- Docker Compose configuration (docker-compose.yml, .env.vpn)
- Prowlarr configuration and database
- Radarr configuration and database (includes custom formats, quality profiles)
- Sonarr configuration and database (includes custom formats, quality profiles)
- Jellyseerr configuration and database
- Bazarr configuration and database (subtitle settings, provider config)
- qBittorrent configuration
- Caddy reverse proxy configuration
- Jellyfin server config (branding, system settings)
- All automation scripts (50+ PowerShell scripts)
- Discord bot (Python script + config)
- Windows Scheduled Tasks (XML exports + summary)

RESTORATION:
------------
To restore from this backup:
1. Install Docker Desktop and start it
2. Copy docker-compose.yml and .env.vpn to c:\jellyfin-stack\
3. Copy config files to their original locations under config\
4. Copy scripts\ folder to c:\jellyfin-stack\scripts\
5. Run: docker-compose up -d
6. Re-import scheduled tasks from scheduled-tasks\ folder:
   Get-ChildItem scheduled-tasks\*.xml | ForEach-Object {
     Register-ScheduledTask -Xml (Get-Content `$_.FullName | Out-String) -TaskName `$_.BaseName
   }
7. Verify all services are running: scripts\health-check.ps1

IMPORTANT NOTES:
----------------
- VPN credentials are included in .env.vpn
- qBittorrent password is stored in qBittorrent.conf
- API keys for all services are in config.xml files
- Discord bot token is in the JellyfinDiscordBot scheduled task XML
- GitHub repo: https://github.com/cn814/jellyfin-stack.git
- Keep this backup secure and private

EXCLUDED:
---------
- Media files (movies/TV shows) - stored on D:\ and E:\ drives
- Download cache
- Log files
- Jellyfin metadata (auto-regenerated on library scan)
- Temporary files
"@

$manifest | Out-File -FilePath "$backupDir\MANIFEST.txt" -Encoding UTF8

# Clean up old backups (keep only last 3)
Write-Host "`nCleaning up old backups (keeping last 3)..." -ForegroundColor Yellow
$oldBackups = Get-ChildItem "backups" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "^arr-stack-backup-" } |
    Sort-Object CreationTime -Descending |
    Select-Object -Skip 3

if ($oldBackups) {
    foreach ($backup in $oldBackups) {
        Write-Host "  Removing: $($backup.Name)" -ForegroundColor Gray
        Remove-Item $backup.FullName -Recurse -Force
    }
    Write-Host "Removed $($oldBackups.Count) old backup(s)" -ForegroundColor Green
} else {
    Write-Host "No old backups to remove" -ForegroundColor Gray
}

# Sync latest backup to Google Drive
$gDrivePath = "G:\My Drive\jellyfin-backup"
if (Test-Path "G:\My Drive") {
    Write-Host "`nSyncing backup to Google Drive..." -ForegroundColor Yellow
    if (Test-Path $gDrivePath) {
        Remove-Item $gDrivePath -Recurse -Force
    }
    Copy-Item $backupDir $gDrivePath -Recurse
    Write-Host "  Synced to: $gDrivePath" -ForegroundColor Green
} else {
    Write-Host "`nGoogle Drive not available - skipping cloud sync" -ForegroundColor Gray
}

Write-Host "`nBackup completed successfully!" -ForegroundColor Green
Write-Host "Location: $backupDir" -ForegroundColor Cyan
if (Test-Path $gDrivePath) {
    Write-Host "Cloud copy: $gDrivePath (syncs to Google Drive automatically)" -ForegroundColor Cyan
}
Write-Host "`nTo restore, see MANIFEST.txt in the backup folder" -ForegroundColor Yellow
