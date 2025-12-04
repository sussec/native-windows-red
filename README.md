# Native Windows Red Team Toolkit

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-5.1+-green?style=for-the-badge&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Purpose-Security%20Research-red?style=for-the-badge" alt="Purpose">
</p>

A comprehensive collection of **Living Off the Land** (LOL) techniques for Windows post-exploitation using only native Windows tools. No external binaries, no custom malware - just built-in Windows functionality used in creative ways.

## ⚠️ Legal Disclaimer

**This toolkit is intended for authorized security testing, red team engagements, penetration testing, and educational purposes only.** Unauthorized access to computer systems is illegal. Always obtain proper written authorization before testing any systems you do not own.

The author assumes no liability for misuse of this toolkit. By using these tools, you agree to use them responsibly and ethically.

## 🎯 What is "Living Off the Land"?

Living Off the Land (LOTL) refers to using legitimate, pre-installed Windows tools for offensive operations. This approach:

- **Avoids signature-based detection** - No custom binaries to flag
- **Bypasses application whitelisting** - Uses Microsoft-signed executables
- **Blends with normal activity** - Uses the same tools as IT administrators
- **Leaves minimal forensic artifacts** - No additional tools to discover

## 📁 Project Structure

```
native-windows-red/
├── recon/                    # Reconnaissance & enumeration
│   ├── Invoke-SystemRecon.ps1
│   ├── Invoke-ADEnum.ps1
│   ├── Invoke-NetworkRecon.ps1
│   └── native-enum.bat
├── credentials/              # Credential harvesting
│   ├── Invoke-CredentialHarvest.ps1
│   ├── Invoke-LsassDump.ps1
│   ├── Invoke-RegistryDump.ps1
│   ├── Invoke-Kerberoast.ps1
│   └── Invoke-CredentialSearch.ps1
├── lateral-movement/         # Lateral movement techniques
│   ├── Invoke-WMIExec.ps1
│   ├── Invoke-PSRemoting.ps1
│   ├── Invoke-DCOMExec.ps1
│   ├── Invoke-ScheduledTaskExec.ps1
│   └── Invoke-ServiceExec.ps1
├── persistence/              # Persistence mechanisms
│   ├── Invoke-RegistryPersistence.ps1
│   ├── Invoke-ScheduledTaskPersistence.ps1
│   ├── Invoke-WMIEventPersistence.ps1
│   └── Invoke-StartupPersistence.ps1
├── exfiltration/            # Data exfiltration
│   ├── Invoke-HTTPExfil.ps1
│   ├── Invoke-DNSExfil.ps1
│   ├── Invoke-BITSExfil.ps1
│   └── Invoke-SMBExfil.ps1
├── bypass/                  # Application whitelisting bypass
│   ├── Invoke-MSBuildBypass.ps1
│   ├── Invoke-RegsvcsRegasmBypass.ps1
│   └── Invoke-MshtaBypass.ps1
├── payloads/                # Payload templates
│   ├── msbuild/             # MSBuild XML payloads
│   ├── hta/                 # HTA application payloads
│   └── sct/                 # Scriptlet payloads
├── utils/                   # Utility functions
│   ├── NativeRed.psm1
│   └── helpers.ps1
└── NativeRed.ps1            # Main loader module
```

## 🚀 Quick Start

### Option 1: Load the Full Module

```powershell
# Import the main module
Import-Module .\NativeRed.ps1

# View available commands
Get-Command -Module NativeRed
```

### Option 2: Use Individual Scripts

```powershell
# Run a specific reconnaissance script
. .\recon\Invoke-SystemRecon.ps1
Invoke-SystemRecon -Verbose

# Run credential harvesting
. .\credentials\Invoke-CredentialSearch.ps1
Invoke-CredentialSearch -SearchPath C:\ -Verbose
```

### Option 3: Use Native Batch Scripts (No PowerShell)

```cmd
REM Run native enumeration without PowerShell
.\recon\native-enum.bat
```

## 📖 Module Documentation

### Reconnaissance

| Script | Description |
|--------|-------------|
| `Invoke-SystemRecon.ps1` | Comprehensive local system enumeration |
| `Invoke-ADEnum.ps1` | Active Directory enumeration using ADSI |
| `Invoke-NetworkRecon.ps1` | Network discovery and mapping |
| `native-enum.bat` | Pure cmd.exe enumeration (no PowerShell) |

### Credentials

| Script | Description |
|--------|-------------|
| `Invoke-LsassDump.ps1` | LSASS memory dump using comsvcs.dll |
| `Invoke-RegistryDump.ps1` | SAM/SYSTEM/SECURITY hive extraction |
| `Invoke-Kerberoast.ps1` | Request TGS tickets for offline cracking |
| `Invoke-CredentialSearch.ps1` | Search for credentials in files |

### Lateral Movement

| Script | Description |
|--------|-------------|
| `Invoke-WMIExec.ps1` | Remote execution via WMI |
| `Invoke-PSRemoting.ps1` | PowerShell Remoting wrapper |
| `Invoke-DCOMExec.ps1` | Execution via DCOM objects |
| `Invoke-ScheduledTaskExec.ps1` | Remote scheduled task creation |

### Persistence

| Script | Description |
|--------|-------------|
| `Invoke-RegistryPersistence.ps1` | Registry Run key persistence |
| `Invoke-ScheduledTaskPersistence.ps1` | Scheduled task persistence |
| `Invoke-WMIEventPersistence.ps1` | WMI event subscription persistence |

### Exfiltration

| Script | Description |
|--------|-------------|
| `Invoke-HTTPExfil.ps1` | HTTP/HTTPS data exfiltration |
| `Invoke-DNSExfil.ps1` | DNS tunneling exfiltration |
| `Invoke-BITSExfil.ps1` | BITS transfer exfiltration |

## 🔴 EDR Detection Reality (2025)

Many classic LOL techniques are now detected by modern EDR solutions. Key considerations:

### High-Risk (Loud) Techniques
- ⚠️ LSASS memory access (comsvcs.dll dumps)
- ⚠️ Registry hive dumps (SAM/SECURITY/SYSTEM)
- ⚠️ Certutil downloads
- ⚠️ Nltest/dsquery enumeration chains

### Moderate-Risk Techniques
- 🔶 WMI remote execution
- 🔶 PowerShell Remoting
- 🔶 Scheduled task creation

### Lower-Risk Techniques
- ✅ Native cmd.exe enumeration
- ✅ Standard file operations
- ✅ Normal network connections

### Recommendations for Real Engagements
1. Layer techniques with AMSI bypasses
2. Use direct syscalls where possible
3. Implement process injection
4. Match legitimate admin behavior patterns
5. Consider timing and operational context

## 🧪 Testing Environment

These scripts work perfectly in:
- Home lab environments
- Virtual machines without EDR
- Legacy systems (Windows 7/Server 2008)
- CTF competitions
- Security research environments

## 📚 References

- [LOLBAS Project](https://lolbas-project.github.io/) - Living Off The Land Binaries and Scripts
- [MITRE ATT&CK](https://attack.mitre.org/) - Adversarial Tactics and Techniques
- [Microsoft Documentation](https://docs.microsoft.com/) - Official Windows documentation

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with detailed description

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Anubhav Gain** ([@anubhavg-icpl](https://github.com/anubhavg-icpl))

---

<p align="center">
  <i>Use responsibly. Stay ethical. Happy hunting!</i>
</p>
