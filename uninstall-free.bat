@echo off
:: ============================================================
::  Zokai Station Free — Windows Uninstaller
::  Double-click to uninstall. Preserves your workspace files.
:: ============================================================

setlocal EnableDelayedExpansion

:: Enable ANSI colors
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

title Zokai Station Free — Uninstaller

echo.
echo  [0;31m============================================================[0m
echo  [0;31m  Zokai Station Free ^| Uninstaller[0m
echo  [0;31m============================================================[0m
echo.

:: --- Check PowerShell is available ---
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo  [0;31m[ERROR][0m PowerShell is not available on this system.
    echo.
    pause
    exit /b 1
)

:: --- Launch the PowerShell uninstaller ---
:: Always look in the fixed install dir — the .bat may live in Documents or Desktop
set "INSTALL_DIR=%USERPROFILE%\AppData\Local\ZokaiStation-free"
if not exist "%INSTALL_DIR%\uninstall.ps1" (
    echo  [0;31m[ERROR][0m Cannot find uninstall.ps1 in %INSTALL_DIR%
    echo         Zokai Station may already be uninstalled.
    echo.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%\uninstall.ps1"

endlocal
exit /b 0
