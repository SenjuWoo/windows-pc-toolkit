@echo off
setlocal EnableExtensions
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
:menu
cls
echo ================================================================
echo   WINDOWS PC TOOLKIT
echo ================================================================
echo   [1] PC Corruption Fixer
echo   [2] PC Privacy Guard
echo   [3] Encrypted DNS Manager
echo   [4] PC Gaming Optimizer
echo   [5] Validate all scripts
echo   [0] Exit
echo.
set /p "choice=Select [0-5]: "
if "%choice%"=="1" call "%~dp0pc-corruption-fixer\Fix_Corruption.bat"
if "%choice%"=="2" call "%~dp0pc-privacy-guard\Run_As_Admin.bat"
if "%choice%"=="3" call "%~dp0dns-encrypted-doh\DNS_Encrypted_Manager.bat"
if "%choice%"=="4" call "%~dp0pc-gaming-optimizer\Run_As_Admin.bat"
if "%choice%"=="5" "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Validate_All.ps1" & pause
if "%choice%"=="0" exit /b 0
goto menu
