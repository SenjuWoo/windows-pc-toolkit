@echo off
title DNS: Apply Quad9
setlocal EnableExtensions DisableDelayedExpansion
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%LOCALAPPDATA%\Temp\DNSManager_launch.log"
"%PS%" -NoProfile -Command "$p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 1 }"
if errorlevel 1 goto Elevate

echo [%date% %time%] elevated start >> "%LOG%"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0DNS_Manager.ps1" -Action Quad9
set "RC=%ERRORLEVEL%"
echo [%date% %time%] toolkit exited with %RC% >> "%LOG%"
if not "%RC%"=="0" (
    echo Toolkit exited with code %RC%. Log: %LOG%
    pause
)
exit /b %RC%

:Elevate
set "TOOLKIT_LAUNCHER=%~f0"
echo [%date% %time%] requesting administrator rights >> "%LOG%"
"%PS%" -NoProfile -Command "try { $p=Start-Process -FilePath $env:TOOLKIT_LAUNCHER -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }" >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo Elevation or the toolkit failed. Log: %LOG%
    pause
)
exit /b %RC%
