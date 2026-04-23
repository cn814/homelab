# Remove ReadOnly attribute from all media files so Sonarr/Radarr can manage them
$paths = @("D:\Movies", "D:\TV", "E:\Movies", "E:\TV")
$extensions = @("*.avi", "*.mp4", "*.mkv", "*.m4v", "*.wmv", "*.flv", "*.ts", "*.nfo", "*.srt", "*.sub", "*.idx")

$totalFixed = 0
foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        Write-Output "Skipping $path (not found)"
        continue
    }
    $count = 0
    foreach ($ext in $extensions) {
        $files = Get-ChildItem -Path $path -Filter $ext -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReadOnly }
        foreach ($f in $files) {
            $f.Attributes = $f.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
            $count++
        }
    }
    Write-Output "$path : Fixed $count read-only files"
    $totalFixed += $count
}

Write-Output ""
Write-Output "Total: $totalFixed files fixed"
