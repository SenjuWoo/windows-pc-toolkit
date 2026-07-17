@echo off
:: ============================================================
::  Revert DNS to DHCP (automatic) + clear custom DoH templates
::  Auto-detects active adapters (Ethernet / Wi-Fi / etc.)
:: ============================================================
setlocal
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0DNS_Revert_DHCP.ps1"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    "%PS_EXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%SCRIPT%" (
    echo [ERROR] Missing: %SCRIPT%
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   Reverting DNS to DHCP + clearing DoH HTTPS templates
echo ============================================================
echo.

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
if %RC% neq 0 (
    echo [FAILED] Exit code %RC%
) else (
    echo [OK] DNS reverted to automatic.
)
pause
exit /b %RC%
