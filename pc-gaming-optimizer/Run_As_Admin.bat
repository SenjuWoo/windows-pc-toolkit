@echo off
title PC Gaming Optimizer v3.3
color 0B

:: SECURITY: absolute path to powershell.exe so a rogue copy next to this
:: bat (or earlier on PATH) is never executed elevated.
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   Requesting Administrator privileges...
    echo.
    "%PS_EXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
echo.
echo  ====================================================
echo     PC GAMING OPTIMIZER v3.3 - Running as Admin
echo     Windows Update Safe  ^|  Sleep-safe long runs
echo  ====================================================
echo.

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC_Optimizer.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo  ====================================================
echo    Press any key to exit...
echo  ====================================================
pause >nul
exit /b %RC%
