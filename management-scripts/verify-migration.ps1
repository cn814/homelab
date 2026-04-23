$src = "c:\jellyfin-stack\config"
$dst = "C:\ProgramData\Jellyfin\Server"

Write-Output "=== Comparing Docker vs Native Jellyfin ==="

# Check config files
foreach ($f in @("system.xml", "network.xml", "database.xml", "branding.xml", "logging.json")) {
    $srcFile = "$src\config\$f"
    $dstFile = "$dst\config\$f"
    if ((Test-Path $srcFile) -and (Test-Path $dstFile)) {
        $srcHash = (Get-FileHash $srcFile).Hash
        $dstHash = (Get-FileHash $dstFile).Hash
        $match = if ($srcHash -eq $dstHash) { "MATCH" } else { "MISMATCH" }
        Write-Output "  $f : $match"
    } else {
        Write-Output "  $f : MISSING"
    }
}

# Check database
$srcDb = "$src\data\jellyfin.db"
$dstDb = "$dst\data\jellyfin.db"
if ((Test-Path $srcDb) -and (Test-Path $dstDb)) {
    $srcSize = (Get-Item $srcDb).Length
    $dstSize = (Get-Item $dstDb).Length
    Write-Output "  jellyfin.db: src=$([math]::Round($srcSize/1MB,1))MB dst=$([math]::Round($dstSize/1MB,1))MB"
} else {
    Write-Output "  jellyfin.db: MISSING"
}

# Check server name in native config
[xml]$sys = Get-Content "$dst\config\system.xml"
Write-Output ""
Write-Output "Native server name: $($sys.ServerConfiguration.ServerName)"

# Check encoding
[xml]$enc = Get-Content "$dst\config\encoding.xml"
Write-Output "Hardware accel: $($enc.EncodingOptions.HardwareAccelerationType)"
