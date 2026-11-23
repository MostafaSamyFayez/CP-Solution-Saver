@echo off
title CP Solution Saver - Install
REM Double-click to install CP Solution Saver for the current user (no admin rights needed).
if not exist "%~dp0app\install.ps1" (
    echo.
    echo   The installer files were not found next to Install.bat.
    echo   If you opened the ZIP file directly, extract it first:
    echo   right-click the ZIP ^> Extract All... ^> open the extracted folder ^> double-click Install.bat
    echo.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\install.ps1" %*
echo.
pause
