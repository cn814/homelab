$path = "C:\ProgramData\Jellyfin\Server\config\network.xml"
[xml]$xml = Get-Content $path

# Replace Docker subnet with actual LAN subnet
$subnets = $xml.NetworkConfiguration.LocalNetworkSubnets
$subnets.RemoveAll()
$newSubnet = $xml.CreateElement("string")
$newSubnet.InnerText = "192.168.86.0/24"
$subnets.AppendChild($newSubnet) | Out-Null

$xml.Save($path)
Write-Output "Updated LocalNetworkSubnets to 192.168.86.0/24"
