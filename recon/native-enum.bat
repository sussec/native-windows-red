@echo off
REM ============================================================
REM Native Windows Enumeration Script (No PowerShell)
REM Author: Anubhav Gain (@anubhavg-icpl)
REM
REM This script performs system reconnaissance using only
REM built-in cmd.exe commands. Useful when PowerShell is
REM blocked, logged, or unavailable.
REM ============================================================

echo.
echo ============================================================
echo       Native Windows Enumeration Script
echo       No PowerShell Required
echo ============================================================
echo.

REM ==================== SYSTEM INFORMATION ====================
echo.
echo [*] SYSTEM INFORMATION
echo ============================================================

echo Computer Name: %COMPUTERNAME%
echo Domain: %USERDOMAIN%
echo DNS Domain: %USERDNSDOMAIN%
echo Logon Server: %LOGONSERVER%
echo User: %USERNAME%
echo User Profile: %USERPROFILE%

echo.
echo --- OS Details ---
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Type" /C:"Domain"

echo.
echo --- Hotfixes ---
wmic qfe list brief

REM ==================== CURRENT USER ====================
echo.
echo [*] CURRENT USER CONTEXT
echo ============================================================

echo.
echo --- User Information ---
whoami

echo.
echo --- User Privileges ---
whoami /priv

echo.
echo --- User Groups ---
whoami /groups

echo.
echo --- User SID ---
whoami /user

REM ==================== LOCAL USERS AND GROUPS ====================
echo.
echo [*] LOCAL USERS AND GROUPS
echo ============================================================

echo.
echo --- Local Users ---
net user

echo.
echo --- Local Administrators ---
net localgroup administrators

echo.
echo --- All Local Groups ---
net localgroup

REM ==================== DOMAIN INFORMATION ====================
echo.
echo [*] DOMAIN INFORMATION
echo ============================================================

echo.
echo --- Domain Controllers ---
nltest /dclist:%USERDOMAIN% 2>nul

echo.
echo --- Domain Trusts ---
nltest /domain_trusts 2>nul

echo.
echo --- Domain Users ---
net user /domain 2>nul | more

echo.
echo --- Domain Admins ---
net group "Domain Admins" /domain 2>nul

echo.
echo --- Enterprise Admins ---
net group "Enterprise Admins" /domain 2>nul

echo.
echo --- Domain Password Policy ---
net accounts /domain 2>nul

REM ==================== NETWORK CONFIGURATION ====================
echo.
echo [*] NETWORK CONFIGURATION
echo ============================================================

echo.
echo --- IP Configuration ---
ipconfig /all

echo.
echo --- Routing Table ---
route print

echo.
echo --- ARP Cache ---
arp -a

echo.
echo --- DNS Cache ---
ipconfig /displaydns | findstr "Record"

echo.
echo --- Network Connections ---
netstat -ano

echo.
echo --- Listening Ports ---
netstat -ano | findstr LISTEN

echo.
echo --- Established Connections ---
netstat -ano | findstr ESTABLISHED

REM ==================== RUNNING PROCESSES ====================
echo.
echo [*] RUNNING PROCESSES
echo ============================================================

echo.
echo --- Process List ---
tasklist /V

echo.
echo --- Services Running ---
net start

echo.
echo --- All Services ---
wmic service get name,displayname,state,startmode,pathname | findstr "Running"

REM ==================== INTERESTING FILES ====================
echo.
echo [*] INTERESTING FILE LOCATIONS
echo ============================================================

echo.
echo --- Unattend Files ---
dir /s /b C:\unattend.xml C:\sysprep.xml C:\autounattend.xml 2>nul
dir /s /b C:\Windows\Panther\unattend.xml 2>nul

echo.
echo --- PowerShell History ---
type %USERPROFILE%\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt 2>nul

echo.
echo --- SAM and SYSTEM Locations ---
echo Check: C:\Windows\System32\config\SAM
echo Check: C:\Windows\System32\config\SYSTEM
echo Check: C:\Windows\repair\SAM

REM ==================== SCHEDULED TASKS ====================
echo.
echo [*] SCHEDULED TASKS
echo ============================================================

schtasks /query /fo LIST /v | findstr /i "taskname task to run"

REM ==================== INSTALLED SOFTWARE ====================
echo.
echo [*] INSTALLED SOFTWARE
echo ============================================================

wmic product get name,version 2>nul

REM Alternative using reg
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s | findstr "DisplayName DisplayVersion"

REM ==================== SECURITY PRODUCTS ====================
echo.
echo [*] SECURITY PRODUCTS
echo ============================================================

echo.
echo --- Antivirus ---
wmic /namespace:\\root\SecurityCenter2 path AntiVirusProduct get displayName,pathToSignedProductExe 2>nul

echo.
echo --- Firewall Status ---
netsh advfirewall show allprofiles state

REM ==================== SHARES ====================
echo.
echo [*] NETWORK SHARES
echo ============================================================

echo.
echo --- Local Shares ---
net share

echo.
echo --- Mapped Drives ---
net use

REM ==================== SERVICES WITH UNQUOTED PATHS ====================
echo.
echo [*] POTENTIAL UNQUOTED SERVICE PATHS
echo ============================================================

wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "C:\Windows\\" | findstr /i /v """

REM ==================== WIFI CREDENTIALS ====================
echo.
echo [*] WIFI PROFILES
echo ============================================================

netsh wlan show profiles 2>nul

REM Note: To get WiFi passwords, run:
REM netsh wlan show profile name="SSID" key=clear

REM ==================== CREDENTIALS ====================
echo.
echo [*] STORED CREDENTIALS
echo ============================================================

cmdkey /list

REM ==================== ENVIRONMENT VARIABLES ====================
echo.
echo [*] ENVIRONMENT VARIABLES
echo ============================================================

set

REM ==================== COMPLETION ====================
echo.
echo ============================================================
echo [+] Enumeration Complete
echo ============================================================
echo.
echo To save output, run: native-enum.bat ^> output.txt 2^>^&1
echo.

pause
