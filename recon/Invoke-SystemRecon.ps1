<#
.SYNOPSIS
    Comprehensive local system reconnaissance using native Windows tools

.DESCRIPTION
    Performs thorough enumeration of the local system including:
    - Operating system information
    - User and group enumeration
    - Running processes and services
    - Network configuration
    - Installed software
    - Security products

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER OutputPath
    Path to save output (optional)

.PARAMETER Brief
    Only show essential information

.EXAMPLE
    Invoke-SystemRecon
    Invoke-SystemRecon -OutputPath C:\temp\recon.txt -Verbose
#>

function Invoke-SystemRecon {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [switch]$Brief
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

    # ==================== SYSTEM INFORMATION ====================
    Write-Section "SYSTEM INFORMATION"

    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $cs = Get-WmiObject -Class Win32_ComputerSystem
        $bios = Get-WmiObject -Class Win32_BIOS

        $sysInfo = [PSCustomObject]@{
            ComputerName   = $env:COMPUTERNAME
            OSName         = $os.Caption
            OSVersion      = $os.Version
            OSBuild        = $os.BuildNumber
            Architecture   = $os.OSArchitecture
            InstallDate    = $os.ConvertToDateTime($os.InstallDate)
            LastBootTime   = $os.ConvertToDateTime($os.LastBootUpTime)
            Domain         = $cs.Domain
            PartOfDomain   = $cs.PartOfDomain
            Manufacturer   = $cs.Manufacturer
            Model          = $cs.Model
            TotalMemoryGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            SerialNumber   = $bios.SerialNumber
        }

        $results['SystemInfo'] = $sysInfo
        $sysInfo.PSObject.Properties | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name): $($_.Value)")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error gathering system info: $_")
    }

    # ==================== CURRENT USER ====================
    Write-Section "CURRENT USER CONTEXT"

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        $userContext = [PSCustomObject]@{
            Username      = $identity.Name
            SID           = $identity.User.Value
            IsAdmin       = $isAdmin
            LogonServer   = $env:LOGONSERVER
            UserProfile   = $env:USERPROFILE
            AuthType      = $identity.AuthenticationType
        }

        $results['UserContext'] = $userContext
        $userContext.PSObject.Properties | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name): $($_.Value)")
        }

        # User privileges
        [void]$output.AppendLine("`n  PRIVILEGES:")
        $whoamiOutput = whoami /priv 2>$null
        if ($whoamiOutput) {
            $whoamiOutput | Where-Object { $_ -match 'Se\w+Privilege' } | ForEach-Object {
                [void]$output.AppendLine("    $_")
            }
        }

        # Group memberships
        [void]$output.AppendLine("`n  GROUP MEMBERSHIPS:")
        $identity.Groups | ForEach-Object {
            try {
                $groupName = $_.Translate([Security.Principal.NTAccount])
                [void]$output.AppendLine("    $groupName")
            }
            catch { }
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error gathering user context: $_")
    }

    # ==================== LOCAL USERS ====================
    Write-Section "LOCAL USERS"

    try {
        $localUsers = Get-LocalUser -ErrorAction SilentlyContinue | Select-Object Name, Enabled, LastLogon, PasswordLastSet, Description

        $results['LocalUsers'] = $localUsers
        $localUsers | ForEach-Object {
            [void]$output.AppendLine("  [$($_.Name)]")
            [void]$output.AppendLine("    Enabled: $($_.Enabled)")
            [void]$output.AppendLine("    LastLogon: $($_.LastLogon)")
            [void]$output.AppendLine("    PwdLastSet: $($_.PasswordLastSet)")
            if ($_.Description) { [void]$output.AppendLine("    Description: $($_.Description)") }
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Cannot enumerate local users (may require admin)")
    }

    # ==================== LOCAL GROUPS ====================
    Write-Section "LOCAL ADMINISTRATORS"

    try {
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue

        $results['LocalAdmins'] = $admins
        $admins | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name) ($($_.ObjectClass))")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Cannot enumerate administrators (may require admin)")
    }

    if (-not $Brief) {
        # ==================== RUNNING PROCESSES ====================
        Write-Section "RUNNING PROCESSES"

        try {
            $processes = Get-Process | Select-Object ProcessName, Id, Path, Company |
            Sort-Object ProcessName -Unique

            $results['Processes'] = $processes
            $processes | ForEach-Object {
                [void]$output.AppendLine("  [$($_.Id)] $($_.ProcessName)")
                if ($_.Path) { [void]$output.AppendLine("        Path: $($_.Path)") }
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating processes: $_")
        }

        # ==================== SERVICES ====================
        Write-Section "RUNNING SERVICES (as SYSTEM)"

        try {
            $services = Get-WmiObject win32_service |
            Where-Object { $_.State -eq "Running" -and $_.StartName -like "*SYSTEM*" } |
            Select-Object Name, DisplayName, PathName, StartMode

            $results['Services'] = $services
            $services | ForEach-Object {
                [void]$output.AppendLine("  [$($_.Name)] $($_.DisplayName)")
                [void]$output.AppendLine("        Path: $($_.PathName)")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating services: $_")
        }

        # ==================== UNQUOTED SERVICE PATHS ====================
        Write-Section "UNQUOTED SERVICE PATHS (Potential Privesc)"

        try {
            $unquoted = Get-WmiObject win32_service | Where-Object {
                $_.PathName -notlike '"*' -and
                $_.PathName -like '* *' -and
                $_.PathName -notlike 'C:\Windows\*'
            } | Select-Object Name, PathName, StartName, State

            if ($unquoted) {
                $results['UnquotedPaths'] = $unquoted
                $unquoted | ForEach-Object {
                    [void]$output.AppendLine("  [!] $($_.Name)")
                    [void]$output.AppendLine("      Path: $($_.PathName)")
                    [void]$output.AppendLine("      RunAs: $($_.StartName)")
                }
            }
            else {
                [void]$output.AppendLine("  No unquoted service paths found")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error checking unquoted paths: $_")
        }
    }

    # ==================== NETWORK CONFIGURATION ====================
    Write-Section "NETWORK CONFIGURATION"

    try {
        $netConfig = Get-NetIPConfiguration -ErrorAction SilentlyContinue

        $results['NetworkConfig'] = $netConfig
        $netConfig | ForEach-Object {
            [void]$output.AppendLine("  Interface: $($_.InterfaceAlias)")
            [void]$output.AppendLine("    IPv4: $($_.IPv4Address.IPAddress)")
            [void]$output.AppendLine("    Gateway: $($_.IPv4DefaultGateway.NextHop)")
            [void]$output.AppendLine("    DNS: $($_.DNSServer.ServerAddresses -join ', ')")
        }
    }
    catch {
        # Fallback to ipconfig
        [void]$output.AppendLine((ipconfig /all | Out-String))
    }

    # ==================== NETWORK CONNECTIONS ====================
    Write-Section "ESTABLISHED NETWORK CONNECTIONS"

    try {
        $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess |
        Sort-Object RemoteAddress

        $results['Connections'] = $connections
        $connections | ForEach-Object {
            $procName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            [void]$output.AppendLine("  $($_.LocalAddress):$($_.LocalPort) -> $($_.RemoteAddress):$($_.RemotePort) [$procName]")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error enumerating connections: $_")
    }

    # ==================== ARP CACHE ====================
    Write-Section "ARP CACHE (Recent Communications)"

    try {
        $arp = Get-NetNeighbor -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne "Unreachable" -and $_.State -ne "Incomplete" } |
        Select-Object IPAddress, LinkLayerAddress, State

        $results['ARPCache'] = $arp
        $arp | ForEach-Object {
            [void]$output.AppendLine("  $($_.IPAddress) -> $($_.LinkLayerAddress) ($($_.State))")
        }
    }
    catch {
        [void]$output.AppendLine((arp -a | Out-String))
    }

    # ==================== INSTALLED SOFTWARE ====================
    Write-Section "INSTALLED SOFTWARE"

    try {
        $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName

        # Also check 32-bit on 64-bit systems
        $software += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher

        $results['Software'] = $software | Select-Object -Unique DisplayName, DisplayVersion, Publisher

        $results['Software'] | ForEach-Object {
            [void]$output.AppendLine("  $($_.DisplayName) v$($_.DisplayVersion)")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error enumerating software: $_")
    }

    # ==================== SECURITY PRODUCTS ====================
    Write-Section "SECURITY PRODUCTS"

    try {
        $av = Get-WmiObject -Namespace root\SecurityCenter2 -Class AntiVirusProduct -ErrorAction SilentlyContinue

        if ($av) {
            $results['AntiVirus'] = $av
            $av | ForEach-Object {
                [void]$output.AppendLine("  AV: $($_.displayName)")
                [void]$output.AppendLine("    Path: $($_.pathToSignedProductExe)")
            }
        }
        else {
            [void]$output.AppendLine("  No antivirus found via SecurityCenter2")
        }

        # Check for common EDR processes
        $edrProcesses = @(
            'MsMpEng', 'CrowdStrike', 'csfalconservice', 'cb', 'CbDefense',
            'SentinelAgent', 'cyserver', 'CylanceSvc', 'xagt', 'TmListen'
        )

        $running = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        $foundEDR = $edrProcesses | Where-Object { $running -contains $_ }

        if ($foundEDR) {
            [void]$output.AppendLine("`n  EDR Processes Detected:")
            $foundEDR | ForEach-Object { [void]$output.AppendLine("    [!] $_") }
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error querying security products: $_")
    }

    # ==================== SCHEDULED TASKS ====================
    if (-not $Brief) {
        Write-Section "SCHEDULED TASKS (Non-Microsoft)"

        try {
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -eq 'Ready' } |
            Select-Object TaskName, TaskPath, State

            $results['ScheduledTasks'] = $tasks
            $tasks | ForEach-Object {
                [void]$output.AppendLine("  $($_.TaskPath)$($_.TaskName) [$($_.State)]")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating scheduled tasks: $_")
        }
    }

    # ==================== ENVIRONMENT VARIABLES ====================
    Write-Section "INTERESTING ENVIRONMENT VARIABLES"

    $interestingVars = @(
        'PATH', 'PATHEXT', 'TEMP', 'TMP', 'USERDOMAIN', 'USERDNSDOMAIN',
        'LOGONSERVER', 'HOMEPATH', 'COMPUTERNAME', 'PROCESSOR_ARCHITECTURE'
    )

    $interestingVars | ForEach-Object {
        $value = [Environment]::GetEnvironmentVariable($_)
        if ($value) {
            [void]$output.AppendLine("  $_=$value")
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

# Export function
Export-ModuleMember -Function Invoke-SystemRecon
