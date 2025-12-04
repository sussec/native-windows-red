<#
.SYNOPSIS
    Network reconnaissance and discovery using native Windows tools

.DESCRIPTION
    Performs network enumeration including:
    - Interface configuration
    - ARP cache analysis
    - DNS configuration
    - Open ports and connections
    - Share enumeration
    - Subnet scanning
    - Network pivoting setup (netsh)

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER ScanSubnet
    Perform subnet ping sweep (noisy)

.PARAMETER EnumerateShares
    Enumerate network shares on discovered hosts

.PARAMETER OutputPath
    Path to save output

.EXAMPLE
    Invoke-NetworkRecon
    Invoke-NetworkRecon -ScanSubnet -EnumerateShares
#>

function Invoke-NetworkRecon {
    [CmdletBinding()]
    param(
        [switch]$ScanSubnet,
        [switch]$EnumerateShares,
        [string]$OutputPath
    )

    $results = [ordered]@{}
    $output = New-Object System.Text.StringBuilder

    function Write-Section {
        param([string]$Title)
        [void]$output.AppendLine("`n" + "=" * 60)
        [void]$output.AppendLine("  $Title")
        [void]$output.AppendLine("=" * 60)
        Write-Verbose $Title
    }

    # ==================== NETWORK INTERFACES ====================
    Write-Section "NETWORK INTERFACES"

    try {
        $interfaces = Get-NetIPConfiguration -ErrorAction SilentlyContinue

        $results['Interfaces'] = @()
        foreach ($iface in $interfaces) {
            $ifaceInfo = [PSCustomObject]@{
                Name          = $iface.InterfaceAlias
                Index         = $iface.InterfaceIndex
                IPv4Address   = $iface.IPv4Address.IPAddress
                IPv4Subnet    = $iface.IPv4Address.PrefixLength
                IPv6Address   = $iface.IPv6Address.IPAddress
                Gateway       = $iface.IPv4DefaultGateway.NextHop
                DNS           = $iface.DNSServer.ServerAddresses -join ', '
                MACAddress    = (Get-NetAdapter -InterfaceIndex $iface.InterfaceIndex -ErrorAction SilentlyContinue).MacAddress
            }

            $results['Interfaces'] += $ifaceInfo
            [void]$output.AppendLine("  [$($ifaceInfo.Name)]")
            [void]$output.AppendLine("    IPv4: $($ifaceInfo.IPv4Address)/$($ifaceInfo.IPv4Subnet)")
            [void]$output.AppendLine("    Gateway: $($ifaceInfo.Gateway)")
            [void]$output.AppendLine("    DNS: $($ifaceInfo.DNS)")
            [void]$output.AppendLine("    MAC: $($ifaceInfo.MACAddress)")
        }
    }
    catch {
        [void]$output.AppendLine((ipconfig /all | Out-String))
    }

    # ==================== ROUTING TABLE ====================
    Write-Section "ROUTING TABLE"

    try {
        $routes = Get-NetRoute -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.NextHop -ne '::' } |
        Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias

        $results['Routes'] = $routes
        $routes | ForEach-Object {
            [void]$output.AppendLine("  $($_.DestinationPrefix) -> $($_.NextHop) [$($_.InterfaceAlias)]")
        }
    }
    catch {
        [void]$output.AppendLine((route print | Out-String))
    }

    # ==================== ARP CACHE ====================
    Write-Section "ARP CACHE (Recent Communications)"

    try {
        $arpCache = Get-NetNeighbor -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Reachable' -or $_.State -eq 'Stale' } |
        Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias

        $results['ARPCache'] = $arpCache
        $arpCache | ForEach-Object {
            [void]$output.AppendLine("  $($_.IPAddress) -> $($_.LinkLayerAddress) [$($_.State)]")
        }
    }
    catch {
        [void]$output.AppendLine((arp -a | Out-String))
    }

    # ==================== DNS CACHE ====================
    Write-Section "DNS CACHE"

    try {
        $dnsCache = Get-DnsClientCache -ErrorAction SilentlyContinue |
        Select-Object Name, Type, TTL, Data |
        Sort-Object Name -Unique

        $results['DNSCache'] = $dnsCache
        $dnsCache | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name) -> $($_.Data) [TTL: $($_.TTL)]")
        }
    }
    catch {
        [void]$output.AppendLine((ipconfig /displaydns | Out-String))
    }

    # ==================== LISTENING PORTS ====================
    Write-Section "LISTENING PORTS"

    try {
        $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess |
        Sort-Object LocalPort

        $results['ListeningPorts'] = @()
        $listening | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            $portInfo = [PSCustomObject]@{
                Address = $_.LocalAddress
                Port    = $_.LocalPort
                Process = $proc.ProcessName
                PID     = $_.OwningProcess
            }
            $results['ListeningPorts'] += $portInfo
            [void]$output.AppendLine("  $($_.LocalAddress):$($_.LocalPort) [$($proc.ProcessName)]")
        }
    }
    catch {
        [void]$output.AppendLine((netstat -ano | findstr LISTEN | Out-String))
    }

    # ==================== ESTABLISHED CONNECTIONS ====================
    Write-Section "ESTABLISHED CONNECTIONS"

    try {
        $established = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess |
        Sort-Object RemoteAddress

        $results['EstablishedConnections'] = @()
        $established | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            $connInfo = [PSCustomObject]@{
                Local   = "$($_.LocalAddress):$($_.LocalPort)"
                Remote  = "$($_.RemoteAddress):$($_.RemotePort)"
                Process = $proc.ProcessName
            }
            $results['EstablishedConnections'] += $connInfo
            [void]$output.AppendLine("  $($connInfo.Local) -> $($connInfo.Remote) [$($connInfo.Process)]")
        }
    }
    catch {
        [void]$output.AppendLine((netstat -ano | findstr ESTABLISHED | Out-String))
    }

    # ==================== FIREWALL STATUS ====================
    Write-Section "FIREWALL STATUS"

    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue |
        Select-Object Name, Enabled

        $results['FirewallStatus'] = $fwProfiles
        $fwProfiles | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name): $($_.Enabled)")
        }
    }
    catch {
        [void]$output.AppendLine((netsh advfirewall show allprofiles state | Out-String))
    }

    # ==================== NETWORK SHARES (LOCAL) ====================
    Write-Section "LOCAL NETWORK SHARES"

    try {
        $shares = Get-SmbShare -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*$' } |
        Select-Object Name, Path, Description

        $results['LocalShares'] = $shares
        $shares | ForEach-Object {
            [void]$output.AppendLine("  \\$env:COMPUTERNAME\$($_.Name)")
            [void]$output.AppendLine("    Path: $($_.Path)")
        }
    }
    catch {
        [void]$output.AppendLine((net share | Out-String))
    }

    # ==================== WIFI PROFILES ====================
    Write-Section "WIFI PROFILES"

    try {
        $profiles = netsh wlan show profiles 2>$null
        if ($profiles) {
            $profileNames = ($profiles | Select-String "All User Profile") | ForEach-Object {
                $_.ToString().Split(':')[1].Trim()
            }

            $results['WifiProfiles'] = @()
            foreach ($profile in $profileNames) {
                if ($profile) {
                    $keyContent = netsh wlan show profile name="$profile" key=clear 2>$null |
                    Select-String "Key Content"

                    $password = if ($keyContent) { $keyContent.ToString().Split(':')[1].Trim() } else { "N/A" }

                    $wifiInfo = [PSCustomObject]@{
                        SSID     = $profile
                        Password = $password
                    }
                    $results['WifiProfiles'] += $wifiInfo
                    [void]$output.AppendLine("  $profile : $password")
                }
            }
        }
        else {
            [void]$output.AppendLine("  No WiFi profiles found or WiFi not available")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error enumerating WiFi profiles: $_")
    }

    # ==================== PORT FORWARDING RULES ====================
    Write-Section "EXISTING PORT FORWARDS (netsh)"

    try {
        $portProxy = netsh interface portproxy show all 2>$null
        if ($portProxy) {
            [void]$output.AppendLine($portProxy | Out-String)
        }
        else {
            [void]$output.AppendLine("  No port forwarding rules configured")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error checking port forwards")
    }

    # ==================== SUBNET SCAN ====================
    if ($ScanSubnet) {
        Write-Section "SUBNET PING SWEEP (Active Scan)"
        Write-Warning "Performing subnet scan - this is noisy and may trigger alerts!"

        try {
            $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
                Select-Object -First 1).IPAddress

            if ($localIP) {
                $subnet = $localIP -replace '\.\d+$', ''

                [void]$output.AppendLine("  Scanning $subnet.0/24...")

                $results['LiveHosts'] = @()
                $jobs = @()

                # Create runspace pool for parallel scanning
                1..254 | ForEach-Object {
                    $ip = "$subnet.$_"
                    if (Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 1) {
                        $hostname = try { [System.Net.Dns]::GetHostEntry($ip).HostName } catch { "N/A" }
                        $hostInfo = [PSCustomObject]@{
                            IPAddress = $ip
                            Hostname  = $hostname
                        }
                        $results['LiveHosts'] += $hostInfo
                        [void]$output.AppendLine("  [+] $ip ($hostname)")
                    }
                }
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error during subnet scan: $_")
        }
    }

    # ==================== SHARE ENUMERATION ====================
    if ($EnumerateShares -and $results['LiveHosts']) {
        Write-Section "REMOTE SHARE ENUMERATION"

        foreach ($host in $results['LiveHosts']) {
            try {
                [void]$output.AppendLine("  [$($host.IPAddress)]")
                $shares = net view \\$($host.IPAddress) 2>$null
                if ($shares) {
                    [void]$output.AppendLine($shares | Out-String)
                }
            }
            catch {
                [void]$output.AppendLine("    No shares accessible")
            }
        }
    }

    # ==================== OUTPUT ====================
    $finalOutput = $output.ToString()

    if ($OutputPath) {
        $finalOutput | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "[+] Output saved to: $OutputPath" -ForegroundColor Green
    }
    else {
        Write-Host $finalOutput
    }

    return $results
}

# Helper function to set up port forwarding
function New-PortForward {
    <#
    .SYNOPSIS
        Create netsh port forward for pivoting

    .PARAMETER ListenPort
        Port to listen on locally

    .PARAMETER TargetAddress
        Target IP address

    .PARAMETER TargetPort
        Target port

    .EXAMPLE
        New-PortForward -ListenPort 8080 -TargetAddress 10.10.10.50 -TargetPort 80
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ListenPort,

        [Parameter(Mandatory)]
        [string]$TargetAddress,

        [Parameter(Mandatory)]
        [int]$TargetPort
    )

    $cmd = "netsh interface portproxy add v4tov4 listenport=$ListenPort listenaddress=0.0.0.0 connectport=$TargetPort connectaddress=$TargetAddress"

    Write-Host "[*] Creating port forward: 0.0.0.0:$ListenPort -> ${TargetAddress}:$TargetPort" -ForegroundColor Yellow

    try {
        Invoke-Expression $cmd
        Write-Host "[+] Port forward created successfully" -ForegroundColor Green
        Write-Host "[*] To remove: netsh interface portproxy delete v4tov4 listenport=$ListenPort listenaddress=0.0.0.0" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to create port forward: $_"
    }
}

function Remove-AllPortForwards {
    <#
    .SYNOPSIS
        Remove all netsh port forwards

    .EXAMPLE
        Remove-AllPortForwards
    #>
    [CmdletBinding()]
    param()

    Write-Host "[*] Removing all port forwards..." -ForegroundColor Yellow
    netsh interface portproxy reset
    Write-Host "[+] All port forwards removed" -ForegroundColor Green
}

# Export functions
Export-ModuleMember -Function Invoke-NetworkRecon, New-PortForward, Remove-AllPortForwards
