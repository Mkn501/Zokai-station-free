@echo off
REM zokai-launcher.bat — Hidden-window wrapper for Zokai Station launcher
REM Double-clickable entry point. Hides the console window and delegates to PowerShell.
REM 
REM Why .bat instead of .ps1 directly?
REM   .ps1 files often open in Notepad or prompt for Execution Policy.
REM   .bat always launches correctly on double-click.
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0zokai-launcher.ps1"
