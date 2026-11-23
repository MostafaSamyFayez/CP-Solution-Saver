<#
.SYNOPSIS
    Removes CP Solution Saver (app files, shortcuts, the tray app).
    Your solutions folder and practice files are never touched.

.DESCRIPTION
    Double-clicking "Uninstall CP Solution Saver" asks first, with a choice to also delete your
    settings, templates and backups (kept by default, so a reinstall picks them up).

.EXAMPLE
    uninstall.ps1                         # asks (window)
    uninstall.ps1 -Yes                    # no questions, keeps settings
    uninstall.ps1 -Yes -RemoveSettings    # no questions, deletes settings too
#>
param(
    [switch]$RemoveSettings,
    [switch]$Yes,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver')
)

Set-Location $env:TEMP
$data = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'CPSolutionSaver'
$ask = -not $Yes

if ($ask) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $icon = $null
    try { $ico = Join-Path $InstallDir 'app.ico'; if (Test-Path -LiteralPath $ico) { $icon = New-Object System.Drawing.Icon(([IO.MemoryStream]::new([IO.File]::ReadAllBytes($ico)))) } } catch { }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Uninstall CP Solution Saver'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.75); $f.BackColor = [System.Drawing.Color]::White
    $f.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96); $f.AutoScaleMode = 'Dpi'
    $f.AutoSize = $true; $f.AutoSizeMode = 'GrowAndShrink'
    if ($icon) { $f.Icon = $icon }
    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.AutoSize = $true; $grid.ColumnCount = 1; $grid.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 12)
    $t = New-Object System.Windows.Forms.Label; $t.Text = 'Uninstall CP Solution Saver?'; $t.AutoSize = $true
    $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13); $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $b = New-Object System.Windows.Forms.Label; $b.AutoSize = $true; $b.MaximumSize = New-Object System.Drawing.Size(470, 0)
    $b.Text = "This removes the app, its shortcuts, the tray icon and the keyboard shortcuts.`r`n`r`nYour solutions folder and your practice files are NOT touched."
    $b.ForeColor = [System.Drawing.Color]::FromArgb(87, 96, 106); $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $c = New-Object System.Windows.Forms.CheckBox; $c.AutoSize = $true; $c.Checked = [bool]$RemoveSettings
    $c.Text = 'Also delete my settings, code templates and backups'
    $c.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
    $h = New-Object System.Windows.Forms.Label; $h.AutoSize = $true; $h.MaximumSize = New-Object System.Drawing.Size(470, 0)
    $h.Text = "Leave it unticked if you may install the app again: it will remember your setup.`r`n($data)"
    $h.ForeColor = [System.Drawing.Color]::Gray; $h.Margin = New-Object System.Windows.Forms.Padding(18, 0, 0, 14)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $mkBtn = {
        param($text, $primary)
        $x = New-Object System.Windows.Forms.Button; $x.Text = $text; $x.AutoSize = $true; $x.MinimumSize = New-Object System.Drawing.Size(100, 0)
        $x.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4); $x.FlatStyle = 'Flat'; $x.UseVisualStyleBackColor = $false
        if ($primary) { $x.BackColor = [System.Drawing.Color]::FromArgb(207, 34, 46); $x.ForeColor = [System.Drawing.Color]::White; $x.FlatAppearance.BorderColor = $x.BackColor }
        else { $x.BackColor = [System.Drawing.Color]::White; $x.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(208, 215, 222) }
        $x
    }
    $go = & $mkBtn 'Uninstall' $true; $go.DialogResult = 'OK'
    $no = & $mkBtn 'Cancel' $false; $no.DialogResult = 'Cancel'
    $btns.Controls.Add($no); $btns.Controls.Add($go)
    foreach ($ctl in @($t, $b, $c, $h, $btns)) { $grid.Controls.Add($ctl) }
    $f.Controls.Add($grid); $f.AcceptButton = $no; $f.CancelButton = $no
    $f.Add_Shown({ $f.Activate(); $no.Focus() })
    $answer = $f.ShowDialog()
    $RemoveSettings = $c.Checked
    $f.Dispose()
    if ($answer -ne 'OK') { exit 0 }
}

$done = New-Object System.Collections.Generic.List[string]
# stop the tray app first (its files are in use)
try {
    $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\CPSolutionSaver_cmd_exit'); [void]$ev.Set(); $ev.Dispose()
    for ($i = 0; $i -lt 60; $i++) { try { $m = [System.Threading.Mutex]::OpenExisting('Local\CPSolutionSaver_Host'); $m.Dispose(); Start-Sleep -Milliseconds 100 } catch { break } }
    Start-Sleep -Milliseconds 300
    $done.Add('Stopped the tray app')
} catch { }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*CPSaver.ps1*-Tray*' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch { } }
# .bat launchers that older versions put next to the practice project
try {
    Import-Module (Join-Path $InstallDir 'CPSaver.Core.psm1') -Force -DisableNameChecking -ErrorAction Stop
    foreach ($x in @(Remove-CPPracticeLaunchers -Config (Get-CPConfig))) { $done.Add("Removed $x") }
    Remove-Module CPSaver.Core -ErrorAction SilentlyContinue
} catch { }
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'CP Solution Saver.lnk'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CP Solution Saver'
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CP Solution Saver.lnk'
foreach ($p in @($startup, $menu, $desk, $InstallDir)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; $done.Add("Removed $p") }
}
if ($RemoveSettings) {
    if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue; $done.Add("Removed $data") }
    $kept = 'Your settings, templates and backups were deleted.'
} else {
    $kept = "Your settings, templates and backups were kept, so installing again picks them up:`r`n$data"
}

$done | ForEach-Object { Write-Host $_ }
Write-Host $kept
Write-Host 'CP Solution Saver was uninstalled. Your solutions folder was not changed.' -ForegroundColor Green
if ($ask) {
    [System.Windows.Forms.MessageBox]::Show("CP Solution Saver was uninstalled.`r`n`r`n$kept`r`n`r`nYour solutions folder was not changed.",
        'CP Solution Saver', 'OK', 'Information') | Out-Null
}
