@echo off
title PC Privacy Guard v2.0
setlocal EnableExtensions
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%LOCALAPPDATA%\Temp\PrivacyGuard_launch.log"
set "FLAG=%LOCALAPPDATA%\Temp\PrivacyGuard_elevated.flag"

net session >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] not elevated - requesting administrator rights >> "%LOG%"
    del "%FLAG%" >nul 2>&1
    "%PS%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >> "%LOG%" 2>&1
    "%SystemRoot%\System32\ping.exe" -n 7 127.0.0.1 >nul
    if not exist "%FLAG%" (
        echo [%date% %time%] elevation did not complete >> "%LOG%"
        echo.
        echo Elevation did not complete - no administrator window appeared.
        echo Right-click this .bat and choose "Run as administrator".
        echo Log: %LOG%
        pause
    )
    exit /b
)

echo [%date% %time%] elevated start >> "%LOG%"
echo elevated > "%FLAG%"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC_Privacy.ps1"
set "RC=%ERRORLEVEL%"
echo [%date% %time%] PC_Privacy.ps1 exited with %RC% >> "%LOG%"
if not "%RC%"=="0" (
    echo.
    echo PC Privacy Guard exited with code %RC%. Log: %LOG%
    pause
)
exit /b %RC%
