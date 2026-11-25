# CPSaver.Tray.ps1 - the tray host: one small background process that keeps the
# app loaded, owns the system-wide hotkeys and opens windows instantly.
# Dot-sourced by CPSaver.ps1 (after CPSaver.Gui.ps1) when started with -Tray.
#
# Commands arrive from: hotkeys (Ctrl+Alt+Shift+S / F / B), the tray menu, and
# CPSaverLauncher.exe (shortcuts, .bat files) through named events.

function Write-CPTrace([string]$Message) {
    try {
        $f = Join-Path (Get-CPDataDir) 'host.log'
        if ((Test-Path $f) -and (Get-Item $f).Length -gt 200KB) { Remove-Item $f -Force }
        Add-Content -LiteralPath $f -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff') + '  ' + $Message)
    } catch { }
}

function Start-CPTray {
    param([string]$Command = 'tray', [Parameter(Mandatory)][string]$ConfigPath)

    Write-CPTrace "host starting (command: $Command)"
    $tray = @{ Busy = $false; Quick = $false; QuickBusy = $null; ConfigPath = $ConfigPath; Icon = $null
               Checking = $false; CheckManual = $false; Pending = $null; UpdateBusy = $null }

    $hostWin = New-Object CPSaverNative.HostWindow
    $mods = [CPSaverNative.HostWindow]::MOD_CONTROL -bor [CPSaverNative.HostWindow]::MOD_ALT -bor [CPSaverNative.HostWindow]::MOD_SHIFT
    $hk = [ordered]@{
        'Ctrl+Alt+Shift+S' = $hostWin.AddHotkey('open', $mods, [System.Windows.Forms.Keys]::S)
        'Ctrl+Alt+Shift+F' = $hostWin.AddHotkey('quick', $mods, [System.Windows.Forms.Keys]::F)
        'Ctrl+Alt+Shift+B' = $hostWin.AddHotkey('browse', $mods, [System.Windows.Forms.Keys]::B)
    }
    foreach ($c in @('open', 'quick', 'browse', 'templates', 'settings', 'welcome', 'update', 'report', 'exit')) { $hostWin.ListenFor($c) }
    $failed = @($hk.Keys | Where-Object { -not $hk[$_] })
    if ($failed.Count) { Write-CPTrace "hotkeys already used by another app: $($failed -join ', ')" }

    # ---------------------------------------------------------------- tray icon + menu
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = Get-CPAppIcon
    $icon.Text = 'CP Solution Saver'
    $tray.Icon = $icon
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Font = $script:CPFont
    $addItem = {
        param($text, $cmd, [bool]$bold = $false)
        $it = New-Object System.Windows.Forms.ToolStripMenuItem($text)
        if ($bold) { $it.Font = $script:CPFontBold }
        $it.Tag = $cmd
        $it.Add_Click({ param($s, $e) & $dispatch ([string]$s.Tag) })
        [void]$menu.Items.Add($it)
    }
    & $addItem 'Save solution...          Ctrl+Alt+Shift+S' 'open' $true
    & $addItem 'Quick save                  Ctrl+Alt+Shift+F' 'quick'
    & $addItem 'Solved problems...       Ctrl+Alt+Shift+B' 'browse'
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    & $addItem 'Analytics report' 'report'
    & $addItem 'Code templates...' 'templates'
    & $addItem 'Settings...' 'settings'
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    & $addItem 'Open repo folder' 'folder'
    & $addItem 'Open repo on GitHub' 'web'
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    & $addItem 'How to use...' 'welcome'
    & $addItem 'Check for updates...' 'update'
    & $addItem 'Exit' 'exit'
    $icon.ContextMenuStrip = $menu
    $icon.Add_MouseDoubleClick({ & $dispatch 'open' })
    $icon.Visible = $true

    # ---------------------------------------------------------------- commands
    $showQuickResult = {
        param($res, $err)
        $cfg = Get-CPConfig $tray.ConfigPath
        if ($err -or -not $res) {
            $a = Show-CPResultDialog -Title 'Quick save failed' -Lines @("$err") -Kind Error -OfferOpen
            if ($a -eq 'open') { & $dispatch 'open' }
            return
        }
        if (-not $res.Success) {
            $lines = @($res.Summary)
            if ($res.LogFile) { $lines += "Details: $($res.LogFile)" }
            $a = Show-CPResultDialog -Title $res.Title -Lines $lines -Kind Error -OfferOpen
            if ($a -eq 'open') { & $dispatch 'open' }
            return
        }
        $url = $null
        if ($res.RelPath) { try { $url = Get-CPFileWebUrl -RepoPath $cfg.RepoPath -RelPath $res.RelPath } catch { } }
        if ($cfg.QuickSaveNotify -eq 'notification') {
            $icon.BalloonTipTitle = $res.Title
            $icon.BalloonTipText = (($res.Summary | Where-Object { $_ }) -join "`n")
            $icon.BalloonTipIcon = 'Info'
            $icon.ShowBalloonTip(8000)
        } else {
            $kind = if ($res.Title -like 'Already saved*') { 'Info' } else { 'Success' }
            Show-CPResultDialog -Title $res.Title -Lines $res.Summary -Kind $kind -Url $url | Out-Null
        }
    }

    # ---------------------------------------------------------------- updates
    # $checkUpdates asks GitHub in the background; a newer release is offered with $offerUpdate
    # (only when no window is open; otherwise the update timer offers it a little later).
    $checkUpdates = {
        if ($tray.Checking) { return }
        $tray.Checking = $true
        Start-CPJob -Script { Get-CPLatestRelease } -OnDone {
            param($rel, $err)
            $tray.Checking = $false
            $manual = $tray.CheckManual; $tray.CheckManual = $false
            $cfg = Get-CPConfig $tray.ConfigPath
            if (-not $manual) { $cfg.LastUpdateCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm'); try { Save-CPConfig -Config $cfg -Path $tray.ConfigPath } catch { } }
            if ($err -or -not $rel) {
                Write-CPTrace "update check failed: $err"
                if ($manual) { Show-CPResultDialog -Title 'Could not check for updates' -Lines @("$err", 'Check your internet connection and try again.') -Kind Error | Out-Null }
                return
            }
            Write-CPTrace "update check: latest $($rel.Version), installed $(Get-CPCurrentVersion)"
            if (Test-CPUpdateAvailable -Release $rel -SkippedVersion $cfg.SkippedVersion -IgnoreSkipped:$manual) { $tray.Pending = $rel; & $offerUpdate }
            elseif ($manual) { Show-CPResultDialog -Title 'You have the latest version' -Lines @("CP Solution Saver $(Get-CPCurrentVersion) is up to date.") -Kind Info | Out-Null }
        }
    }
    $offerUpdate = {
        if (-not $tray.Pending -or $tray.Busy -or $tray.Quick) { return }
        $rel = $tray.Pending; $tray.Pending = $null
        $tray.Busy = $true
        try { $answer = Show-CPUpdateDialog -Release $rel } finally { $tray.Busy = $false }
        Write-CPTrace "update $($rel.Version): $answer"
        if ($answer -eq 'skip') {
            $cfg = Get-CPConfig $tray.ConfigPath; $cfg.SkippedVersion = $rel.Version
            try { Save-CPConfig -Config $cfg -Path $tray.ConfigPath } catch { }
        } elseif ($answer -eq 'update') {
            $tray.Busy = $true
            $tray.UpdateBusy = Show-CPBusy "Downloading version $($rel.Version) ..."
            Start-CPJob -Arguments @($rel) -Script { param($r) Save-CPUpdatePackage -Release $r } -OnDone {
                param($path, $err)
                try { $tray.UpdateBusy.Close(); $tray.UpdateBusy.Dispose() } catch { }
                $tray.Busy = $false
                if ($err -or -not $path) {
                    Write-CPTrace "update download failed: $err"
                    Show-CPResultDialog -Title 'The update could not be downloaded' -Lines @("$err", 'Try again later (tray menu > Check for updates), or download it from the release page.') -Kind Error | Out-Null
                    return
                }
                Write-CPTrace "starting the update installer: $path"
                Start-CPUpdateInstaller -InstallerPath $path    # it closes this app, updates it and starts it again
            }
        }
    }

    $run = {
        param([string]$c)
        Write-CPTrace "command: $c"
        switch ($c) {
            'exit' { [System.Windows.Forms.Application]::Exit(); return }
            'tray' { return }
            'update' { $tray.CheckManual = $true; & $checkUpdates; return }
            'folder' { $cfg = Get-CPConfig $tray.ConfigPath; if ($cfg.RepoPath) { Start-Process explorer.exe -ArgumentList "`"$($cfg.RepoPath)`"" }; return }
            'web' {
                $cfg = Get-CPConfig $tray.ConfigPath; $u = $null; try { $u = Get-CPRepoWebUrl $cfg.RepoPath } catch { }
                if ($u) { Start-Process $u } else { Show-CPResultDialog -Title 'Not on GitHub yet' -Lines @('Your solutions folder is not connected to GitHub.', 'Open Settings > "Connect this folder to GitHub...".') -Kind Info | Out-Null }
                return
            }
        }
        if ($tray.Busy -or $tray.Quick) {
            # a window is already open: bring it to the front instead of opening another one
            if ($script:CPActiveForm -and -not $script:CPActiveForm.IsDisposed) { Show-CPForeground $script:CPActiveForm }
            elseif ($tray.Quick -and $tray.QuickBusy) { try { $tray.QuickBusy.Activate() } catch { } }
            return
        }
        if ($c -eq 'quick') {
            $cfg = Get-CPConfig $tray.ConfigPath
            if (@(Test-CPConfig $cfg).Count) {
                # not set up yet: the tour / settings instead of an error
                $tray.Busy = $true
                try { [void](Start-CPFirstRun -Config $cfg -ConfigPath $tray.ConfigPath) } finally { $tray.Busy = $false }
                return
            }
            $tray.Busy = $true
            try { $idOk = Confirm-CPGitIdentity $cfg.RepoPath } finally { $tray.Busy = $false }
            if (-not $idOk) { return }
            $tray.Quick = $true
            $file = Get-CPActivePracticeFile $cfg
            $name = if ($file) { [IO.Path]::GetFileName($file) } else { 'solution' }
            $tray.QuickBusy = Show-CPBusy "Saving $name ..."
            Start-CPJob -Arguments @($tray.ConfigPath) -Script {
                param($p)
                Invoke-CPQuickSave -Config (Get-CPConfig $p)
            } -OnDone {
                param($res, $err)
                try { $tray.QuickBusy.Close(); $tray.QuickBusy.Dispose() } catch { }
                $tray.Quick = $false
                Write-CPTrace "quick save done: $(if ($res) { $res.Title } else { $err })"
                & $showQuickResult $res $err
            }
            return
        }
        $tray.Busy = $true
        try {
            $cfg = Get-CPConfig $tray.ConfigPath
            if ($c -in @('open', 'browse', 'report') -and (@(Test-CPConfig $cfg).Count -or -not $cfg.TutorialShown)) {
                if (-not (Start-CPFirstRun -Config $cfg -ConfigPath $tray.ConfigPath)) { return }
            }
            switch ($c) {
                'open'      { Show-CPMainWindow -Config $cfg -ConfigPath $tray.ConfigPath }
                'browse'    { Show-CPBrowser -Config $cfg }
                'report'    { Open-CPReport -Config $cfg }
                'welcome'   { [void](Start-CPFirstRun -Config $cfg -ConfigPath $tray.ConfigPath -Force) }
                'templates' { Show-CPTemplatePicker -Config $cfg -ConfigPath $tray.ConfigPath | Out-Null }
                'settings'  { Show-CPSettingsDialog -Config $cfg -ConfigPath $tray.ConfigPath | Out-Null }
            }
        } finally { $tray.Busy = $false }
    }

    $dispatch = {
        param([string]$c)
        try { & $run $c }
        catch {
            Write-CPTrace "error in '$c': $($_.Exception.Message)"
            $tray.Busy = $false
            [System.Windows.Forms.MessageBox]::Show("Something went wrong:`n`n$($_.Exception.Message)", 'CP Solution Saver', 'OK', 'Error') | Out-Null
        }
    }

    $hostWin.add_Command([Action[string]] { param($c) & $dispatch $c })

    $jobTimer = New-Object System.Windows.Forms.Timer
    $jobTimer.Interval = 150
    $jobTimer.Add_Tick({ Update-CPJobs })
    $jobTimer.Start()

    Open-CPPool   # warm up the background worker (module import) while idle

    $startTimer = New-Object System.Windows.Forms.Timer
    $startTimer.Interval = 30
    $startTimer.Add_Tick({
        $startTimer.Stop()
        $cfg0 = Get-CPConfig $tray.ConfigPath
        if (-not $cfg0.TutorialShown) {
            # first run: welcome tour, then settings if needed, then the command that started us (if any)
            $tray.Busy = $true
            try { $ready = Start-CPFirstRun -Config $cfg0 -ConfigPath $tray.ConfigPath } catch { Write-CPTrace "first run: $($_.Exception.Message)"; $ready = $false } finally { $tray.Busy = $false }
            if ($ready -and $Command -and $Command -notin @('tray', 'welcome')) { & $dispatch $Command }
        }
        elseif ($Command -and $Command -ne 'tray') { & $dispatch $Command }
        # no notification on start (the user asked for none); a hotkey taken by another app shows in the icon's tooltip
    })
    $startTimer.Start()
    if ($failed.Count) { $icon.Text = ('CP Solution Saver - in use by another app: ' + ($failed -join ', ')).Substring(0, [Math]::Min(63, ('CP Solution Saver - in use by another app: ' + ($failed -join ', ')).Length)) }

    # automatic update checks: 45 s after start, then every 10 minutes see if 12 hours have passed
    $updTimer = New-Object System.Windows.Forms.Timer
    $updTimer.Interval = 45000
    $updTimer.Add_Tick({
        $updTimer.Interval = 600000
        if ($tray.Pending) { & $offerUpdate; return }
        if ($tray.Busy -or $tray.Quick -or $tray.Checking) { return }
        try { if (Test-CPUpdateCheckDue -Config (Get-CPConfig $tray.ConfigPath)) { $tray.CheckManual = $false; & $checkUpdates } } catch { Write-CPTrace "update timer: $($_.Exception.Message)" }
    })
    $updTimer.Start()
    Write-CPTrace "host ready"

    try { [System.Windows.Forms.Application]::Run() }
    finally {
        Write-CPTrace 'host exiting'
        $jobTimer.Stop(); $updTimer.Stop()
        $icon.Visible = $false; $icon.Dispose()
        $hostWin.Dispose()
        if ($script:CPPool) { try { $script:CPPool.Close() } catch { } }
    }
}
