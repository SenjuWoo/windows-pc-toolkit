@echo off
title PC Gaming Optimizer v5.0.1
setlocal EnableExtensions DisableDelayedExpansion
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LOG=%LOCALAPPDATA%\Temp\GamingOptimizer_launch.log"
set "TOOLKIT_LAUNCHER=%~f0"
"%PS%" -NoProfile -Command "$p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 1"
if errorlevel 1 goto :elevate
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC_Optimizer.ps1" -ExpectedUserSid "%~1"
set "RC=%ERRORLEVEL%"
goto :finish
:elevate
"%PS%" -NoProfile -Command "try { $p=Start-Process -FilePath $env:TOOLKIT_LAUNCHER -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Error $_; exit 1 }" >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
:finish
echo [%date% %time%] PC_Optimizer.ps1 exited with %RC% >> "%LOG%"
if not "%RC%"=="0" (
    echo Toolkit exited with code %RC%. Log: %LOG%
    pause
)
exit /b %RC%
