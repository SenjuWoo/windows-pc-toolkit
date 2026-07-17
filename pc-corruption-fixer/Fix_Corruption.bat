@echo off
title PC Corruption Fixer v6.3
color 0B

:: SECURITY: use the absolute path to powershell.exe so a rogue
:: powershell.exe next to this script (or earlier in PATH) is never used.
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: Self-elevate to Administrator, then launch the PowerShell script
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting Administrator privileges...
    "%PS_EXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC_Fixer.ps1"
set "RC=%ERRORLEVEL%"
exit /b %RC%
