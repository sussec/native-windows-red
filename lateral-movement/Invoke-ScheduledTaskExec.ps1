<#
.SYNOPSIS
    Execute commands on remote systems via scheduled tasks

.DESCRIPTION
    Creates scheduled tasks on remote systems for command execution.
    Tasks can be run immediately or scheduled for a specific time.
    Uses native schtasks.exe utility.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER ComputerName
    Target computer name or IP

.PARAMETER Command
    Command to execute

.PARAMETER TaskName
    Name for the scheduled task (default: random)

.PARAMETER RunAsSystem
    Run task as SYSTEM (default: current user)

.EXAMPLE
    Invoke-ScheduledTaskExec -ComputerName TARGET-PC -Command "whoami > C:\temp\out.txt"
    Invoke-ScheduledTaskExec -ComputerName TARGET-PC -Command "powershell.exe -Command Get-Process" -RunAsSystem
#>

function Invoke-ScheduledTaskExec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Command,

        [string]$TaskName = "WinUpdate$([guid]::NewGuid().ToString().Substring(0,8))",

        [switch]$RunAsSystem,

        [string]$Username,
        [string]$Password,

        [switch]$NoCleanup
    )

    Write-Host @"

============================================================
  SCHEDULED TASK REMOTE EXECUTION
============================================================
  Target: $ComputerName
  Task: $TaskName
  Command: $Command
  Run As: $(if ($RunAsSystem) { 'SYSTEM' } else { 'Current User' })
============================================================

"@ -ForegroundColor Cyan

    # Build schtasks command
    $createArgs = "/create /tn `"$TaskName`" /tr `"$Command`" /sc once /st 00:00 /S $ComputerName"

    if ($RunAsSystem) {
        $createArgs += " /ru SYSTEM"
    }

    if ($Username) {
        $createArgs += " /U $Username"
        if ($Password) {
            $createArgs += " /P $Password"
        }
    }

    Write-Host "[*] Creating scheduled task..." -ForegroundColor Yellow

    try {
        # Create the task
        $result = schtasks.exe $createArgs.Split(' ') 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create task: $result"
        }

        Write-Host "[+] Task created successfully" -ForegroundColor Green

        # Run the task immediately
        Write-Host "[*] Executing task..." -ForegroundColor Yellow

        $runArgs = @("/run", "/tn", $TaskName, "/S", $ComputerName)
        if ($Username) {
            $runArgs += @("/U", $Username)
            if ($Password) {
                $runArgs += @("/P", $Password)
            }
        }

        $result = schtasks.exe @runArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] Task executed successfully" -ForegroundColor Green
        }
        else {
            Write-Warning "Task execution may have failed: $result"
        }

        # Wait a moment for execution
        Start-Sleep -Seconds 2

        # Clean up if requested
        if (-not $NoCleanup) {
            Write-Host "[*] Cleaning up task..." -ForegroundColor Yellow

            $deleteArgs = @("/delete", "/tn", $TaskName, "/S", $ComputerName, "/F")
            if ($Username) {
                $deleteArgs += @("/U", $Username)
                if ($Password) {
                    $deleteArgs += @("/P", $Password)
                }
            }

            $result = schtasks.exe @deleteArgs 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Task deleted" -ForegroundColor Green
            }
            else {
                Write-Warning "Failed to delete task: $result"
            }
        }
        else {
            Write-Host @"

[!] Task NOT deleted. Clean up manually:
    schtasks /delete /tn "$TaskName" /S $ComputerName /F
"@ -ForegroundColor Yellow
        }

        return $true
    }
    catch {
        Write-Error "Scheduled task execution failed: $_"
        return $false
    }
}

function Invoke-PowerShellScheduledTask {
    <#
    .SYNOPSIS
        Create scheduled task using PowerShell cmdlets (more options)

    .EXAMPLE
        Invoke-PowerShellScheduledTask -ComputerName TARGET-PC -ScriptBlock { Get-Process }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$TaskName = "PSUpdate$([guid]::NewGuid().ToString().Substring(0,8))",

        [switch]$RunAsSystem,

        [PSCredential]$Credential
    )

    # Convert scriptblock to base64 encoded command
    $encodedCommand = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($ScriptBlock.ToString())
    )

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -EncodedCommand $encodedCommand"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    }
    else {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden

    Write-Host "[*] Creating scheduled task via CIM..." -ForegroundColor Yellow

    try {
        $cimParams = @{ ComputerName = $ComputerName }
        if ($Credential) { $cimParams['Credential'] = $Credential }

        $cimSession = New-CimSession @cimParams

        Register-ScheduledTask -CimSession $cimSession -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings

        Write-Host "[+] Task registered" -ForegroundColor Green

        # Run immediately
        Start-ScheduledTask -CimSession $cimSession -TaskName $TaskName

        Write-Host "[+] Task started" -ForegroundColor Green

        # Wait and cleanup
        Start-Sleep -Seconds 5

        Unregister-ScheduledTask -CimSession $cimSession -TaskName $TaskName -Confirm:$false

        Write-Host "[+] Task cleaned up" -ForegroundColor Green

        Remove-CimSession $cimSession
    }
    catch {
        Write-Error "PowerShell scheduled task failed: $_"
    }
}

function Get-RemoteScheduledTasks {
    <#
    .SYNOPSIS
        List scheduled tasks on remote system

    .EXAMPLE
        Get-RemoteScheduledTasks -ComputerName TARGET-PC
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$Username,
        [string]$Password
    )

    $queryArgs = @("/query", "/S", $ComputerName, "/FO", "CSV")

    if ($Username) {
        $queryArgs += @("/U", $Username)
        if ($Password) {
            $queryArgs += @("/P", $Password)
        }
    }

    try {
        $result = schtasks.exe @queryArgs 2>&1

        if ($result) {
            # Convert CSV output to objects
            $tasks = $result | ConvertFrom-Csv
            return $tasks | Format-Table -AutoSize
        }
    }
    catch {
        Write-Error "Failed to query scheduled tasks: $_"
    }
}

# Export functions
Export-ModuleMember -Function Invoke-ScheduledTaskExec, Invoke-PowerShellScheduledTask, Get-RemoteScheduledTasks
