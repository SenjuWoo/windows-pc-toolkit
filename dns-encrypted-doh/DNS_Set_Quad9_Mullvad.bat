@echo off
:: ============================================================
::  Set DNS -> Quad9 (primary) + Mullvad AdBlock (secondary)
::  WITH real DNS-over-HTTPS (encrypted HTTPS tunnel templates)
::  Auto-detects active adapters (Ethernet / Wi-Fi / etc.)
:: ============================================================
setlocal
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0DNS_Set_Encrypted_DoH.ps1"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    "%PS_EXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%SCRIPT%" (
    echo [ERROR] Missing: %SCRIPT%
    echo Place DNS_Set_Encrypted_DoH.ps1 next to this bat file.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   Encrypted DNS (DoH over HTTPS)
echo   Primary:    Quad9     https://dns.quad9.net/dns-query
echo   Secondary:  Mullvad   https://adblock.dns.mullvad.net/dns-query
echo ============================================================
echo.

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
if %RC% neq 0 (
    echo [FAILED] Exit code %RC%
) else (
    echo [OK] Encrypted DNS apply finished.
)
pause
exit /b %RC%
