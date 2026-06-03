<#
.SYNOPSIS
    Native Windows Red Team Toolkit - Main Loader Module

.DESCRIPTION
    Loads all Native Windows Red Team modules for post-exploitation operations
    using only built-in Windows tools and utilities.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.NOTES
    Version: 1.0.0
    Requires: PowerShell 5.1+
    Platform: Windows

.EXAMPLE
    Import-Module .\NativeRed.ps1
    Get-Command -Module NativeRed
#>

#Requires -Version 5.1

# Module manifest
$script:ModuleInfo = @{
    Name        = 'NativeRed'
    Version     = '1.0.0'
    Author      = 'Anubhav Gain'
    Description = 'Native Windows Red Team Toolkit'
}

# Get script root directory
$script:ModuleRoot = $PSScriptRoot

# Display banner
function Show-Banner {
    $banner = @"

    _   _       _   _           ____          _
   | \ | | __ _| |_(_)_   _____|  _ \ ___  __| |
   |  \| |/ _` | __| \ \ / / _ \ |_) / _ \/ _` |
   | |\  | (_| | |_| |\ V /  __/  _ <  __/ (_| |
   |_| \_|\__,_|\__|_| \_/ \___|_| \_\___|\__,_|

   Windows Living Off the Land Toolkit v$($script:ModuleInfo.Version)
   Author: $($script:ModuleInfo.Author)

"@
    Write-Host $banner -ForegroundColor Red
    Write-Host "   [!] For authorized security testing only!`n" -ForegroundColor Yellow
}

# Load all module scripts
function Initialize-NativeRed {
    [CmdletBinding()]
    param()

    Show-Banner

    $modulePaths = @(
        'recon',
        'lateral-movement',
        'persistence',
        'exfiltration',
        'bypass',
        'utils'
    )

    $loadedCount = 0

    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $script:ModuleRoot $modulePath
        if (Test-Path $fullPath) {
            $scripts = Get-ChildItem -Path $fullPath -Filter "*.ps1" -ErrorAction SilentlyContinue
            foreach ($scriptFile in $scripts) {
                try {
                    . $scriptFile.FullName
                    $loadedCount++
                    Write-Verbose "Loaded: $($scriptFile.Name)"
                }
                catch {
                    Write-Warning "Failed to load $($scriptFile.Name): $_"
                }
            }
        }
    }

    Write-Host "[+] Loaded $loadedCount modules successfully`n" -ForegroundColor Green
}

# Quick help function
function Get-NativeRedHelp {
    [CmdletBinding()]
    param()

    $helpText = @"

=== Native Windows Red Team Toolkit ===

RECONNAISSANCE:
  Invoke-SystemRecon       - Local system enumeration
  Invoke-ADEnum            - Active Directory enumeration
  Invoke-NetworkRecon      - Network discovery and mapping
  New-PortForward          - Create netsh port forward for pivoting
  Remove-AllPortForwards   - Remove all port forwards

LATERAL MOVEMENT:
  Invoke-WMIExec           - Execute commands via WMI
  Invoke-WMIQuery          - Run WMI queries on remote systems
  Get-RemoteProcesses      - List processes on remote system
  Get-RemoteServices       - List services on remote system
  Get-RemoteLoggedOnUsers  - Get logged on users on remote system
  Invoke-PSRemoting        - PowerShell Remoting wrapper
  New-PersistentSession    - Create persistent PSSession
  Copy-ToRemote            - Copy file to remote system
  Copy-FromRemote          - Copy file from remote system
  Invoke-ParallelCommand   - Execute on multiple targets in parallel
  Invoke-DCOMExec          - Execute via DCOM objects (MMC20, ShellWindows, ShellBrowserWindow)
  Test-DCOMAccess          - Test DCOM accessibility on remote target
  Invoke-ExcelDCOM         - Execute command via Excel DCOM
  Invoke-ScheduledTaskExec - Remote scheduled task execution
  Invoke-PowerShellScheduledTask - Scheduled task via CIM sessions
  Get-RemoteScheduledTasks - List scheduled tasks on remote system
  Invoke-ServiceExec       - Service-based execution (runs as SYSTEM)
  Set-ServiceBinaryPath    - Modify service binary path
  Find-VulnerableServices  - Find services with weak permissions

PERSISTENCE:
  Invoke-RegistryPersistence      - Registry Run key persistence
  Get-RegistryPersistence         - List all registry persistence entries
  New-HiddenRegistryKey           - Create null-byte hidden registry key
  Invoke-ScheduledTaskPersistence - Scheduled task persistence
  Get-SuspiciousScheduledTasks    - Find suspicious scheduled tasks
  Invoke-WMIEventPersistence      - WMI event subscription persistence
  Get-WMIEventSubscriptions       - List WMI event subscriptions
  Remove-AllWMIPersistence        - Remove all WMI subscriptions
  Invoke-StartupPersistence       - Startup folder persistence
  Get-StartupItems                - List all startup folder items

EXFILTRATION:
  Invoke-HTTPExfil         - HTTP/HTTPS data exfiltration (chunked)
  Invoke-WebClientExfil    - Upload via System.Net.WebClient
  Start-SimpleHTTPServer   - Start HTTP listener for receiving data
  Invoke-DNSExfil          - DNS tunneling exfiltration
  New-DNSExfilServer       - DNS exfil receiver setup instructions
  Invoke-BITSExfil         - BITS transfer exfiltration (upload/download)
  Get-BITSJobs             - List all BITS jobs
  Remove-BITSJob           - Cancel a BITS job
  Invoke-SMBExfil          - SMB-based exfiltration
  Get-RemoteShares         - Enumerate shares on remote system
  Test-ShareAccess         - Test read/write access to a share
  Invoke-CertutilExfil     - certutil file transfer (high detection risk)

BYPASS:
  Invoke-MSBuildBypass     - Execute code via MSBuild inline C# task
  New-MSBuildPayload       - Generate MSBuild XML payload
  New-MSBuildReverseShell  - Generate MSBuild reverse shell payload
  Invoke-MshtaBypass       - Execute code via Mshta (HTA/VBScript)
  New-HTAPayload           - Generate HTA payload
  New-HTAReverseShell      - Generate HTA reverse shell payload
  New-SCTPayload           - Generate SCT scriptlet for regsvr32 bypass

UTILITIES:
  Test-AdminPrivileges     - Check if running as admin
  Get-SecurityProducts     - Enumerate security products (AV/EDR)
  Convert-ToBase64         - Encode string or file to Base64
  Convert-FromBase64       - Decode Base64 string
  Get-RandomString         - Generate random string
  New-EncryptedPayload     - XOR encrypt a payload string
  Invoke-EncryptedPayload  - Decrypt and execute XOR payload
  Get-DomainInfo           - Get basic domain information
  Write-Log                - Write timestamped log entry
  ConvertTo-HexString      - Convert bytes to hex string
  ConvertFrom-HexString    - Convert hex string to bytes
  Get-NativeRedHelp        - Show this help
  nrhelp                   - Alias for Get-NativeRedHelp

For detailed help on any function:
  Get-Help <FunctionName> -Full

"@
    Write-Host $helpText
}

# Export alias for help
Set-Alias -Name nrhelp -Value Get-NativeRedHelp

# Initialize module on import
Initialize-NativeRed

# Export functions
Export-ModuleMember -Function * -Alias *
