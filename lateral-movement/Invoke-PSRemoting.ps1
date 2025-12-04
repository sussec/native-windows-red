<#
.SYNOPSIS
    PowerShell Remoting wrapper for lateral movement

.DESCRIPTION
    Provides easy-to-use functions for executing commands on remote systems
    via PowerShell Remoting (WinRM). Includes interactive sessions,
    script execution, and multi-target operations.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.NOTES
    Requires WinRM enabled on target (default on modern Windows)
    Port 5985 (HTTP) or 5986 (HTTPS)

.EXAMPLE
    Invoke-PSRemoting -ComputerName TARGET-PC -ScriptBlock { Get-Process }
    Invoke-PSRemoting -ComputerName TARGET-PC -Interactive
#>

function Invoke-PSRemoting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [scriptblock]$ScriptBlock,

        [string]$ScriptPath,

        [switch]$Interactive,

        [PSCredential]$Credential,

        [string]$Username,
        [string]$Password
    )

    Write-Host @"

============================================================
  POWERSHELL REMOTING
============================================================
  Target(s): $($ComputerName -join ', ')
  Method: WinRM (HTTP:5985, HTTPS:5986)
============================================================

"@ -ForegroundColor Cyan

    # Build credential if needed
    if ($Username -and $Password -and -not $Credential) {
        $secPassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($Username, $secPassword)
    }

    # Test connectivity
    foreach ($target in $ComputerName) {
        Write-Host "[*] Testing WinRM connectivity to $target..." -ForegroundColor Yellow

        try {
            $testParams = @{ ComputerName = $target }
            if ($Credential) { $testParams['Credential'] = $Credential }

            $result = Test-WSMan @testParams -ErrorAction Stop
            Write-Host "[+] WinRM available on $target" -ForegroundColor Green
        }
        catch {
            Write-Warning "WinRM not accessible on $target`: $_"
            continue
        }
    }

    if ($Interactive) {
        # Start interactive session
        if ($ComputerName.Count -gt 1) {
            Write-Warning "Interactive mode only supports single target. Using first: $($ComputerName[0])"
        }

        Write-Host "[*] Starting interactive session to $($ComputerName[0])..." -ForegroundColor Yellow
        Write-Host "[*] Type 'exit' to end the session" -ForegroundColor Yellow

        $sessionParams = @{ ComputerName = $ComputerName[0] }
        if ($Credential) { $sessionParams['Credential'] = $Credential }

        Enter-PSSession @sessionParams
    }
    elseif ($ScriptPath) {
        # Execute local script on remote
        if (-not (Test-Path $ScriptPath)) {
            Write-Error "Script not found: $ScriptPath"
            return
        }

        Write-Host "[*] Executing script on targets..." -ForegroundColor Yellow

        $invokeParams = @{
            ComputerName = $ComputerName
            FilePath     = $ScriptPath
            ErrorAction  = 'Stop'
        }
        if ($Credential) { $invokeParams['Credential'] = $Credential }

        try {
            $results = Invoke-Command @invokeParams
            return $results
        }
        catch {
            Write-Error "Script execution failed: $_"
        }
    }
    elseif ($ScriptBlock) {
        # Execute scriptblock
        Write-Host "[*] Executing command on targets..." -ForegroundColor Yellow

        $invokeParams = @{
            ComputerName = $ComputerName
            ScriptBlock  = $ScriptBlock
            ErrorAction  = 'Stop'
        }
        if ($Credential) { $invokeParams['Credential'] = $Credential }

        try {
            $results = Invoke-Command @invokeParams

            foreach ($result in $results) {
                Write-Host "`n--- [$($result.PSComputerName)] ---" -ForegroundColor Cyan
                Write-Output $result
            }

            return $results
        }
        catch {
            Write-Error "Command execution failed: $_"
        }
    }
    else {
        Write-Error "Specify -ScriptBlock, -ScriptPath, or -Interactive"
    }
}

function New-PersistentSession {
    <#
    .SYNOPSIS
        Create persistent PSSession for multiple commands

    .EXAMPLE
        $session = New-PersistentSession -ComputerName TARGET-PC
        Invoke-Command -Session $session -ScriptBlock { Get-Process }
        Remove-PSSession $session
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [PSCredential]$Credential
    )

    $sessionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }
    if ($Credential) {
        $sessionParams['Credential'] = $Credential
    }

    try {
        $session = New-PSSession @sessionParams
        Write-Host "[+] Session created: $($session.Id) -> $ComputerName" -ForegroundColor Green
        Write-Host "[*] Use: Invoke-Command -Session `$session -ScriptBlock { ... }" -ForegroundColor Yellow
        return $session
    }
    catch {
        Write-Error "Failed to create session: $_"
    }
}

function Copy-ToRemote {
    <#
    .SYNOPSIS
        Copy file to remote system via PSRemoting

    .EXAMPLE
        Copy-ToRemote -ComputerName TARGET-PC -LocalPath C:\tools\script.ps1 -RemotePath C:\temp\script.ps1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$RemotePath,

        [PSCredential]$Credential
    )

    if (-not (Test-Path $LocalPath)) {
        Write-Error "Local file not found: $LocalPath"
        return
    }

    Write-Host "[*] Copying $LocalPath to $ComputerName`:$RemotePath" -ForegroundColor Yellow

    try {
        $sessionParams = @{ ComputerName = $ComputerName }
        if ($Credential) { $sessionParams['Credential'] = $Credential }

        $session = New-PSSession @sessionParams

        Copy-Item -Path $LocalPath -Destination $RemotePath -ToSession $session -Force

        Remove-PSSession $session

        Write-Host "[+] File copied successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Copy failed: $_"
    }
}

function Copy-FromRemote {
    <#
    .SYNOPSIS
        Copy file from remote system via PSRemoting

    .EXAMPLE
        Copy-FromRemote -ComputerName TARGET-PC -RemotePath C:\secrets\data.txt -LocalPath C:\loot\data.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$RemotePath,

        [Parameter(Mandatory)]
        [string]$LocalPath,

        [PSCredential]$Credential
    )

    Write-Host "[*] Copying $ComputerName`:$RemotePath to $LocalPath" -ForegroundColor Yellow

    try {
        $sessionParams = @{ ComputerName = $ComputerName }
        if ($Credential) { $sessionParams['Credential'] = $Credential }

        $session = New-PSSession @sessionParams

        Copy-Item -Path $RemotePath -Destination $LocalPath -FromSession $session -Force

        Remove-PSSession $session

        Write-Host "[+] File copied successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Copy failed: $_"
    }
}

function Invoke-ParallelCommand {
    <#
    .SYNOPSIS
        Execute command on multiple targets in parallel

    .EXAMPLE
        Invoke-ParallelCommand -ComputerName @("PC1", "PC2", "PC3") -ScriptBlock { hostname }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [PSCredential]$Credential,

        [int]$ThrottleLimit = 32
    )

    Write-Host "[*] Executing on $($ComputerName.Count) targets (throttle: $ThrottleLimit)..." -ForegroundColor Yellow

    $invokeParams = @{
        ComputerName  = $ComputerName
        ScriptBlock   = $ScriptBlock
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'remoteErrors'
    }
    if ($Credential) { $invokeParams['Credential'] = $Credential }

    $results = Invoke-Command @invokeParams

    # Report results
    Write-Host "`n[+] Successful: $($results.Count)" -ForegroundColor Green
    Write-Host "[-] Failed: $($remoteErrors.Count)" -ForegroundColor $(if ($remoteErrors.Count -gt 0) { 'Red' } else { 'Green' })

    return $results
}

# Export functions
Export-ModuleMember -Function Invoke-PSRemoting, New-PersistentSession, Copy-ToRemote, Copy-FromRemote, Invoke-ParallelCommand
