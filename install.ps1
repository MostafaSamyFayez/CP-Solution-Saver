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
    .\install.ps1 -PracticeFile "C:\...\main.cpp", "C:\...\main.py"      # one practice file per language"
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'),
    [string]$MainCpp,
    [string[]]$PracticeFile,
    [string]$RepoPath,
    [switch]$NoDesktopShortcut,
    [switch]$NoPracticeLauncher,
    [switch]$NoStartup,
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

# 2. stop a running copy (its files are in use), then copy ----------------------
function Stop-CPHost {
    try { $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\CPSolutionSaver_cmd_exit') } catch { return $false }
    [void]$ev.Set(); $ev.Dispose()
    for ($i = 0; $i -lt 60; $i++) {
        try { $m = [System.Threading.Mutex]::OpenExisting('Local\CPSolutionSaver_Host'); $m.Dispose(); Start-Sleep -Milliseconds 100 } catch { break }
    }
    Start-Sleep -Milliseconds 300
    return $true
}
if (Stop-CPHost) { Ok 'Stopped the running CP Solution Saver (tray) to update it.' }

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

# 2b. compile the small native helpers (hotkeys + instant launcher) with the C#
#     compiler that ships with Windows (.NET Framework). Without them the app
#     still works, just slower to open.
$nativeOk = $false
$launcherExe = Join-Path $InstallDir 'CPSaverLauncher.exe'
if ($PSVersionTable.PSVersion.Major -le 5) {
    Step 'Building the fast launcher'
    try {
        $dll = Join-Path $InstallDir 'CPSaver.Native.dll'
        foreach ($old in @($dll, $launcherExe)) { if (Test-Path $old) { Remove-Item $old -Force } }
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'native\CPSaverNative.cs'))) -ReferencedAssemblies System.Windows.Forms -OutputAssembly $dll -OutputType Library
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'native\CPSaverLauncher.cs'))) -OutputAssembly $launcherExe -OutputType WindowsApplication
        $nativeOk = (Test-Path $dll) -and (Test-Path $launcherExe)
        if ($nativeOk) { Ok 'Built CPSaverLauncher.exe and CPSaver.Native.dll (tray app, instant shortcuts).' }
    } catch {
        Warn "Could not build the fast launcher ($($_.Exception.Message)). Falling back to the slower launcher."
    }
} else {
    Warn 'Run install.bat (Windows PowerShell 5.1) to build the fast launcher; using the slower launcher.'
}

# 3. shortcuts ----------------------------------------------------------------
Step 'Creating shortcuts'
$shell = New-Object -ComObject WScript.Shell
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$icon = Join-Path $InstallDir 'app.ico'
if (-not (Test-Path $icon)) { $icon = "$env:SystemRoot\System32\shell32.dll,43" }
$vbsQ = "`"$(Join-Path $InstallDir 'CPSaver.vbs')`""
# command -> arguments for the target (fast launcher, or the vbs fallback)
function Get-LaunchArgs([string]$Cmd) {
    if ($nativeOk) { return $Cmd }
    switch ($Cmd) { 'open' { return $vbsQ } 'quick' { return "$vbsQ -Quick" } 'browse' { return "$vbsQ -Browse" } 'settings' { return "$vbsQ -Settings" } 'templates' { return $vbsQ } default { return $vbsQ } }
}
function New-Shortcut([string]$Path, [string]$Cmd, [string]$Description, [string]$Hotkey) {
    $s = $shell.CreateShortcut($Path)
    $s.TargetPath = $(if ($nativeOk) { $launcherExe } else { $wscript })
    $s.Arguments = Get-LaunchArgs $Cmd
    $s.WorkingDirectory = $InstallDir
    $s.IconLocation = $icon
    $s.Description = $Description
    # with the tray app the hotkeys are registered by the app itself; shortcut hotkeys only as a fallback
    $s.Hotkey = $(if ($Hotkey -and -not $nativeOk) { $Hotkey } else { '' })
    $s.Save()
}
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CP Solution Saver'
New-Item -ItemType Directory -Path $menu -Force | Out-Null
New-Shortcut (Join-Path $menu 'CP Solution Saver.lnk') 'open' 'Save an accepted solution to GitHub (Ctrl+Alt+Shift+S)' 'CTRL+ALT+SHIFT+S'
New-Shortcut (Join-Path $menu 'CP Solution Saver - Settings.lnk') 'settings' 'Change CP Solution Saver settings' ''
New-Shortcut (Join-Path $menu 'CP Solution Saver - Quick Save.lnk') 'quick' 'Save and push your practice file with no window (Ctrl+Alt+Shift+F)' 'CTRL+ALT+SHIFT+F'
New-Shortcut (Join-Path $menu 'CP Solution Saver - Solved problems.lnk') 'browse' 'Search solved problems and load one back (Ctrl+Alt+Shift+B)' ''
if ($nativeOk) { New-Shortcut (Join-Path $menu 'CP Solution Saver - Code templates.lnk') 'templates' 'Choose and load code templates' '' }
$u = $shell.CreateShortcut((Join-Path $menu 'Uninstall CP Solution Saver.lnk'))
$u.TargetPath = Join-Path $InstallDir 'uninstall.bat'; $u.WorkingDirectory = $env:TEMP; $u.Save()
$r = $shell.CreateShortcut((Join-Path $menu 'Read me.lnk'))
$r.TargetPath = Join-Path $InstallDir 'README.md'; $r.Save()
Ok "Start Menu: $menu"
Ok 'Hotkeys: Ctrl+Alt+Shift+S = save window,  Ctrl+Alt+Shift+F = quick save,  Ctrl+Alt+Shift+B = solved problems'
if (-not $NoDesktopShortcut) {
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'CP Solution Saver.lnk') 'open' 'Save an accepted solution to GitHub' ''
    Ok 'Desktop shortcut created.'
}
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'CP Solution Saver.lnk'
if ($nativeOk -and -not $NoStartup) {
    $s = $shell.CreateShortcut($startupLnk)
    $s.TargetPath = $launcherExe; $s.Arguments = 'tray'; $s.WorkingDirectory = $InstallDir; $s.IconLocation = $icon
    $s.Description = 'CP Solution Saver (tray)'; $s.Save()
    Ok 'Starts with Windows (quietly in the tray). Turn it off in Settings.'
}

# 4. settings -----------------------------------------------------------------
Step 'Settings'
Import-Module (Join-Path $InstallDir 'CPSaver.Core.psm1') -Force -DisableNameChecking
$cfgPath = Get-CPDefaultConfigPath
$cfg = Get-CPConfig $cfgPath
# practice files: one per language; a new file replaces the old one of the same language
$add = @(@($PracticeFile) + @($MainCpp) | Where-Object { $_ } | ForEach-Object { (Resolve-Path -LiteralPath $_).ProviderPath })
foreach ($p in $add) {
    $lang = (Get-CPLanguage $p).Name
    $cfg.PracticeFiles = @(@($cfg.PracticeFiles) | Where-Object { $_ -and ((Get-CPLanguage $_).Name -ne $lang) }) + @($p)
}
if ($add.Count) { $cfg.MainCppPath = $add[-1] }
if ($RepoPath) { $cfg.RepoPath = (Resolve-Path -LiteralPath $RepoPath).ProviderPath }

# migrate from the v1 script's config if present next to the practice project
if (-not $cfg.RepoPath -and $cfg.MainCppPath) {
    $old = Join-Path (Split-Path (Split-Path $cfg.MainCppPath -Parent) -Parent) 'save_solution.config.json'
    if (Test-Path $old) { try { $cfg.RepoPath = (Get-Content $old -Raw | ConvertFrom-Json).RepoPath; Ok "Imported repo path from $old" } catch { } }
}
$tplDir = Initialize-CPTemplates
Save-CPConfig -Config $cfg -Path $cfgPath
Ok "Settings file: $cfgPath"
Ok "Templates    : $tplDir ($(@(Get-CPTemplates).Count) templates)"

$problems = @(Test-CPConfig $cfg)
if ($problems.Count -and -not $Quiet) {
    Warn 'Some settings are missing - opening the Settings window...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $InstallDir 'CPSaver.ps1') -Settings
    $cfg = Get-CPConfig $cfgPath
    $problems = @(Test-CPConfig $cfg)
}
if ($problems.Count) { $problems | ForEach-Object { Warn $_ }; Warn 'Open "CP Solution Saver - Settings" from the Start Menu to fix this.' }
else { foreach ($p in @($cfg.PracticeFiles)) { Ok "Practice file : $p" }; Ok "Solutions repo: $($cfg.RepoPath)" }

# 5. launcher next to the practice project ------------------------------------
if (-not $NoPracticeLauncher -and $cfg.MainCppPath -and (Test-Path -LiteralPath $cfg.MainCppPath)) {
    Step 'Adding save_solution.bat next to your practice project'
    $dir = Split-Path $cfg.MainCppPath -Parent
    for ($i = 0; $i -lt 2; $i++) {
        if (Get-ChildItem -LiteralPath $dir -Filter *.sln -ErrorAction SilentlyContinue) { break }
        $parent = Split-Path $dir -Parent; if (-not $parent) { break }; $dir = $parent
    }
    if (-not (Get-ChildItem -LiteralPath $dir -Filter *.sln -ErrorAction SilentlyContinue)) { $dir = Split-Path $cfg.MainCppPath -Parent }
    $vbsPath = Join-Path $InstallDir 'CPSaver.vbs'
    $mk = { param($cmd, $vbsArgs) if ($nativeOk) { "start `"`" `"$launcherExe`" $cmd" } else { "start `"`" wscript.exe `"$vbsPath`" $vbsArgs" } }
    $launcher = "@echo off`r`nREM Opens CP Solution Saver (installed in $InstallDir)`r`n$(& $mk 'open' '')`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'save_solution.bat'), $launcher, [Text.Encoding]::ASCII)
    $quick = "@echo off`r`nREM Quick save: saves and pushes your practice file with no window, then shows the result`r`n$(& $mk 'quick' '-Quick')`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'quick_save.bat'), $quick, [Text.Encoding]::ASCII)
    $browse = "@echo off`r`nREM Search your solved problems and load one back`r`n$(& $mk 'browse' '-Browse')`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'solved_problems.bat'), $browse, [Text.Encoding]::ASCII)
    Ok "$(Join-Path $dir 'save_solution.bat')  (+ quick_save.bat, solved_problems.bat)"
}

# 6. start the tray app so the shortcuts work right away ------------------------
if ($nativeOk -and -not $Quiet) {
    Start-Process -FilePath $launcherExe -ArgumentList 'tray'
    Ok 'CP Solution Saver is running in the tray (bottom-right, next to the clock).'
} elseif ($nativeOk) {
    Start-Process -FilePath $launcherExe -ArgumentList 'tray'
}

Write-Host "`nInstalled CP Solution Saver $(Get-CPAppVersion)." -ForegroundColor Green
Write-Host 'Open it with:  Ctrl+Alt+Shift+S,  the Desktop / Start Menu shortcut,  or save_solution.bat next to your project.' -ForegroundColor Green
Write-Host 'Quick save (no window): Ctrl+Alt+Shift+F or quick_save.bat.   Browse solved problems: solved_problems.bat or the button in the app.' -ForegroundColor Green
