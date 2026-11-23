@echo off
REM Runs the self-tests (uses a temporary repo; does not touch your real repo).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Run-Tests.ps1" -Online
echo.
pause
