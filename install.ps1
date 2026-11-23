<#
.SYNOPSIS
    Installs CP Solution Saver for the current user (no admin rights needed).

.DESCRIPTION
    - Copies the app to %LOCALAPPDATA%\Programs\CPSolutionSaver
    - Adds Start Menu + Desktop shortcuts (hotkey Ctrl+Alt+Shift+S)
    - Creates/updates your settings in %APPDATA%\CPSolutionSaver\config.json
    - Optionally puts a "save_solution.bat" launcher next to your practice project

.EXAMPLE
    .\install.bat
    .\install.ps1 -MainCpp "C:\...\main.cpp" -RepoPath "C:\Users\me\Desktop\Problem-Solving-Solutions"
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'),
    [string]$MainCpp,
    [string]$RepoPath,
    [switch]$NoDesktopShortcut,
    [switch]$NoPracticeLauncher,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
function Step($m) { Write-Host "  > $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

Write-Host "`nCP Solution Saver - installer`n" -ForegroundColor White

# 1. requirements -------------------------------------------------------------
Step 'Checking requirements'
if ($env:OS -ne 'Windows_NT') { throw 'This installer is for Windows.' }
Ok "PowerShell $($PSVersionTable.PSVersion)"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Ok "Git: $((& git --version) -join ' ')" }
else {
    Warn 'Git is not installed. Install it from https://git-scm.com/download/win (or: winget install Git.Git),'
    Warn 'then run this installer again. Continuing anyway...'
}

# 2. copy files ---------------------------------------------------------------
Step "Copying the app to $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $InstallDir -Recurse -Force
foreach ($extra in @('uninstall.ps1', 'README.md', 'LICENSE', 'CHANGELOG.md')) {
    $p = Join-Path $PSScriptRoot $extra
    if (Test-Path $p) { Copy-Item $p -Destination $InstallDir -Force }
}
if (Test-Path (Join-Path $PSScriptRoot 'tests')) { Copy-Item (Join-Path $PSScriptRoot 'tests') -Destination $InstallDir -Recurse -Force }

# hidden launcher (no console window flash) + console launcher
$vbs = @'
' Starts CP Solution Saver without a console window. Arguments are passed through.
Set sh = CreateObject("WScript.Shell")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
args = ""
For Each a In WScript.Arguments
    args = args & " """ & a & """"
Next
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\CPSaver.ps1""" & args, 0, False
'@
[IO.File]::WriteAllText((Join-Path $InstallDir 'CPSaver.vbs'), ($vbs -replace "\r?\n", "`r`n"), [Text.Encoding]::ASCII)
$cmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0CPSaver.ps1`" %*`r`n"
[IO.File]::WriteAllText((Join-Path $InstallDir 'cpsaver.cmd'), $cmd, [Text.Encoding]::ASCII)
$un = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0uninstall.ps1`" %*`r`npause`r`n"
[IO.File]::WriteAllText((Join-Path $InstallDir 'uninstall.bat'), $un, [Text.Encoding]::ASCII)
Get-ChildItem $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Ok 'Files copied.'

# 3. shortcuts ----------------------------------------------------------------
Step 'Creating shortcuts'
$shell = New-Object -ComObject WScript.Shell
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$icon = "$env:SystemRoot\System32\shell32.dll,43"
function New-Shortcut([string]$Path, [string]$Arguments, [string]$Description, [string]$Hotkey) {
    $s = $shell.CreateShortcut($Path)
    $s.TargetPath = $wscript
    $s.Arguments = $Arguments
    $s.WorkingDirectory = $InstallDir
    $s.IconLocation = $icon
    $s.Description = $Description
    if ($Hotkey) { $s.Hotkey = $Hotkey }
    $s.Save()
}
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CP Solution Saver'
New-Item -ItemType Directory -Path $menu -Force | Out-Null
$vbsQ = "`"$(Join-Path $InstallDir 'CPSaver.vbs')`""
New-Shortcut (Join-Path $menu 'CP Solution Saver.lnk') $vbsQ 'Save an accepted solution to GitHub (Ctrl+Alt+Shift+S)' 'CTRL+ALT+SHIFT+S'
New-Shortcut (Join-Path $menu 'CP Solution Saver - Settings.lnk') "$vbsQ -Settings" 'Change CP Solution Saver settings' ''
$u = $shell.CreateShortcut((Join-Path $menu 'Uninstall CP Solution Saver.lnk'))
$u.TargetPath = Join-Path $InstallDir 'uninstall.bat'; $u.WorkingDirectory = $env:TEMP; $u.Save()
$r = $shell.CreateShortcut((Join-Path $menu 'Read me.lnk'))
$r.TargetPath = Join-Path $InstallDir 'README.md'; $r.Save()
Ok "Start Menu: $menu   (hotkey Ctrl+Alt+Shift+S opens the app from anywhere)"
if (-not $NoDesktopShortcut) {
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'CP Solution Saver.lnk') $vbsQ 'Save an accepted solution to GitHub' ''
    Ok 'Desktop shortcut created.'
}

# 4. settings -----------------------------------------------------------------
Step 'Settings'
Import-Module (Join-Path $InstallDir 'CPSaver.Core.psm1') -Force -DisableNameChecking
$cfgPath = Get-CPDefaultConfigPath
$cfg = Get-CPConfig $cfgPath
if ($MainCpp)  { $cfg.MainCppPath = (Resolve-Path -LiteralPath $MainCpp).ProviderPath }
if ($RepoPath) { $cfg.RepoPath = (Resolve-Path -LiteralPath $RepoPath).ProviderPath }

# migrate from the v1 script's config if present next to the practice project
if (-not $cfg.RepoPath -and $cfg.MainCppPath) {
    $old = Join-Path (Split-Path (Split-Path $cfg.MainCppPath -Parent) -Parent) 'save_solution.config.json'
    if (Test-Path $old) { try { $cfg.RepoPath = (Get-Content $old -Raw | ConvertFrom-Json).RepoPath; Ok "Imported repo path from $old" } catch { } }
}
Initialize-CPTemplate $cfg.TemplatePath
Save-CPConfig -Config $cfg -Path $cfgPath
Ok "Settings file: $cfgPath"
Ok "Template file: $($cfg.TemplatePath)"

$problems = @(Test-CPConfig $cfg)
if ($problems.Count -and -not $Quiet) {
    Warn 'Some settings are missing - opening the Settings window...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $InstallDir 'CPSaver.ps1') -Settings
    $cfg = Get-CPConfig $cfgPath
    $problems = @(Test-CPConfig $cfg)
}
if ($problems.Count) { $problems | ForEach-Object { Warn $_ }; Warn 'Open "CP Solution Saver - Settings" from the Start Menu to fix this.' }
else { Ok "Practice file : $($cfg.MainCppPath)"; Ok "Solutions repo: $($cfg.RepoPath)" }

# 5. launcher next to the practice project ------------------------------------
if (-not $NoPracticeLauncher -and $cfg.MainCppPath -and (Test-Path -LiteralPath $cfg.MainCppPath)) {
    Step 'Adding save_solution.bat next to your practice project'
    $dir = Split-Path $cfg.MainCppPath -Parent
    for ($i = 0; $i -lt 2; $i++) {
        if (Get-ChildItem -LiteralPath $dir -Filter *.sln -ErrorAction SilentlyContinue) { break }
        $parent = Split-Path $dir -Parent; if (-not $parent) { break }; $dir = $parent
    }
    if (-not (Get-ChildItem -LiteralPath $dir -Filter *.sln -ErrorAction SilentlyContinue)) { $dir = Split-Path $cfg.MainCppPath -Parent }
    $launcher = "@echo off`r`nREM Opens CP Solution Saver (installed in $InstallDir)`r`nstart `"`" wscript.exe `"$(Join-Path $InstallDir 'CPSaver.vbs')`" %*`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'save_solution.bat'), $launcher, [Text.Encoding]::ASCII)
    Ok "$(Join-Path $dir 'save_solution.bat')"
}

Write-Host "`nInstalled CP Solution Saver $(Get-CPAppVersion)." -ForegroundColor Green
Write-Host 'Open it with:  Ctrl+Alt+Shift+S,  the Desktop / Start Menu shortcut,  or save_solution.bat next to your project.' -ForegroundColor Green
