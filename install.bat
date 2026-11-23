@echo off
REM Double-click to install CP Solution Saver for the current user (no admin needed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
