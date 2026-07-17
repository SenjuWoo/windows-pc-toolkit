@echo off
title VR / PCVR Repair

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :isAdmin
)

:: Not admin - self-elevate (-NoProfile: don't run user profile scripts elevated)
echo.
echo   Requesting Administrator privileges...
echo.
PowerShell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:isAdmin
cd /d "%~dp0"
echo.
echo  ====================================================
echo     VR / PCVR REPAIR - Running as Admin
echo     Reverts only the VR-hostile optimizer settings
echo  ====================================================
echo.

PowerShell -NoProfile -ExecutionPolicy Bypass -File "Fix_VR_PCVR.ps1"
