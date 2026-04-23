param(
  [string]$StackDir = "C:\jellyfin-stack",
  [string]$ComposeFile = "docker-compose.yml"
)

$ErrorActionPreference = "Stop"

function Write-Log($m) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$ts] $m"
}

Push-Location $StackDir

Write-Log "Pulling latest images..."
docker compose -f $ComposeFile pull

Write-Log "Recreating containers..."
docker compose -f $ComposeFile up -d

Write-Log "Done. Current containers:"
docker ps

Pop-Location
