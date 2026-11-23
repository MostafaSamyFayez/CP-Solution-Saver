<#
.SYNOPSIS
    Installs (or updates) CP Solution Saver for the current user. No admin rights needed.

.DESCRIPTION
    Install.bat runs this with -Gui: a small window (options -> progress -> done) and then the app
    opens with the welcome tour. Steps:
      1. check Windows / PowerShell / Git
      2. stop a running copy, copy app\src to %LOCALAPPDATA%\Programs\CPSolutionSaver
      3. build CPSaverLauncher.exe + CPSaver.Native.dll with the C# compiler that ships with Windows
      4. shortcuts: Start Menu, Desktop (optional), Startup (optional, tray app)
      5. settings in %APPDATA%\CPSolutionSaver (kept across installs); templates; the welcome tour is
         reset so it shows again after every interactive install
      6. remove .bat launchers made by older versions; start the app
    A log of the last install is written to %TEMP%\CPSolutionSaver-install.log.

.EXAMPLE
    Install.bat                      # the window (normal use)
    Install.bat -Console             # same, in the console
    Install.bat -Quiet               # console, no questions, no tour, app restarted in the tray (updates/scripts)
    .\install.ps1 -MainCpp "C:\...\main.cpp" -RepoPath "C:\Users\me\Desktop\Problem-Solving-Solutions"
    .\install.ps1 -PracticeFile "C:\...\main.cpp", "C:\...\main.py"      # one practice file per language
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'),
    [string]$MainCpp,
    [string[]]$PracticeFile,
    [string]$RepoPath,
    [switch]$NoDesktopShortcut,
    [switch]$NoPracticeLauncher,   # kept for older scripts; no .bat files are created any more
    [switch]$NoStartup,
    [switch]$Quiet,                # no questions, no tour, keep the app in the tray (used for updates and tests)
    [switch]$Gui,                  # the installer window (Install.bat)
    [switch]$Console               # accepted for Install.bat -Console (console output, same as no -Gui)
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
$script:InstallLog = Join-Path ([IO.Path]::GetTempPath()) 'CPSolutionSaver-install.log'
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:Ui = $null      # the progress window's controls while installing with -Gui
try { Set-Content -LiteralPath $script:InstallLog -Value "CP Solution Saver install - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding ASCII } catch { }

function Write-InstallLog([string]$m) { try { Add-Content -LiteralPath $script:InstallLog -Value $m -Encoding ASCII } catch { } }
function Update-InstallUi {
    if ($script:Ui) { [System.Windows.Forms.Application]::DoEvents() }
}
function Step($m) {
    Write-InstallLog "> $m"
    if ($script:Ui) { $script:Ui.Step.Text = "$m..."; $script:Ui.Bar.Value = [Math]::Min($script:Ui.Bar.Maximum, $script:Ui.Bar.Value + 1); Update-InstallUi }
    else { Write-Host "  > $m" -ForegroundColor Cyan }
}
function Ok($m) {
    Write-InstallLog "    $m"
    if ($script:Ui) { $script:Ui.Detail.Text = $m; Update-InstallUi } else { Write-Host "    $m" -ForegroundColor Green }
}
function Warn($m) {
    Write-InstallLog "    WARNING: $m"; $script:Warnings.Add($m)
    if ($script:Ui) { Update-InstallUi } else { Write-Host "    $m" -ForegroundColor Yellow }
}

# ---------------------------------------------------------------- installer window (-Gui)
if ($Gui) {
    Import-Module (Join-Path $src 'CPSaver.Core.psm1') -Force -DisableNameChecking
    try {
        Add-Type -Namespace CPInstall -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop
        [void][CPInstall.Dpi]::SetProcessDPIAware()
    } catch { }
    . (Join-Path $src 'CPSaver.Gui.ps1')     # theme + helpers (New-CPForm, New-CPHeader, New-CPButton ...)
}

function New-InstallText([string]$Text, $Color = $null, $Font = $null) {
    $l = New-CPLabel $Text $(if ($Font) { $Font } else { $script:CPFont })
    $l.MaximumSize = New-Object System.Drawing.Size(500, 0); $l.UseMnemonic = $false
    if ($Color) { $l.ForeColor = $Color }
    return $l
}

function Show-InstallWelcome {
    <# First page: what will happen + options. Returns @{ Desktop; Startup } or $null (cancelled). #>
    $update = Test-Path -LiteralPath (Join-Path $InstallDir 'CPSaver.ps1')
    $f = New-CPForm 'CP Solution Saver Setup' 600 440
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.BackColor = [System.Drawing.Color]::White
    $f.AutoSize = $true; $f.AutoSizeMode = 'GrowOnly'
    $hdr = New-CPHeader $(if ($update) { 'Update CP Solution Saver' } else { 'Install CP Solution Saver' }) "Version $(Get-CPAppVersion)"
    $hdr.Right.Visible = $false
    $g = New-Object System.Windows.Forms.TableLayoutPanel; $g.Dock = 'Fill'; $g.ColumnCount = 1; $g.AutoSize = $true
    $g.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 10)
    $g.Controls.Add((New-InstallText 'Save your accepted competitive-programming solutions with one shortcut - organized by platform, topic and difficulty, and uploaded to GitHub if you like.'))
    $where = if ($update) { "Updates the installed app. Your settings, templates and solutions are kept.`r`nFolder: $InstallDir" } else { "Installs for your Windows user only (no admin rights needed) into:`r`n$InstallDir" }
    $g.Controls.Add((New-InstallText $where $script:CPMuted))
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $gl = New-InstallText "Git found: $((& git --version) -join ' ')" $script:CPGreen }
    else {
        $gl = New-Object System.Windows.Forms.LinkLabel; $gl.AutoSize = $true; $gl.MaximumSize = New-Object System.Drawing.Size(500, 0); $gl.Font = $script:CPFont
        $gl.Text = 'Git is not installed. The app needs it to save your solutions: install Git for Windows (default options), then run this setup again.'
        $gl.ForeColor = $script:CPOrange; $gl.LinkArea = New-Object System.Windows.Forms.LinkArea(76, 15)
        $gl.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
        $gl.Add_LinkClicked({ Start-Process 'https://git-scm.com/download/win' })
    }
    $g.Controls.Add($gl)
    $desk = New-Object System.Windows.Forms.CheckBox; $desk.Text = 'Create a Desktop shortcut'; $desk.AutoSize = $true; $desk.Checked = -not $NoDesktopShortcut
    $desk.Margin = New-Object System.Windows.Forms.Padding(3, 12, 3, 2)
    $start = New-Object System.Windows.Forms.CheckBox; $start.Text = 'Start with Windows (recommended: keeps the shortcuts instant, runs quietly in the tray)'; $start.AutoSize = $true
    $start.Checked = -not $NoStartup; $start.MaximumSize = New-Object System.Drawing.Size(520, 0)
    $g.Controls.Add($desk); $g.Controls.Add($start)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $btns.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
    $go = New-CPButton $(if ($update) { 'Update' } else { 'Install' }) 110; Set-CPPrimary $go; $go.DialogResult = 'OK'
    $no = New-CPButton 'Cancel' 90; $no.DialogResult = 'Cancel'
    $btns.Controls.Add($no); $btns.Controls.Add($go)
    $g.Controls.Add($btns)
    $f.Controls.Add($g); $f.Controls.Add($hdr.Panel)
    $f.AcceptButton = $go; $f.CancelButton = $no
    $f.Add_Shown({ Show-CPForeground $f; $go.Focus() })
    $r = $f.ShowDialog(); $res = @{ Desktop = $desk.Checked; Startup = $start.Checked }; $f.Dispose()
    if ($r -ne 'OK') { return $null }
    return $res
}

function Show-InstallProgress {
    <# The progress window (not modal; the install steps update it). #>
    $f = New-CPForm 'CP Solution Saver Setup' 560 230
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $true; $f.BackColor = [System.Drawing.Color]::White
    $hdr = New-CPHeader 'Installing CP Solution Saver' "Version $(Get-CPAppVersion)"; $hdr.Right.Visible = $false
    $p = New-Object System.Windows.Forms.Panel; $p.Dock = 'Fill'; $p.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 10)
    $step = New-Object System.Windows.Forms.Label; $step.Font = $script:CPFontBold; $step.AutoSize = $false; $step.Dock = 'Top'; $step.Height = 26; $step.Text = 'Starting...'
    $bar = New-Object System.Windows.Forms.ProgressBar; $bar.Dock = 'Top'; $bar.Height = 16; $bar.Maximum = 6; $bar.Value = 0
    $gap = New-Object System.Windows.Forms.Panel; $gap.Dock = 'Top'; $gap.Height = 8
    $det = New-Object System.Windows.Forms.Label; $det.ForeColor = $script:CPMuted; $det.AutoSize = $false; $det.Dock = 'Top'; $det.Height = 40; $det.AutoEllipsis = $true; $det.UseMnemonic = $false
    $p.Controls.Add($det); $p.Controls.Add($gap); $p.Controls.Add($bar); $p.Controls.Add($step)
    $f.Controls.Add($p); $f.Controls.Add($hdr.Panel)
    $state = @{ Done = $false }
    $f.Add_FormClosing({ param($s, $e) if (-not $state.Done) { $e.Cancel = $true } })
    $f.Show(); Show-CPForeground $f; [System.Windows.Forms.Application]::DoEvents()
    return @{ Form = $f; Step = $step; Bar = $bar; Detail = $det; State = $state }
}

function Show-InstallDone {
    <# Last page. -Failed shows the error. #>
    param([string]$Message, [switch]$Failed)
    $f = New-CPForm 'CP Solution Saver Setup' 600 380
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.BackColor = [System.Drawing.Color]::White
    $f.AutoSize = $true; $f.AutoSizeMode = 'GrowOnly'
    $hdr = New-CPHeader $(if ($Failed) { 'Setup could not finish' } else { 'CP Solution Saver is installed' }) "Version $(Get-CPAppVersion)"; $hdr.Right.Visible = $false
    $g = New-Object System.Windows.Forms.TableLayoutPanel; $g.Dock = 'Fill'; $g.ColumnCount = 1; $g.AutoSize = $true
    $g.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 10)
    if ($Failed) {
        $g.Controls.Add((New-InstallText $Message $script:CPRed))
        $g.Controls.Add((New-InstallText "Details are in the install log:`r`n$($script:InstallLog)" $script:CPMuted))
    } else {
        $g.Controls.Add((New-InstallText 'Click Finish to open it. A short tour shows you how to use it, then you choose your practice file and solutions folder (only the first time).' $script:CPAccent))
        $g.Controls.Add((New-InstallText "Shortcuts:   Ctrl+Alt+Shift+S  save    |    Ctrl+Alt+Shift+F  quick save    |    Ctrl+Alt+Shift+B  solved problems" $script:CPAccent $script:CPFontBold))
        $g.Controls.Add((New-InstallText 'It lives in the tray, next to the clock (right-click the icon for everything). You can delete the downloaded folder now.' $script:CPMuted))
        foreach ($w in $script:Warnings) { $g.Controls.Add((New-InstallText $w $script:CPOrange)) }
    }
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $btns.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
    $ok = New-CPButton $(if ($Failed) { 'Close' } else { 'Finish' }) 110; Set-CPPrimary $ok; $ok.DialogResult = 'OK'
    $btns.Controls.Add($ok)
    if ($Failed) { $lg = New-CPButton 'Open the log'; $lg.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$($script:InstallLog)`"" }); $btns.Controls.Add($lg) }
    $g.Controls.Add($btns)
    $f.Controls.Add($g); $f.Controls.Add($hdr.Panel)
    $f.AcceptButton = $ok; $f.CancelButton = $ok
    $f.Add_Shown({ Show-CPForeground $f; $ok.Focus() })
    [void]$f.ShowDialog(); $f.Dispose()
}

if ($Gui) {
    $opts = Show-InstallWelcome
    if (-not $opts) { exit 0 }
    $NoDesktopShortcut = -not $opts.Desktop
    $NoStartup = -not $opts.Startup
    $script:Ui = Show-InstallProgress
} else {
    Write-Host "`nCP Solution Saver - installer`n" -ForegroundColor White
}

$installSteps = {
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
    elseif ($NoStartup -and (Test-Path -LiteralPath $startupLnk)) { Remove-Item -LiteralPath $startupLnk -Force; Ok 'Will not start with Windows.' }

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
    # every interactive install shows the welcome tour again (updates with -Quiet don't)
    if (-not $Quiet) { $cfg.TutorialShown = $false }
    Save-CPConfig -Config $cfg -Path $cfgPath
    Ok "Settings file: $cfgPath"
    Ok "Templates    : $tplDir ($(@(Get-CPTemplates).Count) templates)"

    $problems = @(Test-CPConfig $cfg)
    if ($problems.Count -and $nativeOk) {
        # the tray app shows the welcome tour and then Settings on its first start (step 6)
        Ok 'Not set up yet: the welcome window will guide you through it in a moment.'
        $problems = @()
    } elseif ($problems.Count -and -not $Quiet -and -not $Gui) {
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

    # 6. start the app ---------------------------------------------------------------
    #    -Quiet: back in the tray as before. Otherwise it opens (after the Done page in the window):
    #    the welcome tour, Settings if needed, then the save window.
    Step 'Starting CP Solution Saver'
    $script:StartApp = {
        if ($nativeOk) { Start-Process -FilePath $launcherExe -ArgumentList $(if ($Quiet) { 'tray' } else { 'open' }) }
        elseif (-not $Quiet) { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList "`"$(Join-Path $InstallDir 'CPSaver.vbs')`"" }
    }
    Ok 'Done.'
}

$failed = $null
try { . $installSteps }
catch { $failed = $_.Exception.Message; Write-InstallLog "FAILED: $failed`n$($_.ScriptStackTrace)" }

if ($Gui) {
    $script:Ui.State.Done = $true; $script:Ui.Form.Close(); $script:Ui.Form.Dispose(); $script:Ui = $null
    if ($failed) { Show-InstallDone -Failed -Message "Something went wrong: $failed"; exit 1 }
    Show-InstallDone
    & $script:StartApp
    exit 0
}

if ($failed) { Write-Host "`nInstall failed: $failed`nLog: $($script:InstallLog)" -ForegroundColor Red; exit 1 }
& $script:StartApp
Write-Host "`nInstalled CP Solution Saver $(Get-CPAppVersion)." -ForegroundColor Green
Write-Host 'Shortcuts:  Ctrl+Alt+Shift+S save window   |   Ctrl+Alt+Shift+F quick save   |   Ctrl+Alt+Shift+B solved problems' -ForegroundColor Green
Write-Host 'Everything else: right-click the CP Solution Saver icon in the tray (next to the clock).' -ForegroundColor Green
Write-Host 'The app is installed - you can delete the downloaded folder now (keep it only if you want to run the tests).' -ForegroundColor DarkGray
