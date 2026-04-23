$files = Get-ChildItem -Path "D:\Movies", "E:\Movies" -Recurse -Filter "*Gabby*Dollhouse*" -ErrorAction SilentlyContinue
if ($files.Count -eq 0) {
    $files = Get-ChildItem -Path "D:\Movies", "E:\Movies" -Recurse -Filter "*Gabby*" -ErrorAction SilentlyContinue
}
foreach ($f in $files) {
    Write-Output "File: $($f.FullName)"
    Write-Output "Size: $([math]::Round($f.Length / 1GB, 2)) GB"
    Write-Output ""
}
if ($files.Count -gt 0) {
    $file = $files[0].FullName
    & docker exec jellyfin ffprobe -v quiet -show_streams -print_format json "$($file -replace 'D:\\','/data/' -replace 'E:\\','/data2/' -replace '\\','/')" 2>$null
}
