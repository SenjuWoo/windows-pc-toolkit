@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%LOCALAPPDATA%\Temp\WindowsPCToolkit_launch.log"
"%PS%" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Toolkit.ps1" >"%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo Windows PC Toolkit could not start. Details: %LOG%
    type "%LOG%"
    pause
)
exit /b %RC%
