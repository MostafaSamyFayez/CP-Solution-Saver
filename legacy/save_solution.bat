@echo off
REM Double-click this (or run it from Visual Studio) to save main.cpp to your solutions repo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0save_solution.ps1" %*
echo.
pause
