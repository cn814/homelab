$gDrivePath = "G:\My Drive\jellyfin-backup"
$latestBackup = Get-ChildItem "c:\jellyfin-stack\backups" -Directory |
    Where-Object { $_.Name -match "^arr-stack-backup-" } |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1

if (-not $latestBackup) {
    Write-Output "No backup found to sync."
    exit 1
}

Write-Output "Syncing: $($latestBackup.Name) -> $gDrivePath"

# Remove old Google Drive backup if it exists
if (Test-Path $gDrivePath) {
    Write-Output "Removing old cloud backup..."
    Remove-Item $gDrivePath -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# Copy fresh backup
Write-Output "Copying to Google Drive..."
Copy-Item $latestBackup.FullName $gDrivePath -Recurse -Force

# Verify RESTORE.ps1 is there
if (Test-Path "$gDrivePath\RESTORE.ps1") {
    Write-Output "RESTORE.ps1 confirmed in Google Drive backup."
} else {
    Write-Output "WARNING: RESTORE.ps1 not found!"
}

Write-Output "Done."
