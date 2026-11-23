@echo off
REM Double-click to install (or update) CP Solution Saver for the current user. No admin rights needed.
REM   Install.bat            the setup window (normal use)
REM   Install.bat -Console   the same steps in this console window
REM   Install.bat -Quiet     no questions, no tour (updates / scripts)
if not exist "%~dp0app\install.ps1" (
    echo.
    echo   The installer files were not found next to Install.bat.
    echo   If you opened the ZIP file directly, extract it first:
    echo   right-click the ZIP ^> Extract All... ^> open the extracted folder ^> double-click Install.bat
    echo.
    pause
    exit /b 1
)
if /i "%~1"=="-Quiet" goto console
if /i "%~1"=="-Console" goto console
start "" wscript.exe "%~dp0app\setup.vbs" %*
exit /b 0

:console
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0app\install.ps1" %*
echo.
pause
