param(
    [int]$JellyfinPort = 8080,  # Jellyfin HTTP port
    [int]$MaxDockerRetries = 10,
    [int]$DockerRetrySeconds = 6,
    [int]$MaxHealthRetries = 20,
    [int]$HealthRetrySeconds = 6,

    # Path to your docker-compose file
    [string]$ComposeFile = "$PSScriptRoot\docker-compose.yml",

    # Path to the Discord watcher script
    [string]$DiscordWatcherScript = "$PSScriptRoot\jellyfin-discord-watch.ps1",

    # Path to the Tailscale Serve/Funnel setup script (your existing one)
    [string]$TailscaleServeScript = "$PSScriptRoot\Start-TailscaleServe.ps1",

    # Path to the Funnel watchdog script
    [string]$FunnelWatchdogScript = "$PSScriptRoot\Watch-TailscaleFunnel.ps1",

    # Path to the Discord bot script
    [string]$DiscordBotScript = "$PSScriptRoot\discord-bot.py",

    # Discord Webhook URL (optional, can also be set via DISCORD_WEBHOOK_URL env var)
    [string]$WebhookUrl = ""
)

# --- Utility: timestamped logging ---
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [$Level] $Message"
}

# --- Utility: Load .env file ---
function Load-EnvFile {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Log "Loading environment variables from $Path..."
        Get-Content $Path | ForEach-Object {
            $line = $_.Trim()
            if ($line -notmatch "^#" -and $line -match "=") {
                # Split only on the first equals sign to handle values containing '='
                $parts = $line -split "=", 2
                $key = $parts[0].Trim()
                $val = $parts[1].Trim()
                
                # Simple quote removal if needed
                if ($val.StartsWith('"') -and $val.EndsWith('"')) {
                    $val = $val.Substring(1, $val.Length - 2)
                }
                
                [Environment]::SetEnvironmentVariable($key, $val, "Process")
            }
        }
    }
    else {
        Write-Log ".env file not found at $Path; skipping." "WARN"
    }
}

Write-Log "==== StartEverything script started ===="

# Load env file early so variables are available
# Check for .env or .env.txt (common if extensions are hidden)
$envPath = "$PSScriptRoot\.env"
if (-not (Test-Path $envPath)) {
    $envPathTxt = "$PSScriptRoot\.env.txt"
    if (Test-Path $envPathTxt) {
        $envPath = $envPathTxt
    }
}
Load-EnvFile -Path $envPath

# --- Helper: check if Discord watcher is already running ---
function Test-DiscordWatcherRunning {
    param(
        [string]$ScriptPath
    )

    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'powershell' -and
            $_.CommandLine -like "*$ScriptPath*"
        }

        return ($procs -ne $null -and $procs.Count -gt 0)
    }
    catch {
        Write-Log "Could not inspect running processes: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# --- Helper: start Discord watcher in background ---
function Start-DiscordWatcher {
    param(
        [string]$ScriptPath,
        [string]$WebhookUrl
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Discord watcher script not found at '$ScriptPath'. Skipping watcher start." "WARN"
        return
    }

    # Always try to stop any existing instances to ensure only one is running with latest config
    Write-Log "Searching for and stopping existing Discord watcher processes..."
    
    $found = 0
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match 'powershell|pwsh' -and
        $_.CommandLine -like "*jellyfin-discord-watch.ps1*"
    } | ForEach-Object {
        Write-Log "Stopping process $($_.ProcessId)..."
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $found++
    }
    
    if ($found -gt 0) {
        Start-Sleep -Seconds 2
    }
    else {
        Write-Log "No existing watcher processes found."
    }

    try {
        $scriptDir = Split-Path $ScriptPath -Parent

        Write-Log "Starting Discord watcher: $ScriptPath"
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$ScriptPath`"",
            "-WebhookUrl", "`"$WebhookUrl`""
        ) `
            -WorkingDirectory $scriptDir `
            -WindowStyle Minimized | Out-Null

        Write-Log "Discord watcher launched in background."
    }
    catch {
        Write-Log "Failed to start Discord watcher: $($_.Exception.Message)" "ERROR"
    }
}

# --- Helper: check if Funnel watchdog is already running ---
function Test-FunnelWatchdogRunning {
    param(
        [string]$ScriptPath
    )

    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'powershell' -and
            $_.CommandLine -like "*$ScriptPath*"
        }

        return ($procs -ne $null -and $procs.Count -gt 0)
    }
    catch {
        Write-Log "Could not inspect running processes for funnel watchdog: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# --- Helper: start Funnel watchdog in background ---
function Start-FunnelWatchdog {
    param(
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Funnel watchdog script not found at '$ScriptPath'. Skipping watchdog start." "WARN"
        return
    }

    if (Test-FunnelWatchdogRunning -ScriptPath $ScriptPath) {
        Write-Log "Funnel watchdog already running; not starting another instance."
        return
    }

    try {
        $scriptDir = Split-Path $ScriptPath -Parent

        Write-Log "Starting Funnel watchdog: $ScriptPath"
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$ScriptPath`""
        ) `
            -WorkingDirectory $scriptDir `
            -WindowStyle Hidden | Out-Null

        Write-Log "Funnel watchdog launched in background."
    }
    catch {
        Write-Log "Failed to start Funnel watchdog: $($_.Exception.Message)" "ERROR"
    }
}

# --- Helper: check if Discord bot is already running ---
function Test-DiscordBotRunning {
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'python' -and
            $_.CommandLine -like "*discord-bot.py*"
        }

        return ($procs -ne $null -and $procs.Count -gt 0)
    }
    catch {
        Write-Log "Could not inspect running processes for Discord bot: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# --- Helper: start Discord bot in background ---
function Start-DiscordBot {
    param(
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Discord bot script not found at '$ScriptPath'. Skipping bot start." "WARN"
        return
    }

    # Check if bot token is set
    if ([string]::IsNullOrWhiteSpace($env:DISCORD_BOT_TOKEN)) {
        Write-Log "DISCORD_BOT_TOKEN environment variable not set. Skipping Discord bot start." "WARN"
        Write-Log "Set the token in your .env file or system environment variables." "WARN"
        return
    }

    if (Test-DiscordBotRunning) {
        Write-Log "Discord bot already running; not starting another instance."
        return
    }

    try {
        $scriptDir = Split-Path $ScriptPath -Parent

        Write-Log "Starting Discord bot: $ScriptPath"
        Start-Process -FilePath "python.exe" `
            -ArgumentList @(
            "`"$ScriptPath`""
        ) `
            -WorkingDirectory $scriptDir `
            -WindowStyle Hidden | Out-Null

        Write-Log "Discord bot launched in background."
    }
    catch {
        Write-Log "Failed to start Discord bot: $($_.Exception.Message)" "ERROR"
        Write-Log "Make sure Python is installed and in PATH." "ERROR"
    }
}

# --- Step 1: Make sure Docker Desktop is up (best-effort) ---
Write-Log "Step 1: Checking/starting Docker Desktop if needed..."

try {
    $dockerOk = $false
    try {
        docker version | Out-Null
        $dockerOk = $true
    }
    catch {
        $dockerOk = $false
    }

    if (-not $dockerOk) {
        Write-Log "Docker engine not responding; trying to start Docker Desktop (if installed)..."
        $dockerExe = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerExe) {
            Start-Process -FilePath $dockerExe | Out-Null
            Write-Log "Docker Desktop launched; waiting briefly for it to initialize..."
            Start-Sleep -Seconds 10
        }
        else {
            Write-Log "Docker Desktop executable not found at $dockerExe. Continuing anyway." "WARN"
        }
    }
    else {
        Write-Log "Docker is already responding; no need to start Docker Desktop."
    }
}
catch {
    Write-Log "Unexpected error while checking/starting Docker Desktop: $($_.Exception.Message)" "ERROR"
}

# --- Step 2: Wait for Docker engine to be ready with bounded retries ---
Write-Log "Step 2: Waiting for Docker engine..."
$dockerReady = $false

for ($i = 1; $i -le $MaxDockerRetries; $i++) {
    try {
        docker info | Out-Null
        Write-Log "Docker engine is ready (attempt $i/$MaxDockerRetries)."
        $dockerReady = $true
        break
    }
    catch {
        Write-Log "Docker not ready yet (attempt $i/$MaxDockerRetries). Retrying in $DockerRetrySeconds seconds..."
        Start-Sleep -Seconds $DockerRetrySeconds
    }
}

if (-not $dockerReady) {
    Write-Log "Docker engine never became ready after $MaxDockerRetries attempts. Aborting." "ERROR"
    exit 1
}

# --- Step 3: Start the Jellyfin stack with docker compose ---
Write-Log "Step 3: Starting Jellyfin docker stack..."

if (-not (Test-Path $ComposeFile)) {
    Write-Log "docker-compose.yml not found at $ComposeFile. Aborting." "ERROR"
    exit 1
}

try {
    docker compose -f $ComposeFile up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Log "docker compose up returned exit code $LASTEXITCODE." "ERROR"
    }
    else {
        Write-Log "docker compose up -d completed successfully."
    }
}
catch {
    Write-Log "Error running docker compose up: $($_.Exception.Message)" "ERROR"
}

# --- Step 4: Health check for Jellyfin with short timeouts + retries ---
$healthUrl = "http://localhost:$JellyfinPort"
Write-Log "Step 4: Checking Jellyfin health at $healthUrl ..."

$healthy = $false

for ($i = 1; $i -le $MaxHealthRetries; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3
        $status = [int]$response.StatusCode

        if ($status -ge 200 -and $status -lt 400) {
            Write-Log "Jellyfin responded with HTTP $status (attempt $i/$MaxHealthRetries). Considering it healthy."
            $healthy = $true
            break
        }
        else {
            Write-Log "Jellyfin responded with HTTP $status (attempt $i/$MaxHealthRetries). Retrying in $HealthRetrySeconds seconds..."
        }
    }
    catch {
        Write-Log "Health check failed (attempt $i/$MaxHealthRetries): $($_.Exception.Message). Retrying in $HealthRetrySeconds seconds..."
    }

    Start-Sleep -Seconds $HealthRetrySeconds
}

if (-not $healthy) {
    Write-Log "Jellyfin did NOT become healthy after $MaxHealthRetries attempts." "ERROR"
    Write-Log "You can manually check by opening $healthUrl in a browser or running:" "ERROR"
    Write-Host "    docker ps"
    Write-Host "    docker logs jellyfin --since 2m"
    exit 1
}

Write-Log "Jellyfin is healthy and responding on port $JellyfinPort. All done! 🎉"

# --- Step 5: Configure/ensure Tailscale Serve (only after Jellyfin is healthy) ---
if (Test-Path $TailscaleServeScript) {
    try {
        Write-Log "Step 5: Running Tailscale serve script: $TailscaleServeScript"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TailscaleServeScript | Out-Null
        Write-Log "Tailscale serve script completed."
    }
    catch {
        Write-Log "Tailscale serve script failed: $($_.Exception.Message)" "WARN"
    }
}
else {
    Write-Log "Tailscale serve script not found at '$TailscaleServeScript'. Skipping." "WARN"
}

# --- Step 6: Start Discord watcher (login/failed-login/playback alerts) ---
# Check env var if param is empty
if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    $WebhookUrl = $Env:DISCORD_WEBHOOK_URL
}

Start-DiscordWatcher -ScriptPath $DiscordWatcherScript -WebhookUrl $WebhookUrl

# --- Step 7: Start Funnel watchdog (keeps public URL alive) ---
Start-FunnelWatchdog -ScriptPath $FunnelWatchdogScript

# --- Step 8: Start Discord bot (interactive Discord commands) ---
Start-DiscordBot -ScriptPath $DiscordBotScript

exit 0
