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
        'credentials',
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
  Invoke-NetworkRecon      - Network discovery

CREDENTIALS:
  Invoke-LsassDump         - Dump LSASS memory (requires admin)
  Invoke-RegistryDump      - Extract SAM/SYSTEM/SECURITY hives
  Invoke-Kerberoast        - Request TGS tickets for cracking
  Invoke-CredentialSearch  - Search for credentials in files

LATERAL MOVEMENT:
  Invoke-WMIExec           - Execute commands via WMI
  Invoke-PSRemoting        - PowerShell Remoting wrapper
  Invoke-DCOMExec          - Execute via DCOM objects
  Invoke-ScheduledTaskExec - Remote scheduled task execution
  Invoke-ServiceExec       - Service-based execution

PERSISTENCE:
  Invoke-RegistryPersistence      - Registry Run key persistence
  Invoke-ScheduledTaskPersistence - Scheduled task persistence
  Invoke-WMIEventPersistence      - WMI event subscription persistence
  Invoke-StartupPersistence       - Startup folder persistence

EXFILTRATION:
  Invoke-HTTPExfil         - HTTP/HTTPS exfiltration
  Invoke-DNSExfil          - DNS tunneling exfiltration
  Invoke-BITSExfil         - BITS transfer exfiltration
  Invoke-SMBExfil          - SMB-based exfiltration

BYPASS:
  Invoke-MSBuildBypass     - Execute code via MSBuild
  Invoke-MshtaBypass       - Execute code via Mshta
  New-MSBuildPayload       - Generate MSBuild payloads
  New-HTAPayload           - Generate HTA payloads

UTILITIES:
  Get-NativeRedHelp        - Show this help
  Test-AdminPrivileges     - Check if running as admin
  Get-SecurityProducts     - Enumerate security products

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
