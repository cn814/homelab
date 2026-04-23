# Auto-balance script for dual-drive media setup
# Switches the default root folder to whichever drive has more free space
# This ensures equal distribution of content across both drives

$SonarrUrl = "http://localhost:8989"
$SonarrApiKey = "2ac6994b6a224d5d84ebd4c7abd7381c"

$RadarrUrl = "http://localhost:7878"
$RadarrApiKey = "a63000fb63a240a8bcb5e7d750926379"

$LogFile = "C:\jellyfin-stack\logs\balance-drives.log"

# Ensure log directory exists
$null = New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

# Get free space for both drives
$DriveD = Get-Volume -DriveLetter D
$DriveE = Get-Volume -DriveLetter E

$FreeDGB = [math]::Round($DriveD.SizeRemaining / 1GB, 2)
$FreeEGB = [math]::Round($DriveE.SizeRemaining / 1GB, 2)

Write-Log "Drive D: Free: $FreeDGB GB"
Write-Log "Drive E: Free: $FreeEGB GB"

# Determine which drive should be default (the one with MORE free space)
if ($FreeEGB -gt $FreeDGB) {
    $TargetSonarrPath = "/data2/TV"
    $TargetRadarrPath = "/data2/Movies"
    $TargetDrive = "E:"
} else {
    $TargetSonarrPath = "/data/TV"
    $TargetRadarrPath = "/data/Movies"
    $TargetDrive = "D:"
}

Write-Log "Target drive for new downloads: $TargetDrive"

# Function to get naming config and update default root folder
function Update-DefaultRootFolder {
    param(
        [string]$AppName,
        [string]$Url,
        [string]$ApiKey,
        [string]$TargetPath
    )

    try {
        # Get current naming config (which contains the default root folder setting)
        $namingConfig = Invoke-RestMethod -Uri "$Url/api/v3/config/naming" -Headers @{ "X-Api-Key" = $ApiKey }

        # Get root folders to find the ID of our target path
        $rootFolders = Invoke-RestMethod -Uri "$Url/api/v3/rootfolder" -Headers @{ "X-Api-Key" = $ApiKey }
        $targetFolder = $rootFolders | Where-Object { $_.path -eq $TargetPath }

        if (-not $targetFolder) {
            Write-Log "$AppName : ERROR - Target root folder '$TargetPath' not found!"
            return $false
        }

        Write-Log "$AppName : Found root folder ID $($targetFolder.id) for path $TargetPath"

        # Note: Sonarr/Radarr don't have a "default" root folder setting in config.
        # The default is determined by order or user selection in UI.
        # However, we CAN log which one we recommend and let the user know.

        Write-Log "$AppName : Recommended root folder: $TargetPath (ID: $($targetFolder.id))"
        return $true

    } catch {
        Write-Log "$AppName : ERROR - $_"
        return $false
    }
}

# Update recommendations
Update-DefaultRootFolder -AppName "Sonarr" -Url $SonarrUrl -ApiKey $SonarrApiKey -TargetPath $TargetSonarrPath
Update-DefaultRootFolder -AppName "Radarr" -Url $RadarrUrl -ApiKey $RadarrApiKey -TargetPath $TargetRadarrPath

# Update Jellyseerr settings to use the target drive
$JellyseerrSettingsPath = "C:\jellyfin-stack\config\jellyseerr\settings.json"

try {
    $settings = Get-Content $JellyseerrSettingsPath -Raw | ConvertFrom-Json

    $currentRadarrDir = $settings.radarr[0].activeDirectory
    $currentSonarrDir = $settings.sonarr[0].activeDirectory

    $changed = $false

    if ($currentRadarrDir -ne $TargetRadarrPath) {
        Write-Log "Updating Radarr directory: $currentRadarrDir -> $TargetRadarrPath"
        $settings.radarr[0].activeDirectory = $TargetRadarrPath
        $changed = $true
    }

    if ($currentSonarrDir -ne $TargetSonarrPath) {
        Write-Log "Updating Sonarr directory: $currentSonarrDir -> $TargetSonarrPath"
        $settings.sonarr[0].activeDirectory = $TargetSonarrPath
        $changed = $true
    }

    if ($changed) {
        # Write without BOM to avoid JSON parse errors
        $json = $settings | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($JellyseerrSettingsPath, $json)
        Write-Log "Jellyseerr settings updated. Restarting container..."
        docker restart jellyseerr 2>&1 | Out-Null
        Write-Log "Jellyseerr restarted with new settings."
    } else {
        Write-Log "Jellyseerr already configured for $TargetDrive - no changes needed."
    }
} catch {
    Write-Log "ERROR updating Jellyseerr settings: $_"
}

# Summary
$DiffGB = [math]::Abs($FreeDGB - $FreeEGB)
Write-Log "Space difference between drives: $DiffGB GB"
Write-Log "Balance check complete. New content going to $TargetDrive"
