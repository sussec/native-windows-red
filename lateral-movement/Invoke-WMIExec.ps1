<#
.SYNOPSIS
    Execute commands on remote systems via WMI

.DESCRIPTION
    Uses Windows Management Instrumentation (WMI) for remote command execution.
    WMI is a legitimate Windows administration protocol enabled by default.

    Methods:
    - Win32_Process Create: Execute commands
    - Win32_ScheduledJob: Create scheduled jobs
    - Remote WMI queries for enumeration

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER ComputerName
    Target computer name or IP

.PARAMETER Command
    Command to execute

.PARAMETER Credential
    PSCredential object for authentication

.PARAMETER Username
    Username for authentication

.PARAMETER Password
    Password for authentication

.EXAMPLE
    Invoke-WMIExec -ComputerName TARGET-PC -Command "whoami"
    Invoke-WMIExec -ComputerName 192.168.1.100 -Command "powershell.exe -Command Get-Process" -Username DOMAIN\admin -Password P@ssw0rd
#>

function Invoke-WMIExec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Command,

        [PSCredential]$Credential,

        [string]$Username,
        [string]$Password,

        [string]$OutputFile = "C:\Windows\Temp\wmi_output_$([guid]::NewGuid().ToString().Substring(0,8)).txt"
    )

    Write-Host @"

============================================================
  WMI REMOTE EXECUTION
============================================================
  Target: $ComputerName
  Command: $Command
============================================================

"@ -ForegroundColor Cyan

    # Build credential if username/password provided
    if ($Username -and $Password -and -not $Credential) {
        $secPassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($Username, $secPassword)
    }

    # Test WMI connectivity
    Write-Host "[*] Testing WMI connectivity..." -ForegroundColor Yellow

    try {
        $testParams = @{
            ComputerName = $ComputerName
            Class        = 'Win32_OperatingSystem'
            ErrorAction  = 'Stop'
        }
        if ($Credential) {
            $testParams['Credential'] = $Credential
        }

        $os = Get-WmiObject @testParams
        Write-Host "[+] Connected to: $($os.CSName) ($($os.Caption))" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect via WMI: $_"
        return
    }

    # Execute command with output redirection
    $fullCommand = "cmd.exe /c $Command > $OutputFile 2>&1"

    Write-Host "[*] Executing command..." -ForegroundColor Yellow

    try {
        $processParams = @{
            ComputerName = $ComputerName
            Class        = 'Win32_Process'
            Name         = 'Create'
            ArgumentList = $fullCommand
            ErrorAction  = 'Stop'
        }
        if ($Credential) {
            $processParams['Credential'] = $Credential
        }

        $result = Invoke-WmiMethod @processParams

        if ($result.ReturnValue -eq 0) {
            Write-Host "[+] Command executed successfully (PID: $($result.ProcessId))" -ForegroundColor Green

            # Wait a moment for command to complete
            Start-Sleep -Seconds 2

            # Try to retrieve output
            $outputPath = "\\$ComputerName\C$\Windows\Temp\$(Split-Path $OutputFile -Leaf)"

            try {
                if (Test-Path $outputPath) {
                    Write-Host "[*] Retrieving output..." -ForegroundColor Yellow
                    $output = Get-Content $outputPath -Raw

                    Write-Host "`n--- OUTPUT ---" -ForegroundColor Cyan
                    Write-Host $output
                    Write-Host "--- END ---`n" -ForegroundColor Cyan

                    # Cleanup
                    Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[+] Output file cleaned up" -ForegroundColor Green

                    return $output
                }
                else {
                    Write-Warning "Output file not accessible via admin share. Check manually: $OutputFile"
                }
            }
            catch {
                Write-Warning "Could not retrieve output: $_"
                Write-Host "[*] Check output manually on target: $OutputFile" -ForegroundColor Yellow
            }
        }
        else {
            Write-Error "Command execution failed. Return value: $($result.ReturnValue)"
        }
    }
    catch {
        Write-Error "WMI execution failed: $_"
    }
}

function Invoke-WMIQuery {
    <#
    .SYNOPSIS
        Run WMI queries on remote systems

    .EXAMPLE
        Invoke-WMIQuery -ComputerName TARGET-PC -Class Win32_Process
        Invoke-WMIQuery -ComputerName TARGET-PC -Query "SELECT * FROM Win32_Service WHERE State='Running'"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$Class,
        [string]$Query,
        [string]$Namespace = "root\cimv2",

        [PSCredential]$Credential
    )

    $wmiParams = @{
        ComputerName = $ComputerName
        Namespace    = $Namespace
        ErrorAction  = 'Stop'
    }

    if ($Credential) {
        $wmiParams['Credential'] = $Credential
    }

    try {
        if ($Query) {
            $wmiParams['Query'] = $Query
            $results = Get-WmiObject @wmiParams
        }
        elseif ($Class) {
            $wmiParams['Class'] = $Class
            $results = Get-WmiObject @wmiParams
        }
        else {
            Write-Error "Specify either -Class or -Query"
            return
        }

        return $results
    }
    catch {
        Write-Error "WMI query failed: $_"
    }
}

function Get-RemoteProcesses {
    <#
    .SYNOPSIS
        List processes on remote system via WMI

    .EXAMPLE
        Get-RemoteProcesses -ComputerName TARGET-PC
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [PSCredential]$Credential
    )

    $params = @{
        ComputerName = $ComputerName
        Class        = 'Win32_Process'
    }
    if ($Credential) {
        $params['Credential'] = $Credential
    }

    try {
        $processes = Get-WmiObject @params | Select-Object ProcessName, ProcessId, CommandLine, CreationDate |
        Sort-Object ProcessName

        Write-Host "[+] Processes on $ComputerName`n" -ForegroundColor Green
        return $processes | Format-Table -AutoSize
    }
    catch {
        Write-Error "Failed to enumerate processes: $_"
    }
}

function Get-RemoteServices {
    <#
    .SYNOPSIS
        List services on remote system via WMI

    .EXAMPLE
        Get-RemoteServices -ComputerName TARGET-PC -Running
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [switch]$Running,

        [PSCredential]$Credential
    )

    $query = if ($Running) {
        "SELECT * FROM Win32_Service WHERE State='Running'"
    }
    else {
        "SELECT * FROM Win32_Service"
    }

    $params = @{
        ComputerName = $ComputerName
        Query        = $query
    }
    if ($Credential) {
        $params['Credential'] = $Credential
    }

    try {
        $services = Get-WmiObject @params | Select-Object Name, DisplayName, State, StartMode, PathName |
        Sort-Object Name

        Write-Host "[+] Services on $ComputerName`n" -ForegroundColor Green
        return $services | Format-Table -AutoSize
    }
    catch {
        Write-Error "Failed to enumerate services: $_"
    }
}

function Get-RemoteLoggedOnUsers {
    <#
    .SYNOPSIS
        Get currently logged on users on remote system

    .EXAMPLE
        Get-RemoteLoggedOnUsers -ComputerName TARGET-PC
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [PSCredential]$Credential
    )

    $params = @{
        ComputerName = $ComputerName
        Class        = 'Win32_ComputerSystem'
    }
    if ($Credential) {
        $params['Credential'] = $Credential
    }

    try {
        $cs = Get-WmiObject @params
        Write-Host "[+] Currently logged on: $($cs.UserName)" -ForegroundColor Green
        return $cs.UserName
    }
    catch {
        Write-Error "Failed to get logged on user: $_"
    }
}

# Export functions
Export-ModuleMember -Function Invoke-WMIExec, Invoke-WMIQuery, Get-RemoteProcesses, Get-RemoteServices, Get-RemoteLoggedOnUsers
