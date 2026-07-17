@echo off
title PC Privacy Guard v1.0
color 0D

:: SECURITY: absolute path to powershell.exe — never trust PATH or script folder.
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
echo     PC PRIVACY GUARD v1.0 - Running as Admin
echo     Location mask ^| Tracker kill ^| WU/Game safe
echo  ====================================================
echo.

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC_Privacy.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo  ====================================================
echo    Press any key to exit...
echo  ====================================================
pause >nul
exit /b %RC%
