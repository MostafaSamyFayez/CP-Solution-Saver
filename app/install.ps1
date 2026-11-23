<#
.SYNOPSIS
    Installs CP Solution Saver for the current user (no admin rights needed).

.DESCRIPTION
    - Copies the app to %LOCALAPPDATA%\Programs\CPSolutionSaver
    - Adds Start Menu + Desktop shortcuts (hotkey Ctrl+Alt+Shift+S)
    - Creates/updates your settings in %APPDATA%\CPSolutionSaver\config.json
    - Starts the app in the tray; on first run it shows a short welcome tour, then Settings

.EXAMPLE
    Install.bat   (in the folder above this one)
    .\install.ps1 -MainCpp "C:\...\main.cpp" -RepoPath "C:\Users\me\Desktop\Problem-Solving-Solutions"
    .\install.ps1 -PracticeFile "C:\...\main.cpp", "C:\...\main.py"      # one practice file per language"
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'),
    [string]$MainCpp,
    [string[]]$PracticeFile,
    [string]$RepoPath,
    [switch]$NoDesktopShortcut,
    [switch]$NoPracticeLauncher,   # kept for older scripts; no .bat files are created any more
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
    # 1. ask the tray app to exit
    $asked = $false
    try {
        $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\CPSolutionSaver_cmd_exit'); [void]$ev.Set(); $ev.Dispose(); $asked = $true
        for ($i = 0; $i -lt 60; $i++) {
            try { $m = [System.Threading.Mutex]::OpenExisting('Local\CPSolutionSaver_Host'); $m.Dispose(); Start-Sleep -Milliseconds 100 } catch { break }
        }
    } catch { }
    # 2. make sure no copy of it (including test copies) still has the files open
    $left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*CPSaver.ps1*-Tray*' })
    foreach ($p in $left) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $asked = $true } catch { } }
    if ($asked) { Start-Sleep -Milliseconds 500 }
    return $asked
}
function Remove-OrRename([string]$Path) {
    # a DLL/EXE that is still loaded cannot be deleted, but it can be renamed out of the way
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch { Rename-Item -LiteralPath $Path -NewName ((Split-Path $Path -Leaf) + '.old-' + [DateTime]::Now.Ticks) -ErrorAction SilentlyContinue }
}
if (Stop-CPHost) { Ok 'Stopped the running CP Solution Saver (tray) to update it.' }

Step "Copying the app to $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $InstallDir -Recurse -Force
foreach ($extra in @('uninstall.ps1', 'README.md', 'LICENSE', 'CHANGELOG.md')) {
    # next to this script (app\) or one level up (README.md and LICENSE sit next to Install.bat)
    foreach ($d in @($PSScriptRoot, (Split-Path $PSScriptRoot -Parent))) {
        $p = Join-Path $d $extra
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $InstallDir -Force; break }
    }
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
# uninstall.bat asks in a window (no console); "uninstall.bat -Yes [-RemoveSettings]" runs without questions
$un = "@echo off`r`nif /i `"%~1`"==`"-Yes`" (`r`n    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0uninstall.ps1`" %*`r`n) else (`r`n    start `"`" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"%~dp0uninstall.ps1`" %*`r`n)`r`n"
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
        Get-ChildItem -LiteralPath $InstallDir -Filter '*.old-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        foreach ($old in @($dll, $launcherExe)) { Remove-OrRename $old }
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'native\CPSaverNative.cs'))) -ReferencedAssemblies System.Windows.Forms -OutputAssembly $dll -OutputType Library
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'native\CPSaverLauncher.cs'))) -OutputAssembly $launcherExe -OutputType WindowsApplication
        $nativeOk = (Test-Path $dll) -and (Test-Path $launcherExe)
        if ($nativeOk) { Ok 'Built CPSaverLauncher.exe and CPSaver.Native.dll (tray app, instant shortcuts).' }
    } catch {
        Warn "Could not build the fast launcher ($($_.Exception.Message)). Falling back to the slower launcher."
    }
} else {
    Warn 'Run Install.bat (Windows PowerShell 5.1) to build the fast launcher; using the slower launcher.'
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
if ($nativeOk) {
    New-Shortcut (Join-Path $menu 'CP Solution Saver - Code templates.lnk') 'templates' 'Choose and load code templates' ''
    New-Shortcut (Join-Path $menu 'CP Solution Saver - How to use.lnk') 'welcome' 'A short tour of CP Solution Saver and its shortcuts' ''
}
$u = $shell.CreateShortcut((Join-Path $menu 'Uninstall CP Solution Saver.lnk'))
$u.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$u.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$(Join-Path $InstallDir 'uninstall.ps1')`""
$u.WorkingDirectory = $env:TEMP; $u.IconLocation = $icon; $u.WindowStyle = 7; $u.Description = 'Uninstall CP Solution Saver (asks first)'; $u.Save()
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
if ($problems.Count -and $nativeOk) {
    # the tray app shows the welcome tour and then Settings on its first start (step 6)
    Ok 'Not set up yet: the welcome window will guide you through it in a moment.'
    $problems = @()
} elseif ($problems.Count -and -not $Quiet) {
    Warn 'Some settings are missing - opening the Settings window...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $InstallDir 'CPSaver.ps1') -Settings
    $cfg = Get-CPConfig $cfgPath
    $problems = @(Test-CPConfig $cfg)
}
if ($problems.Count) { $problems | ForEach-Object { Warn $_ }; Warn 'Open "CP Solution Saver - Settings" from the Start Menu to fix this.' }
else { foreach ($p in @($cfg.PracticeFiles)) { Ok "Practice file : $p" }; Ok "Solutions repo: $($cfg.RepoPath)" }

# 5. older versions put .bat launchers next to the practice project: remove them -------
#    (the shortcuts and the tray icon do the same job)
$gone = @(Remove-CPPracticeLaunchers -Config $cfg)
if ($gone.Count) { Step 'Cleaning up'; Ok "Removed the old .bat launchers next to your project: $(($gone | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')" }

# 6. start the tray app so the shortcuts work right away ------------------------
if ($nativeOk -and -not $Quiet) {
    Start-Process -FilePath $launcherExe -ArgumentList 'tray'
    Ok 'CP Solution Saver is running in the tray (bottom-right, next to the clock).'
} elseif ($nativeOk) {
    Start-Process -FilePath $launcherExe -ArgumentList 'tray'
}

Write-Host "`nInstalled CP Solution Saver $(Get-CPAppVersion)." -ForegroundColor Green
Write-Host 'Shortcuts:  Ctrl+Alt+Shift+S save window   |   Ctrl+Alt+Shift+F quick save   |   Ctrl+Alt+Shift+B solved problems' -ForegroundColor Green
Write-Host 'Everything else: right-click the CP Solution Saver icon in the tray (next to the clock).' -ForegroundColor Green
Write-Host 'The app is installed - you can delete the downloaded folder now (keep it only if you want to run the tests).' -ForegroundColor DarkGray
