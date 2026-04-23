param(
    [string[]]$Containers = @("jellyfin", "tailscale", "caddy"),
    [string]$WebhookUrl = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"  # <-- updated webhook
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

function Check-And-RestartContainer {
    param([string]$Name)

    try {
        $status = docker inspect -f '{{.State.Status}}' $Name 2>$null

        if ([string]::IsNullOrWhiteSpace($status)) {
            Send-DiscordMessage "⚠️ Jellyfin host: container **$Name** not found when running auto-restart check."
            return
        }

        $status = $status.Trim()

        if ($status -eq "running") {
            Write-Host "Container $Name is running."
            return
        }

        Send-DiscordMessage "⛔ Container **$Name** status is '$status'. Attempting auto-restart..."
        Write-Host "Container $Name status is '$status' – restarting..."

        docker start $Name | Out-Null
        Start-Sleep -Seconds 3

        $newStatus = docker inspect -f '{{.State.Status}}' $Name 2>$null
        $newStatus = $newStatus.Trim()

        if ($newStatus -eq "running") {
            Send-DiscordMessage "✅ Container **$Name** successfully restarted (now '$newStatus')."
        }
        else {
            Send-DiscordMessage "🚨 Failed to auto-restart container **$Name**. Status after attempt: '$newStatus'."
        }
    }
    catch {
        Send-DiscordMessage "🚨 Error while checking container **$Name**: $($_.Exception.Message)"
    }
}

Write-Host "===== Jellyfin container auto-restart check ====="
foreach ($c in $Containers) {
    Check-And-RestartContainer -Name $c
}
Write-Host "===== Done ====="
