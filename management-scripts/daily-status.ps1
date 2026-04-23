param(
    [string]$WebhookUrl = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN",
    [string[]]$Containers = @(
        "jellyfin", 
        "caddy", 
        "tailscale", 
        "watchtower",
        "gluetun", 
        "qbittorrent", 
        "prowlarr", 
        "sonarr", 
        "radarr", 
        "jellyseerr", 
        "flaresolverr"
    )
)

function Send-DiscordMessage {
    param([string]$Content)

    $body = @{ content = $Content } | ConvertTo-Json
    try {
        Invoke-WebRequest `
            -Uri $WebhookUrl `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -UseBasicParsing | Out-Null
    }
    catch {
        Write-Warning "Failed to send Discord message: $($_.Exception.Message)"
    }
}

$issues = @()
$runningCount = 0

# Ensure docker is in path
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    $commonPaths = @(
        "C:\Program Files\Docker\Docker\resources\bin",
        "C:\Program Files\Docker\Docker\resources",
        "C:\Program Files\Docker\cli-plugins"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path "$p\docker.exe") {
            $env:Path += ";$p"
            break
        }
    }
}

foreach ($c in $Containers) {
    # Using specific error action and redirection to avoid noise
    $status = docker inspect -f "{{.State.Status}}" $c 2>$null
    
    if ([string]::IsNullOrWhiteSpace($status)) {
        $issues += "**$c**: Not Found"
    }
    else {
        $status = $status.Trim()
        if ($status -eq "running") {
            $runningCount++
        }
        else {
            $issues += "**$c**: $status"
        }
    }
}

if ($issues.Count -eq 0) {
    $msg = "**Daily Status Report**: All systems operational ($runningCount services running)."
    Send-DiscordMessage $msg
}
else {
    $msg = "**Daily Status Report**: Issues found!`n" + ($issues -join "`n")
    Send-DiscordMessage $msg
}
