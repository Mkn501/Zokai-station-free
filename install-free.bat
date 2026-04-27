@echo off
:: ============================================================
::  Zokai Station Free — Windows Installer Launcher
::  Double-click to install. Requires Docker Desktop.
:: ============================================================
:: This launcher bypasses PowerShell execution policy restrictions
:: so non-technical users don't get blocked by security prompts.

setlocal EnableDelayedExpansion

:: Enable ANSI colors on Windows 10+
for /f "tokens=4-5 delims=. " %%i in ('ver') do set WIN_VER=%%i.%%j
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

title Zokai Station Free — Installer

echo.
echo  [0;36m============================================================[0m
echo  [0;36m  Zokai Station Free ^| Windows Installer[0m
echo  [0;36m============================================================[0m
echo.

:: --- Check PowerShell is available ---
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo  [0;31m[ERROR][0m PowerShell is not available on this system.
    echo         Zokai Station requires Windows 10 or later.
    echo.
    pause
    exit /b 1
)

:: --- Check if running from the right directory ---
if not exist "%~dp0docker-compose.yml" (
    echo  [0;31m[ERROR][0m This file must be run from the Zokai Station folder.
    echo.
    echo  Expected to find docker-compose.yml in the same folder.
    echo  Please extract the downloaded zip and run install-free.bat from inside it.
    echo.
    pause
    exit /b 1
)

:: --- Check Docker Desktop is installed ---
set DOCKER_FOUND=0
if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" set DOCKER_FOUND=1
if exist "%LocalAppData%\Docker\Docker Desktop.exe" set DOCKER_FOUND=1
where docker.exe >nul 2>&1 && set DOCKER_FOUND=1

if "%DOCKER_FOUND%"=="0" (
    echo  [0;31m[ERROR][0m Docker Desktop is not installed.
    echo.
    echo  Zokai Station runs inside Docker containers.
    echo  Please install Docker Desktop first:
    echo.
    echo    https://www.docker.com/products/docker-desktop/
    echo.
    echo  After installing Docker Desktop, run this file again.
    echo.
    echo  [0;33m[TIP][0m  If Docker fails to start or you see "WSL" errors:
    echo         1. Press Start, type "cmd", right-click "Run as Administrator"
    echo         2. Run: wsl --update
    echo         3. Run: wsl --shutdown
    echo         4. Restart Docker Desktop
    echo.
    powershell -NoProfile -Command "Start-Process 'https://www.docker.com/products/docker-desktop/'"
    pause
    exit /b 1
)

:: --- Check docker daemon is running ---
docker info >nul 2>&1
if errorlevel 1 (
    echo  [0;33m[WAIT][0m  Starting Docker Desktop...
    echo.
    start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" 2>nul
    start "" "%LocalAppData%\Docker\Docker Desktop.exe" 2>nul

    :: Poll up to 120 seconds (Windows WSL2 startup can be slow)
    set /a WAITED=0
    :DOCKER_WAIT
    timeout /t 5 /nobreak >nul
    docker info >nul 2>&1 && goto DOCKER_READY
    set /a WAITED+=5
    echo  Waiting for Docker Desktop... (!WAITED!s)
    if !WAITED! geq 120 (
        echo.
        echo  [0;31m[ERROR][0m Docker Desktop did not start in time.
        echo         Please start Docker Desktop manually and run this file again.
        echo.
        echo  [0;33m[TIP][0m  If Docker Desktop is stuck, try:
        echo         1. Open Command Prompt as Administrator
        echo         2. Run: wsl --shutdown
        echo         3. Restart Docker Desktop
        echo.
        pause
        exit /b 1
    )
    goto DOCKER_WAIT
    :DOCKER_READY
    echo  [0;32m[OK][0m    Docker Desktop is running.
    echo.
)

:: --- Launch the PowerShell installer (bypasses execution policy) ---
echo  [0;34m[INFO][0m  Launching installer...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-free.ps1"

if errorlevel 1 (
    echo.
    echo  [0;31m[ERROR][0m Installation did not complete successfully.
    echo         Check install-free.log in this folder for details.
    echo.
    pause
    exit /b 1
)

endlocal
exit /b 0
