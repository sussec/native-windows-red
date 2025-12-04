<#
.SYNOPSIS
    Active Directory enumeration using native Windows tools

.DESCRIPTION
    Performs Active Directory reconnaissance without requiring the ActiveDirectory
    PowerShell module. Uses ADSI (Active Directory Service Interfaces) and
    built-in Windows commands.

.AUTHOR
    Anubhav Gain (@anubhavg-icpl)

.PARAMETER Domain
    Target domain (defaults to current domain)

.PARAMETER OutputPath
    Path to save output

.PARAMETER Quick
    Only enumerate essential objects

.EXAMPLE
    Invoke-ADEnum
    Invoke-ADEnum -Domain corp.local -OutputPath C:\temp\ad-enum.txt
#>

function Invoke-ADEnum {
    [CmdletBinding()]
    param(
        [string]$Domain,
        [string]$OutputPath,
        [switch]$Quick
    )

    # Check if domain-joined
    $cs = Get-WmiObject -Class Win32_ComputerSystem
    if (-not $cs.PartOfDomain) {
        Write-Error "System is not domain-joined. Cannot perform AD enumeration."
        return
    }

    if (-not $Domain) {
        $Domain = $cs.Domain
    }

    $results = [ordered]@{}
    $output = New-Object System.Text.StringBuilder

    function Write-Section {
        param([string]$Title)
        [void]$output.AppendLine("`n" + "=" * 60)
        [void]$output.AppendLine("  $Title")
        [void]$output.AppendLine("=" * 60)
        Write-Verbose $Title
    }

    function Get-LDAPPath {
        param([string]$DomainName)
        $parts = $DomainName.Split('.')
        $ldapPath = ($parts | ForEach-Object { "DC=$_" }) -join ','
        return $ldapPath
    }

    $ldapPath = Get-LDAPPath -DomainName $Domain

    # ==================== DOMAIN INFORMATION ====================
    Write-Section "DOMAIN INFORMATION"

    try {
        $domainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()

        $domainInfo = [PSCustomObject]@{
            DomainName             = $domainObj.Name
            Forest                 = $domainObj.Forest.Name
            DomainMode             = $domainObj.DomainMode
            Parent                 = $domainObj.Parent
            Children               = $domainObj.Children | ForEach-Object { $_.Name }
            DomainControllerCount  = $domainObj.DomainControllers.Count
            PDCEmulator            = $domainObj.PdcRoleOwner
        }

        $results['DomainInfo'] = $domainInfo
        $domainInfo.PSObject.Properties | ForEach-Object {
            [void]$output.AppendLine("  $($_.Name): $($_.Value)")
        }
    }
    catch {
        [void]$output.AppendLine("  [!] Error getting domain info: $_")
    }

    # ==================== DOMAIN CONTROLLERS ====================
    Write-Section "DOMAIN CONTROLLERS"

    try {
        $dcs = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().DomainControllers

        $results['DomainControllers'] = @()
        foreach ($dc in $dcs) {
            $dcInfo = [PSCustomObject]@{
                Name       = $dc.Name
                IPAddress  = $dc.IPAddress
                OSVersion  = $dc.OSVersion
                Roles      = ($dc.Roles | ForEach-Object { $_.ToString() }) -join ', '
                SiteName   = $dc.SiteName
            }
            $results['DomainControllers'] += $dcInfo
            [void]$output.AppendLine("  [$($dc.Name)]")
            [void]$output.AppendLine("    IP: $($dc.IPAddress)")
            [void]$output.AppendLine("    OS: $($dc.OSVersion)")
            [void]$output.AppendLine("    Site: $($dc.SiteName)")
        }
    }
    catch {
        # Fallback to nltest
        [void]$output.AppendLine((nltest /dclist:$Domain 2>$null | Out-String))
    }

    # ==================== DOMAIN TRUSTS ====================
    Write-Section "DOMAIN TRUSTS"

    try {
        $trustOutput = nltest /domain_trusts 2>$null
        [void]$output.AppendLine($trustOutput | Out-String)
        $results['DomainTrusts'] = $trustOutput
    }
    catch {
        [void]$output.AppendLine("  [!] Error enumerating trusts")
    }

    # ==================== DOMAIN ADMINS ====================
    Write-Section "DOMAIN ADMINS"

    try {
        $searcher = [ADSISearcher]"(&(objectClass=group)(cn=Domain Admins))"
        $daGroup = $searcher.FindOne()

        if ($daGroup) {
            $members = $daGroup.Properties['member']
            $results['DomainAdmins'] = @()

            foreach ($member in $members) {
                $userSearcher = [ADSISearcher]"(distinguishedName=$member)"
                $user = $userSearcher.FindOne()
                if ($user) {
                    $username = $user.Properties['samaccountname'][0]
                    $results['DomainAdmins'] += $username
                    [void]$output.AppendLine("  $username")
                }
            }
        }
    }
    catch {
        # Fallback to net group
        [void]$output.AppendLine((net group "Domain Admins" /domain 2>$null | Out-String))
    }

    # ==================== ENTERPRISE ADMINS ====================
    Write-Section "ENTERPRISE ADMINS"

    try {
        $searcher = [ADSISearcher]"(&(objectClass=group)(cn=Enterprise Admins))"
        $eaGroup = $searcher.FindOne()

        if ($eaGroup) {
            $members = $eaGroup.Properties['member']
            $results['EnterpriseAdmins'] = @()

            foreach ($member in $members) {
                $userSearcher = [ADSISearcher]"(distinguishedName=$member)"
                $user = $userSearcher.FindOne()
                if ($user) {
                    $username = $user.Properties['samaccountname'][0]
                    $results['EnterpriseAdmins'] += $username
                    [void]$output.AppendLine("  $username")
                }
            }
        }
    }
    catch {
        [void]$output.AppendLine((net group "Enterprise Admins" /domain 2>$null | Out-String))
    }

    if (-not $Quick) {
        # ==================== ALL DOMAIN USERS ====================
        Write-Section "DOMAIN USERS (First 100)"

        try {
            $searcher = [ADSISearcher]"(&(objectClass=user)(objectCategory=person))"
            $searcher.PropertiesToLoad.AddRange(@('samaccountname', 'displayname', 'mail', 'pwdlastset', 'lastlogon', 'admincount'))
            $searcher.PageSize = 100

            $users = $searcher.FindAll()
            $results['DomainUsers'] = @()

            $count = 0
            foreach ($user in $users) {
                if ($count -ge 100) { break }
                $count++

                $pwdLastSet = if ($user.Properties['pwdlastset'][0]) {
                    [DateTime]::FromFileTime([Int64]$user.Properties['pwdlastset'][0])
                }
                else { $null }

                $lastLogon = if ($user.Properties['lastlogon'][0]) {
                    [DateTime]::FromFileTime([Int64]$user.Properties['lastlogon'][0])
                }
                else { $null }

                $userObj = [PSCustomObject]@{
                    Username    = $user.Properties['samaccountname'][0]
                    DisplayName = $user.Properties['displayname'][0]
                    Email       = $user.Properties['mail'][0]
                    PwdLastSet  = $pwdLastSet
                    LastLogon   = $lastLogon
                    AdminCount  = $user.Properties['admincount'][0]
                }

                $results['DomainUsers'] += $userObj
                [void]$output.AppendLine("  $($userObj.Username) - $($userObj.DisplayName)")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating users: $_")
        }

        # ==================== DOMAIN COMPUTERS ====================
        Write-Section "DOMAIN COMPUTERS (First 100)"

        try {
            $searcher = [ADSISearcher]"(objectClass=computer)"
            $searcher.PropertiesToLoad.AddRange(@('name', 'operatingsystem', 'operatingsystemversion', 'lastlogon'))
            $searcher.PageSize = 100

            $computers = $searcher.FindAll()
            $results['DomainComputers'] = @()

            $count = 0
            foreach ($comp in $computers) {
                if ($count -ge 100) { break }
                $count++

                $compObj = [PSCustomObject]@{
                    Name    = $comp.Properties['name'][0]
                    OS      = $comp.Properties['operatingsystem'][0]
                    Version = $comp.Properties['operatingsystemversion'][0]
                }

                $results['DomainComputers'] += $compObj
                [void]$output.AppendLine("  $($compObj.Name) - $($compObj.OS)")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating computers: $_")
        }

        # ==================== SERVICE ACCOUNTS (SPNs) ====================
        Write-Section "ACCOUNTS WITH SPNs (Kerberoastable)"

        try {
            $searcher = [ADSISearcher]"(&(servicePrincipalName=*)(objectCategory=person))"
            $searcher.PropertiesToLoad.AddRange(@('samaccountname', 'serviceprincipalname', 'pwdlastset'))

            $spnUsers = $searcher.FindAll()
            $results['SPNAccounts'] = @()

            foreach ($user in $spnUsers) {
                $spnObj = [PSCustomObject]@{
                    Username = $user.Properties['samaccountname'][0]
                    SPNs     = $user.Properties['serviceprincipalname'] -join '; '
                }

                $results['SPNAccounts'] += $spnObj
                [void]$output.AppendLine("  [!] $($spnObj.Username)")
                [void]$output.AppendLine("      SPNs: $($spnObj.SPNs)")
            }

            if ($spnUsers.Count -eq 0) {
                [void]$output.AppendLine("  No user accounts with SPNs found")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating SPNs: $_")
        }

        # ==================== PRIVILEGED ACCOUNTS ====================
        Write-Section "ACCOUNTS WITH adminCount=1"

        try {
            $searcher = [ADSISearcher]"(&(objectClass=user)(adminCount=1))"
            $searcher.PropertiesToLoad.AddRange(@('samaccountname', 'whencreated'))

            $privUsers = $searcher.FindAll()
            $results['PrivilegedAccounts'] = @()

            foreach ($user in $privUsers) {
                $username = $user.Properties['samaccountname'][0]
                $results['PrivilegedAccounts'] += $username
                [void]$output.AppendLine("  $username")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating privileged accounts: $_")
        }

        # ==================== PASSWORD NEVER EXPIRES ====================
        Write-Section "ACCOUNTS WITH PASSWORD NEVER EXPIRES"

        try {
            # UserAccountControl 65536 = DONT_EXPIRE_PASSWORD
            $searcher = [ADSISearcher]"(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=65536))"
            $searcher.PropertiesToLoad.AddRange(@('samaccountname', 'pwdlastset'))

            $neverExpire = $searcher.FindAll()
            $results['PasswordNeverExpires'] = @()

            foreach ($user in $neverExpire) {
                $username = $user.Properties['samaccountname'][0]
                $results['PasswordNeverExpires'] += $username
                [void]$output.AppendLine("  $username")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error: $_")
        }

        # ==================== DISABLED ACCOUNTS ====================
        Write-Section "DISABLED USER ACCOUNTS"

        try {
            # UserAccountControl 2 = ACCOUNTDISABLE
            $searcher = [ADSISearcher]"(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))"
            $searcher.PropertiesToLoad.AddRange(@('samaccountname'))

            $disabled = $searcher.FindAll()
            [void]$output.AppendLine("  Found $($disabled.Count) disabled accounts")
        }
        catch {
            [void]$output.AppendLine("  [!] Error: $_")
        }

        # ==================== DOMAIN PASSWORD POLICY ====================
        Write-Section "DOMAIN PASSWORD POLICY"

        try {
            $policy = net accounts /domain 2>$null
            [void]$output.AppendLine($policy | Out-String)
        }
        catch {
            [void]$output.AppendLine("  [!] Error getting password policy")
        }

        # ==================== ORGANIZATIONAL UNITS ====================
        Write-Section "ORGANIZATIONAL UNITS"

        try {
            $searcher = [ADSISearcher]"(objectClass=organizationalUnit)"
            $searcher.PropertiesToLoad.AddRange(@('name', 'distinguishedname'))

            $ous = $searcher.FindAll()
            $results['OUs'] = @()

            foreach ($ou in $ous) {
                $ouName = $ou.Properties['distinguishedname'][0]
                $results['OUs'] += $ouName
                [void]$output.AppendLine("  $ouName")
            }
        }
        catch {
            [void]$output.AppendLine("  [!] Error enumerating OUs: $_")
        }
    }

    # ==================== OUTPUT ====================
    $finalOutput = $output.ToString()

    if ($OutputPath) {
        $finalOutput | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "[+] Output saved to: $OutputPath" -ForegroundColor Green
    }
    else {
        Write-Host $finalOutput
    }

    return $results
}

# Export function
Export-ModuleMember -Function Invoke-ADEnum
