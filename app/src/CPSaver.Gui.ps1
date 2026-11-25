# CPSaver.Gui.ps1 - Windows Forms user interface for CP Solution Saver.
# Dot-sourced by CPSaver.ps1 after CPSaver.Core.psm1 is imported.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:CPGuiDir  = $PSScriptRoot
$script:CPCorePath = Join-Path $PSScriptRoot 'CPSaver.Core.psm1'

# Native helpers (hotkeys, sharp text on scaled screens), compiled by the installer.
$script:CPNative = $false
$nativeDll = Join-Path $PSScriptRoot 'CPSaver.Native.dll'
if (Test-Path -LiteralPath $nativeDll) {
    try { Add-Type -Path $nativeDll -ErrorAction Stop; $script:CPNative = $true }
    catch { if ('CPSaverNative.HostWindow' -as [type]) { $script:CPNative = $true } }
}
if ($script:CPNative -and -not $script:CPDpiDone) { [CPSaverNative.Dpi]::Enable(); $script:CPDpiDone = $true }
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- theme
$script:CPFont      = New-Object System.Drawing.Font('Segoe UI', 9.75)
$script:CPFontBold  = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
$script:CPFontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$script:CPFontHead  = New-Object System.Drawing.Font('Segoe UI Semibold', 12.5)
$script:CPFontSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$script:CPFontMono  = New-Object System.Drawing.Font('Consolas', 9.5)
$script:CPGreen     = [System.Drawing.Color]::FromArgb(26, 127, 55)
$script:CPOrange    = [System.Drawing.Color]::FromArgb(188, 76, 0)
$script:CPRed       = [System.Drawing.Color]::FromArgb(207, 34, 46)
$script:CPBlue      = [System.Drawing.Color]::FromArgb(9, 105, 218)
$script:CPAccent    = [System.Drawing.Color]::FromArgb(36, 41, 47)
$script:CPBg        = [System.Drawing.Color]::FromArgb(246, 248, 250)
$script:CPBorder    = [System.Drawing.Color]::FromArgb(208, 215, 222)
$script:CPMuted     = [System.Drawing.Color]::FromArgb(87, 96, 106)
$script:CPPrimary   = [System.Drawing.Color]::FromArgb(31, 136, 61)
$script:CPPrimaryHi = [System.Drawing.Color]::FromArgb(26, 115, 52)

$script:CPCommonTopics = @(
    'implementation', 'math', 'greedy', 'dp', 'data structures', 'brute force', 'constructive algorithms',
    'graphs', 'sortings', 'binary search', 'dfs and similar', 'bfs', 'trees', 'strings', 'number theory',
    'combinatorics', 'two pointers', 'prefix sums', 'sliding window', 'bitmasks', 'geometry', 'dsu',
    'shortest paths', 'probabilities', 'divide and conquer', 'hashing', 'games', 'interactive',
    'matrices', 'stack', 'queue', 'deque', 'priority queue', 'recursion', 'backtracking', 'simulation',
    'sieve', 'segment tree', 'fenwick tree', 'stl', 'string suffix structures', 'flows', 'graph matchings'
)

function Invoke-CPSafe {
    param([scriptblock]$Action, [string]$What = 'That action')
    try { & $Action }
    catch {
        [System.Windows.Forms.MessageBox]::Show("$What failed:`n`n$($_.Exception.Message)", 'CP Solution Saver',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Get-CPAppIcon {
    if ($script:CPIconCache) { return $script:CPIconCache }
    $ico = Join-Path $script:CPGuiDir 'app.ico'
    try {
        if (Test-Path -LiteralPath $ico) { $script:CPIconCache = New-Object System.Drawing.Icon($ico) }
        else { $script:CPIconCache = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')) }
    } catch { $script:CPIconCache = $null }
    return $script:CPIconCache
}

function Get-CPAppImage([int]$Size = 32) {
    $png = Join-Path $script:CPGuiDir 'app.png'
    if (Test-Path -LiteralPath $png) {
        try { return [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,[IO.File]::ReadAllBytes($png)))) } catch { }
    }
    $ico = Get-CPAppIcon
    if (-not $ico) { return $null }
    try { return (New-Object System.Drawing.Icon($ico, $Size, $Size)).ToBitmap() } catch { return $ico.ToBitmap() }
}

function New-CPLabel([string]$Text, $Font = $script:CPFont) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $true; $l.Font = $Font
    $l.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $l.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
    return $l
}

function New-CPButton([string]$Text, [int]$Width = 0) {
    # flat, light button with a hover colour
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Font = $script:CPFont; $b.AutoSize = $true
    $b.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
    $b.Margin = New-Object System.Windows.Forms.Padding(3, 4, 6, 4)
    $b.FlatStyle = 'Flat'; $b.BackColor = [System.Drawing.Color]::White; $b.ForeColor = $script:CPAccent
    $b.FlatAppearance.BorderColor = $script:CPBorder
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(234, 238, 242)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    if ($Width) { $b.MinimumSize = New-Object System.Drawing.Size($Width, 0) }
    return $b
}

function Set-CPPrimary($Button) {
    $Button.BackColor = $script:CPPrimary; $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderColor = $script:CPPrimaryHi
    $Button.FlatAppearance.MouseOverBackColor = $script:CPPrimaryHi
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(20, 95, 43)
    $Button.Font = $script:CPFontBold
}

function New-CPForm([string]$Title, [int]$Width, [int]$Height, [int]$MinWidth = 0, [int]$MinHeight = 0) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title; $f.Font = $script:CPFont; $f.StartPosition = 'CenterScreen'
    $f.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $f.Size = New-Object System.Drawing.Size($Width, $Height)
    if ($MinWidth) { $f.MinimumSize = New-Object System.Drawing.Size($MinWidth, $MinHeight) }
    $f.BackColor = $script:CPBg; $f.KeyPreview = $true
    $ico = Get-CPAppIcon; if ($ico) { $f.Icon = $ico }
    return $f
}

function New-CPHeader {
    <# Dark header strip: icon, title, subtitle, and a right-hand label (returned as .Right). #>
    param([string]$Title, [string]$Subtitle = '')
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Top'; $p.Height = 58; $p.BackColor = $script:CPAccent; $p.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size(40, 40); $pic.Location = New-Object System.Drawing.Point(14, 9)
    $pic.SizeMode = 'Zoom'; $pic.Image = Get-CPAppImage 48
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title; $t.Font = $script:CPFontHead; $t.ForeColor = [System.Drawing.Color]::White; $t.AutoSize = $true; $t.UseMnemonic = $false
    $t.Location = New-Object System.Drawing.Point(62, 7)
    $s = New-Object System.Windows.Forms.Label
    $s.UseMnemonic = $false; $s.Text = $Subtitle; $s.Font = $script:CPFontSmall; $s.ForeColor = [System.Drawing.Color]::FromArgb(201, 209, 217); $s.AutoSize = $true
    $s.Location = New-Object System.Drawing.Point(64, 32)
    $r = New-Object System.Windows.Forms.Label
    $r.UseMnemonic = $false; $r.Text = ''; $r.Font = $script:CPFontSmall; $r.ForeColor = [System.Drawing.Color]::FromArgb(201, 209, 217)
    $r.AutoSize = $false; $r.Dock = 'Right'; $r.Width = 330; $r.TextAlign = 'MiddleRight'
    $p.Controls.Add($r); $p.Controls.Add($pic); $p.Controls.Add($t); $p.Controls.Add($s)
    return @{ Panel = $p; Right = $r; Subtitle = $s }
}

function Format-CPStats([string]$RepoPath) {
    try {
        $s = Get-CPStats $RepoPath
        $txt = "$($s.Problems) problem$(if ($s.Problems -ne 1) { 's' }) solved"
        if ($s.ThisWeek) { $txt += "   |   $($s.ThisWeek) this week" }
        return $txt
    } catch { return '' }
}

function Show-CPForeground($Form) {
    # bring a window in front of other apps (e.g. Visual Studio) when opened from a hotkey
    try {
        $Form.TopMost = $true; $Form.Activate(); $Form.TopMost = $false
        if ($script:CPNative) { [CPSaverNative.HostWindow]::BringToFront($Form.Handle) }
    } catch { }
}

# ---------------------------------------------------------------- background work
# Online lookups and git run in a runspace pool so windows never freeze.
# Start-CPJob queues work; Update-CPJobs (called by a timer of the open window or
# the tray) runs the -OnDone scriptblock on the UI thread when it finishes.
$script:CPJobs = New-Object System.Collections.ArrayList
$script:CPPool = $null

function Open-CPPool {
    <# Starts opening the pool in the background (call early). #>
    if ($script:CPPool) { return }
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.ImportPSModule(@($script:CPCorePath))
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $script:CPPool = [runspacefactory]::CreateRunspacePool(1, 2, $iss, $Host)
        $script:CPPoolOpen = $script:CPPool.BeginOpen($null, $null)
    } catch { $script:CPPool = $null }
}

function Get-CPPool {
    if (-not $script:CPPool) { Open-CPPool }
    if (-not $script:CPPool) { return $null }
    try {
        if ($script:CPPoolOpen) { $script:CPPool.EndOpen($script:CPPoolOpen); $script:CPPoolOpen = $null }
        if ($script:CPPool.RunspacePoolStateInfo.State -ne 'Opened') { return $null }
        return $script:CPPool
    } catch { $script:CPPool = $null; return $null }
}

function Start-CPJob {
    <# Runs -Script with -Arguments in the background; calls -OnDone with (result, error message). Falls back to running it now. #>
    param([Parameter(Mandatory)][scriptblock]$Script, [object[]]$Arguments = @(), [Parameter(Mandatory)][scriptblock]$OnDone, $Owner)
    $pool = Get-CPPool
    if (-not $pool) {
        $r = $null; $e = $null
        try { $r = & $Script @Arguments } catch { $e = $_.Exception.Message }
        & $OnDone $r $e
        return
    }
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($Script.ToString())
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $h = $ps.BeginInvoke()
    [void]$script:CPJobs.Add(@{ PS = $ps; H = $h; OnDone = $OnDone; Owner = $Owner })
}

function Update-CPJobs {
    foreach ($j in @($script:CPJobs)) {
        if (-not $j.H.IsCompleted) { continue }
        $script:CPJobs.Remove($j)
        $r = $null; $e = $null
        try { $out = $j.PS.EndInvoke($j.H); if ($out.Count -gt 0) { $r = $out[$out.Count - 1] } }
        catch { $e = $_.Exception.InnerException.Message; if (-not $e) { $e = $_.Exception.Message } }
        if ($null -eq $r -and -not $e -and $j.PS.Streams.Error.Count) { $e = [string]$j.PS.Streams.Error[0] }
        $j.PS.Dispose()
        if ($r -is [psobject] -and $r.BaseObject -is [System.Collections.IDictionary]) { $r = $r.BaseObject }
        if ($j.Owner -and $j.Owner.IsDisposed) { continue }   # its window was closed meanwhile
        try { & $j.OnDone $r $e } catch { }
    }
}

function Test-CPJobsRunning { return ($script:CPJobs.Count -gt 0) }

# ---------------------------------------------------------------- busy popup + result window
function Show-CPBusy {
    <# Small "working..." window in the middle of the screen; returns it (call .Close()). #>
    param([string]$Text)
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.ShowInTaskbar = $false
    $f.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96); $f.AutoScaleMode = 'Dpi'
    $f.Size = New-Object System.Drawing.Size(380, 96); $f.BackColor = $script:CPAccent; $f.Padding = New-Object System.Windows.Forms.Padding(2)
    $inner = New-Object System.Windows.Forms.Panel; $inner.Dock = 'Fill'; $inner.BackColor = [System.Drawing.Color]::White
    $pic = New-Object System.Windows.Forms.PictureBox; $pic.Image = Get-CPAppImage 32; $pic.SizeMode = 'Zoom'
    $pic.Size = New-Object System.Drawing.Size(32, 32); $pic.Location = New-Object System.Drawing.Point(16, 18)
    $l = New-Object System.Windows.Forms.Label; $l.Text = $Text; $l.Font = $script:CPFontBold; $l.AutoSize = $false
    $l.Location = New-Object System.Drawing.Point(60, 14); $l.Size = New-Object System.Drawing.Size(300, 24); $l.AutoEllipsis = $true
    $bar = New-Object System.Windows.Forms.ProgressBar; $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 25
    $bar.Location = New-Object System.Drawing.Point(62, 46); $bar.Size = New-Object System.Drawing.Size(290, 12)
    $inner.Controls.Add($pic); $inner.Controls.Add($l); $inner.Controls.Add($bar)
    $f.Controls.Add($inner)
    $f.Show(); [System.Windows.Forms.Application]::DoEvents()
    return $f
}

function Show-CPResultDialog {
    <#
      A clean result window (used by quick save). -Kind Success | Info | Error.
      Returns 'ok', 'open' (open the full window) or 'web'.
    #>
    param([string]$Title, [string[]]$Lines, [string]$Kind = 'Success', [string]$Url, [switch]$OfferOpen)
    $f = New-CPForm 'CP Solution Saver' 520 250
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $f.BackColor = [System.Drawing.Color]::White
    $color = switch ($Kind) { 'Error' { $script:CPRed } 'Info' { $script:CPBlue } default { $script:CPPrimary } }
    $strip = New-Object System.Windows.Forms.Panel; $strip.Dock = 'Left'; $strip.Width = 6; $strip.BackColor = $color
    $grid = New-Object System.Windows.Forms.TableLayoutPanel; $grid.Dock = 'Fill'; $grid.ColumnCount = 2; $grid.RowCount = 3
    $grid.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 10)
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $mark = New-Object System.Windows.Forms.Label
    $mark.Text = $(switch ($Kind) { 'Error' { '!' } 'Info' { 'i' } default { [string][char]0x2713 } })
    $mark.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold); $mark.ForeColor = [System.Drawing.Color]::White
    $mark.BackColor = $color; $mark.AutoSize = $false; $mark.Size = New-Object System.Drawing.Size(42, 42); $mark.TextAlign = 'MiddleCenter'
    $mark.Margin = New-Object System.Windows.Forms.Padding(0, 2, 14, 0)
    $t = New-Object System.Windows.Forms.Label; $t.UseMnemonic = $false; $t.Text = $Title; $t.Font = $script:CPFontTitle; $t.ForeColor = $script:CPAccent
    $t.AutoSize = $true; $t.MaximumSize = New-Object System.Drawing.Size(420, 0); $t.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 6)
    $body = New-Object System.Windows.Forms.Label; $body.UseMnemonic = $false; $body.Text = (($Lines | Where-Object { $_ }) -join "`r`n")
    $body.Font = $script:CPFont; $body.ForeColor = $script:CPMuted; $body.AutoSize = $true; $body.MaximumSize = New-Object System.Drawing.Size(420, 0)
    $grid.Controls.Add($mark, 0, 0); $grid.SetRowSpan($mark, 2)
    $grid.Controls.Add($t, 1, 0); $grid.Controls.Add($body, 1, 1)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $ok = New-CPButton 'OK' 90; Set-CPPrimary $ok
    $btns.Controls.Add($ok)
    $result = @{ Value = 'ok' }
    if ($Url) { $web = New-CPButton 'Open on GitHub'; $btns.Controls.Add($web); $web.Add_Click({ $result.Value = 'web'; $f.Close() }) }
    if ($OfferOpen) { $op = New-CPButton 'Open CP Solution Saver'; $btns.Controls.Add($op); $op.Add_Click({ $result.Value = 'open'; $f.Close() }) }
    $ok.Add_Click({ $result.Value = 'ok'; $f.Close() })
    $grid.Controls.Add($btns, 0, 2); $grid.SetColumnSpan($btns, 2)
    $f.Controls.Add($grid); $f.Controls.Add($strip)
    $f.AcceptButton = $ok; $f.CancelButton = $ok
    $f.AutoSize = $true; $f.AutoSizeMode = 'GrowOnly'
    $f.Add_Shown({ Show-CPForeground $f; $ok.Focus() })
    [void]$f.ShowDialog()
    $f.Dispose()
    if ($result.Value -eq 'web' -and $Url) { try { Start-Process $Url } catch { } }
    return $result.Value
}

# ============================================================================
#  First-time helpers: git name/email, solutions folder
# ============================================================================
function Show-CPGitIdentityDialog {
    <# Asks for the name + email git records with each save and stores them (git config --global).
       Returns $true when saved. #>
    param([string]$Reason = '')
    $f = New-CPForm 'CP Solution Saver - Git name and email' 560 330
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $hdr = New-CPHeader 'Tell Git who you are' 'One-time setup on this PC'; $hdr.Right.Visible = $false
    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.ColumnCount = 2; $grid.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 10)
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $text = 'Git saves a name and email with every solution you save (even without GitHub). ' +
            'Use the email of your GitHub account if you want your saves linked to your profile.'
    if ($Reason) { $text = "$Reason`r`n`r`n$text" }
    $intro = New-CPLabel $text; $intro.MaximumSize = New-Object System.Drawing.Size(500, 0); $intro.ForeColor = $script:CPMuted
    $grid.Controls.Add($intro, 0, 0); $grid.SetColumnSpan($intro, 2)
    $cur = Get-CPGitIdentity
    $grid.Controls.Add((New-CPLabel 'Name:'), 0, 1)
    $nameBox = New-CPTextBox; $nameBox.Text = $(if ($cur.Name) { $cur.Name } else { $env:USERNAME })
    $grid.Controls.Add($nameBox, 1, 1)
    $grid.Controls.Add((New-CPLabel 'Email:'), 0, 2)
    $mailBox = New-CPTextBox; $mailBox.Text = $cur.Email
    $grid.Controls.Add($mailBox, 1, 2)
    $err = New-CPLabel ''; $err.ForeColor = $script:CPRed; $err.MaximumSize = New-Object System.Drawing.Size(500, 0)
    $grid.Controls.Add($err, 0, 3); $grid.SetColumnSpan($err, 2)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $ok = New-CPButton 'Save' 100; Set-CPPrimary $ok
    $cancel = New-CPButton 'Cancel' 90; $cancel.DialogResult = 'Cancel'
    $btns.Controls.Add($cancel); $btns.Controls.Add($ok)
    $grid.Controls.Add($btns, 0, 4); $grid.SetColumnSpan($btns, 2)
    $ok.Add_Click({
        try { Set-CPGitIdentity -Name $nameBox.Text -Email $mailBox.Text; $f.DialogResult = 'OK'; $f.Close() }
        catch { $err.Text = $_.Exception.Message }
    })
    $f.Controls.Add($grid); $f.Controls.Add($hdr.Panel)
    $f.AcceptButton = $ok; $f.CancelButton = $cancel
    $f.Add_Shown({ Show-CPForeground $f; if ($mailBox.Text) { $nameBox.Focus() } else { $mailBox.Focus() } })
    $r = $f.ShowDialog(); $f.Dispose()
    return ($r -eq 'OK')
}

function Confirm-CPGitIdentity {
    <# $true if git knows the user's name + email (asks for them once if not). #>
    param([string]$RepoPath)
    if (-not (Test-CPGitAvailable)) { return $true }   # the save itself explains that git is missing
    if ((Get-CPGitIdentity $RepoPath).Ok) { return $true }
    return (Show-CPGitIdentityDialog -Reason 'Before your first save, Git needs your name and email.')
}

function Use-CPRepoFolder {
    <# Checks a folder chosen for the solutions. An empty folder becomes a new local repo automatically;
       a folder with files (not a repo) is turned into one only if the user agrees. Returns the path or $null. #>
    param([string]$Path, [switch]$Quiet)
    if (-not $Path) { return $null }
    switch (Test-CPRepoFolder $Path) {
        'repo'  { return $Path }
        'empty' {
            $full = Initialize-CPRepo $Path
            if (-not $Quiet) {
                [System.Windows.Forms.MessageBox]::Show("Created a new local repo in:`n$full`n`nYour solutions are saved here. To put them on GitHub later, use ""Connect to GitHub"" in Settings or the README steps.", 'CP Solution Saver', 'OK', 'Information') | Out-Null
            }
            return $full
        }
        'files' {
            $a = [System.Windows.Forms.MessageBox]::Show("This folder is not a git repo yet and already has files in it:`n$Path`n`nTurn it into a repo for your solutions? (Its files are kept as they are.)`n`nTip: an empty folder is usually the better choice.", 'CP Solution Saver', 'YesNo', 'Question')
            if ($a -eq 'Yes') { return (Initialize-CPRepo $Path) }
            return $null
        }
    }
    return $null
}

# ============================================================================
#  Welcome tour (first run, and "How to use" in the tray menu)
# ============================================================================
function Show-CPWelcome {
    <# A short paged tour. Returns $true if finished with "Set up now" / "Start". #>
    param([switch]$NeedsSetup)
    $f = New-CPForm 'Welcome to CP Solution Saver' 720 520
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $hdr = New-CPHeader 'Welcome to CP Solution Saver' 'A quick tour - 5 short steps'
    $f.BackColor = [System.Drawing.Color]::White

    $keycap = {
        param([string]$Keys, [string]$What)
        $row = New-Object System.Windows.Forms.FlowLayoutPanel; $row.AutoSize = $true; $row.WrapContents = $false; $row.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
        foreach ($k in ($Keys -split '\+')) {
            $kl = New-Object System.Windows.Forms.Label; $kl.Text = $k; $kl.AutoSize = $true; $kl.Font = $script:CPFontBold
            $kl.BorderStyle = 'FixedSingle'; $kl.BackColor = $script:CPBg; $kl.Padding = New-Object System.Windows.Forms.Padding(6, 3, 6, 3)
            $kl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0); $row.Controls.Add($kl)
        }
        $wl = New-Object System.Windows.Forms.Label; $wl.Text = $What; $wl.AutoSize = $true; $wl.Font = $script:CPFont; $wl.UseMnemonic = $false
        $wl.Margin = New-Object System.Windows.Forms.Padding(10, 4, 0, 0); $row.Controls.Add($wl)
        return $row
    }
    $para = {
        param([string]$Text, $Font = $script:CPFont, $Color = $script:CPAccent)
        $l = New-Object System.Windows.Forms.Label; $l.Text = $Text; $l.AutoSize = $true; $l.Font = $Font; $l.ForeColor = $Color; $l.UseMnemonic = $false
        $l.MaximumSize = New-Object System.Drawing.Size(640, 0); $l.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)
        return $l
    }
    $code = {
        param([string]$Text)
        $t = New-Object System.Windows.Forms.TextBox; $t.Multiline = $true; $t.ReadOnly = $true; $t.Text = $Text; $t.Font = $script:CPFontMono
        $t.BackColor = $script:CPBg; $t.BorderStyle = 'FixedSingle'; $t.Width = 640; $t.Height = 132; $t.TabStop = $false
        $t.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)
        return $t
    }
    $newPage = {
        param([string]$Title)
        $p = New-Object System.Windows.Forms.FlowLayoutPanel; $p.FlowDirection = 'TopDown'; $p.WrapContents = $false; $p.Dock = 'Fill'
        $p.Padding = New-Object System.Windows.Forms.Padding(26, 18, 26, 6); $p.AutoScroll = $true; $p.Visible = $false
        $p.Controls.Add((& $para $Title $script:CPFontTitle))
        return $p
    }

    $pages = New-Object System.Collections.Generic.List[object]
    # 1 - what it is
    $p = & $newPage 'Save every accepted solution with one shortcut'
    $p.Controls.Add((& $para 'You solve problems in one practice file (like main.cpp). When a solution is accepted, press a shortcut: CP Solution Saver copies it into your solutions folder as its own file (e.g. Codeforces/4A_Watermelon.cpp), keeps a README with your progress and indexes by topic and difficulty, and uploads it to GitHub if you connected one.'))
    $p.Controls.Add((& $para 'It runs quietly in the tray (the icon next to the clock, bottom-right). Right-click the icon for everything; nothing needs to stay open.' $script:CPFont $script:CPMuted))
    $pages.Add($p)
    # 2 - the header
    $p = & $newPage 'Write your solution with a small header'
    $p.Controls.Add((& $para 'Put a comment like this at the top of your practice file. Only the Problem Link is required - it identifies the problem, so solving it again updates the same file instead of making a copy.'))
    $p.Controls.Add((& $code "/*`r`n * Problem Name: Watermelon`r`n * Problem Link: https://codeforces.com/problemset/problem/4/A`r`n * Difficulty:   800`r`n * Topics:       math, brute force`r`n * Notes:        even and > 2`r`n */"))
    $p.Controls.Add((& $para 'For Codeforces, LeetCode, AtCoder and CSES the name, difficulty and topics are filled in from the link automatically. C++, C and Python (# comments) are supported. The code templates already have this header.' $script:CPFont $script:CPMuted))
    $pages.Add($p)
    # 3 - save
    $p = & $newPage 'Save it'
    $p.Controls.Add((& $keycap 'Ctrl+Alt+Shift+S' 'Open the save window: check the details, then Save (Ctrl+S).'))
    $p.Controls.Add((& $keycap 'Ctrl+Alt+Shift+F' 'Quick save: no window, just saves and shows the result.'))
    $p.Controls.Add((& $para 'Saving the same problem again updates its file (nothing is duplicated). After a successful save your practice file is reset to a clean template, ready for the next problem - you can turn that off.' $script:CPFont $script:CPMuted))
    $pages.Add($p)
    # 4 - find again
    $p = & $newPage 'Find and reuse your solutions'
    $p.Controls.Add((& $keycap 'Ctrl+Alt+Shift+B' 'Solved problems: search by name, filter by platform, topic, difficulty or language.'))
    $p.Controls.Add((& $para 'Pick one and press Enter to load it back into your practice file to review it (your current file is backed up first).'))
    $p.Controls.Add((& $para 'Tray menu > Code templates: choose a starting template (competitive C++, fast I/O, multiple test cases, C, Python ...).' $script:CPFont $script:CPMuted))
    $pages.Add($p)
    # 5 - setup
    $p = & $newPage $(if ($NeedsSetup) { 'One last thing: set it up' } else { 'You are all set' })
    if ($NeedsSetup) {
        $p.Controls.Add((& $para 'Next, choose:'))
        $p.Controls.Add((& $para '1.  Your practice file - the main.cpp (or main.c / main.py) you solve problems in.'))
        $p.Controls.Add((& $para '2.  A folder for your solutions - pick or make an empty folder; it becomes a repo automatically. Already have a solutions repo on GitHub? Use "Clone a GitHub repo...".'))
        $p.Controls.Add((& $para 'GitHub is optional: everything works on your PC alone, and you can connect GitHub later.' $script:CPFont $script:CPMuted))
    } else {
        $p.Controls.Add((& $para 'Solve a problem, get Accepted, press Ctrl+Alt+Shift+F. That''s it.'))
    }
    $p.Controls.Add((& $para 'See this tour again any time: right-click the tray icon > How to use.' $script:CPFont $script:CPMuted))
    $pages.Add($p)

    $body = New-Object System.Windows.Forms.Panel; $body.Dock = 'Fill'
    foreach ($pg in $pages) { $body.Controls.Add($pg) }

    $bar = New-Object System.Windows.Forms.TableLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 58; $bar.ColumnCount = 2; $bar.RowCount = 1
    $bar.Padding = New-Object System.Windows.Forms.Padding(20, 8, 16, 8); $bar.BackColor = $script:CPBg
    [void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$bar.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $step = New-Object System.Windows.Forms.Label; $step.AutoSize = $true; $step.ForeColor = $script:CPMuted; $step.Anchor = 'Left'; $step.Font = $script:CPFont
    $nav = New-Object System.Windows.Forms.FlowLayoutPanel; $nav.FlowDirection = 'RightToLeft'; $nav.AutoSize = $true; $nav.WrapContents = $false; $nav.Anchor = 'Right'
    $next = New-CPButton 'Next' 110; Set-CPPrimary $next
    $back = New-CPButton 'Back' 90
    $skip = New-CPButton 'Skip tour' 90
    $nav.Controls.Add($next); $nav.Controls.Add($back); $nav.Controls.Add($skip)
    $bar.Controls.Add($step, 0, 0); $bar.Controls.Add($nav, 1, 0)

    $st = @{ Page = 0; Done = $false }
    $show = {
        for ($i = 0; $i -lt $pages.Count; $i++) { $pages[$i].Visible = ($i -eq $st.Page) }
        $step.Text = "Step $($st.Page + 1) of $($pages.Count)"
        $back.Enabled = ($st.Page -gt 0)
        $last = ($st.Page -eq $pages.Count - 1)
        $next.Text = $(if ($last) { if ($NeedsSetup) { 'Set up now' } else { 'Start' } } else { 'Next' })
        $skip.Visible = -not $last
    }
    $next.Add_Click({ if ($st.Page -lt $pages.Count - 1) { $st.Page++; & $show } else { $st.Done = $true; $f.Close() } })
    $back.Add_Click({ if ($st.Page -gt 0) { $st.Page--; & $show } })
    $skip.Add_Click({ $st.Done = $true; $f.Close() })
    $f.KeyPreview = $true
    $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Right') { $next.PerformClick() } elseif ($e.KeyCode -eq 'Left') { $back.PerformClick() } elseif ($e.KeyCode -eq 'Escape') { $f.Close() } })

    $f.Controls.Add($body); $f.Controls.Add($bar); $f.Controls.Add($hdr.Panel)
    $f.AcceptButton = $next
    & $show
    $f.Add_Shown({ Show-CPForeground $f; $next.Focus() })
    [void]$f.ShowDialog(); $f.Dispose()
    return $st.Done
}

function Start-CPFirstRun {
    <# First run: the welcome tour once, then Settings if something is missing. Returns $true if the app is ready. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$ConfigPath, [switch]$Force)
    $needs = @(Test-CPConfig $Config).Count -gt 0
    if ($Force -or -not $Config.TutorialShown) {
        [void](Show-CPWelcome -NeedsSetup:$needs)
        $Config.TutorialShown = $true
        try { Save-CPConfig -Config $Config -Path $ConfigPath } catch { }
    }
    if ($needs -and -not $Force) {
        [void](Show-CPSettingsDialog -Config $Config -ConfigPath $ConfigPath -Intro 'Choose your practice file and a folder for your solutions to get started.')
    }
    return (@(Test-CPConfig $Config).Count -eq 0)
}

# ============================================================================
#  Updates (asks before updating; the tray app checks now and then)
# ============================================================================
function Show-CPUpdateDialog {
    <# "Version X is available". Returns 'update', 'later' or 'skip'. #>
    param([Parameter(Mandatory)][hashtable]$Release)
    $f = New-CPForm 'CP Solution Saver - Update available' 620 200
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $f.BackColor = [System.Drawing.Color]::White; $f.AutoSize = $true; $f.AutoSizeMode = 'GrowOnly'
    $hdr = New-CPHeader "Version $($Release.Version) is available" "You have version $(Get-CPCurrentVersion)"; $hdr.Right.Visible = $false
    $g = New-Object System.Windows.Forms.TableLayoutPanel; $g.Dock = 'Fill'; $g.ColumnCount = 1; $g.AutoSize = $true
    $g.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
    $intro = New-CPLabel 'A newer version of CP Solution Saver is ready. Updating takes a few seconds; your settings, templates and solutions are kept.'
    $intro.MaximumSize = New-Object System.Drawing.Size(560, 0)
    $g.Controls.Add($intro)
    $wl = New-CPLabel "What's new:" $script:CPFontBold; $wl.Margin = New-Object System.Windows.Forms.Padding(3, 10, 3, 2)
    $g.Controls.Add($wl)
    $notes = New-Object System.Windows.Forms.TextBox; $notes.Multiline = $true; $notes.ReadOnly = $true; $notes.ScrollBars = 'Vertical'
    $notes.Font = $script:CPFontSmall; $notes.BackColor = $script:CPBg; $notes.BorderStyle = 'FixedSingle'
    $notes.Width = 560; $notes.Height = 180; $notes.TabStop = $false
    # release notes are markdown: drop the install line, heading marks and bold marks
    $noteLines = @(([string]$Release.Notes) -split '\r?\n' | Where-Object { $_ -notmatch '^\s*\**Install:' } | ForEach-Object { ($_ -replace '^\s*#{1,6}\s*', '') -replace '\*\*', '' -replace '`', '' })
    $txt = (($noteLines -join "`r`n").Trim())
    if ($txt.Length -gt 4000) { $txt = $txt.Substring(0, 4000) + "`r`n..." }
    $notes.Text = $(if ($txt.Trim()) { $txt } else { '(no notes)' })
    $g.Controls.Add($notes)
    $more = New-Object System.Windows.Forms.LinkLabel; $more.Text = 'Open the release page'; $more.AutoSize = $true; $more.Font = $script:CPFontSmall
    $more.Margin = New-Object System.Windows.Forms.Padding(3, 4, 3, 0)
    $pageUrl = $Release.Page
    $more.Add_LinkClicked({ if ($pageUrl) { Start-Process $pageUrl } }.GetNewClosure())
    $g.Controls.Add($more)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $btns.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
    $res = @{ Value = 'later' }
    $up = New-CPButton 'Update now' 120; Set-CPPrimary $up
    $later = New-CPButton 'Later' 90
    $skip = New-CPButton 'Skip this version'
    $btns.Controls.Add($up); $btns.Controls.Add($later); $btns.Controls.Add($skip)
    $up.Add_Click({ $res.Value = 'update'; $f.Close() })
    $later.Add_Click({ $res.Value = 'later'; $f.Close() })
    $skip.Add_Click({ $res.Value = 'skip'; $f.Close() })
    $g.Controls.Add($btns)
    $f.Controls.Add($g); $f.Controls.Add($hdr.Panel)
    $f.AcceptButton = $up; $f.CancelButton = $later
    $f.Add_Shown({ Show-CPForeground $f; $up.Focus() })
    [void]$f.ShowDialog(); $f.Dispose()
    return $res.Value
}

function Start-CPUpdateInstaller {
    <# Starts the downloaded installer (setup window in update mode). It stops this app, updates it
       and starts it again. The test variables (CPSAVER_*) are not passed on. #>
    param([Parameter(Mandatory)][string]$InstallerPath)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi = New-Object System.Diagnostics.ProcessStartInfo($ps, "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$InstallerPath`" -Gui -Update")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = Split-Path $InstallerPath -Parent
    foreach ($k in @('CPSAVER_INSTANCE', 'CPSAVER_DATA_DIR', 'CPSAVER_CONFIG', 'CPSAVER_CURRENT_VERSION')) {
        if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) }
    }
    [void][System.Diagnostics.Process]::Start($psi)
}

function New-CPTextBox([switch]$Multiline) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Font = $script:CPFont
    $t.Dock = [System.Windows.Forms.DockStyle]::Fill
    if ($Multiline) { $t.Multiline = $true; $t.ScrollBars = 'Vertical'; $t.Height = 52 }
    return $t
}

function Format-CPAgo([datetime]$t) {
    $s = (Get-Date) - $t
    if ($s.TotalSeconds -lt 60) { return "$([int]$s.TotalSeconds) s ago" }
    if ($s.TotalMinutes -lt 60) { return "$([int]$s.TotalMinutes) min ago" }
    if ($s.TotalHours -lt 24)   { return "$([int]$s.TotalHours) h ago" }
    return $t.ToString('yyyy-MM-dd HH:mm')
}

# ============================================================================
#  Topic picker
# ============================================================================
function Show-CPTopicPicker {
    param([string[]]$Selected, [string]$RepoPath)
    $known = New-Object System.Collections.Generic.List[string]
    foreach ($t in $script:CPCommonTopics) { $known.Add($t) }
    if ($RepoPath -and (Test-Path -LiteralPath $RepoPath)) {
        try { foreach ($s in (Get-CPAllSolutions $RepoPath)) { foreach ($t in @($s.Topics)) { $known.Add($t.ToLowerInvariant()) } } } catch { }
    }
    foreach ($t in @($Selected)) { if ($t) { $known.Add($t) } }
    $items = @(Merge-CPTopics @(,$known.ToArray()) | Sort-Object)
    $selLower = @($Selected | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })

    $f = New-CPForm 'Pick topics' 400 560
    $f.StartPosition = 'CenterParent'; $f.MinimizeBox = $false; $f.MaximizeBox = $false
    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'; $layout.ColumnCount = 1; $layout.RowCount = 4; $layout.Padding = New-Object System.Windows.Forms.Padding(8)
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $layout.Controls.Add((New-CPLabel 'Tick the topics this problem uses:'), 0, 0)
    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Dock = 'Fill'; $list.CheckOnClick = $true; $list.Font = $script:CPFont
    foreach ($t in $items) { $i = $list.Items.Add($t); if ($selLower -contains $t.ToLowerInvariant()) { $list.SetItemChecked($i, $true) } }
    $layout.Controls.Add($list, 0, 1)
    $addRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $addRow.AutoSize = $true; $addRow.Dock = 'Fill'
    $newBox = New-Object System.Windows.Forms.TextBox; $newBox.Width = 220; $newBox.Font = $script:CPFont
    $addBtn = New-CPButton 'Add'
    $addBtn.Add_Click({ $x = $newBox.Text.Trim(); if ($x) { $i = $list.Items.Add($x); $list.SetItemChecked($i, $true); $newBox.Text = '' } })
    $addRow.Controls.Add($newBox); $addRow.Controls.Add($addBtn)
    $layout.Controls.Add($addRow, 0, 2)
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel
    $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'
    $ok = New-CPButton 'OK' 80; $ok.DialogResult = 'OK'; Set-CPPrimary $ok
    $cancel = New-CPButton 'Cancel' 80; $cancel.DialogResult = 'Cancel'
    $btns.Controls.Add($cancel); $btns.Controls.Add($ok)
    $layout.Controls.Add($btns, 0, 3)
    $f.Controls.Add($layout); $f.AcceptButton = $ok; $f.CancelButton = $cancel
    if ($f.ShowDialog() -ne 'OK') { return $null }
    return ,@($list.CheckedItems | ForEach-Object { [string]$_ })
}

# ============================================================================
#  Settings dialog
# ============================================================================
function Get-CPLauncherPath { Join-Path $script:CPGuiDir 'CPSaverLauncher.exe' }
function Get-CPStartupShortcut { Join-Path ([Environment]::GetFolderPath('Startup')) 'CP Solution Saver.lnk' }
function Test-CPStartWithWindows { return (Test-Path -LiteralPath (Get-CPStartupShortcut)) }
function Set-CPStartWithWindows([bool]$Enabled) {
    $lnk = Get-CPStartupShortcut
    if (-not $Enabled) { if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }; return }
    $exe = Get-CPLauncherPath
    if (-not (Test-Path -LiteralPath $exe)) { return }
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $exe; $s.Arguments = 'tray'; $s.WorkingDirectory = $script:CPGuiDir
    $s.IconLocation = (Join-Path $script:CPGuiDir 'app.ico'); $s.Description = 'CP Solution Saver (tray)'
    $s.Save()
}

function Show-CPSettingsDialog {
    <# Returns $true if saved. Edits $Config in place. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$ConfigPath, [string]$Intro)

    $f = New-CPForm 'CP Solution Saver - Settings' 820 760 700 640
    $hdr = New-CPHeader 'Settings' "CP Solution Saver $(Get-CPAppVersion)"

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.ColumnCount = 3; $grid.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10); $grid.AutoScroll = $true
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $row = 0

    if ($Intro) {
        $il = New-CPLabel $Intro; $il.MaximumSize = New-Object System.Drawing.Size(700, 0); $il.ForeColor = $script:CPOrange
        $grid.Controls.Add($il, 0, $row); $grid.SetColumnSpan($il, 3); $row++
    }

    # practice files (one per language)
    $grid.Controls.Add((New-CPLabel 'Practice files:'), 0, $row)
    $pfList = New-Object System.Windows.Forms.ListBox
    $pfList.Dock = 'Fill'; $pfList.Font = $script:CPFont; $pfList.Height = 72; $pfList.HorizontalScrollbar = $true
    foreach ($p in @($Config.PracticeFiles)) { if ($p) { [void]$pfList.Items.Add($p) } }
    if ($pfList.Items.Count -eq 0 -and $Config.MainCppPath) { [void]$pfList.Items.Add($Config.MainCppPath) }
    $grid.Controls.Add($pfList, 1, $row)
    $pfBtns = New-Object System.Windows.Forms.FlowLayoutPanel; $pfBtns.AutoSize = $true; $pfBtns.FlowDirection = 'TopDown'
    $pfAdd = New-CPButton 'Add...'; $pfRemove = New-CPButton 'Remove'
    $pfBtns.Controls.Add($pfAdd); $pfBtns.Controls.Add($pfRemove)
    $grid.Controls.Add($pfBtns, 2, $row); $row++
    $pfHint = New-CPLabel 'The file you write solutions in, one per language (e.g. main.cpp, main.c, main.py). The one you saved last is used.'
    $pfHint.ForeColor = [System.Drawing.Color]::Gray; $pfHint.MaximumSize = New-Object System.Drawing.Size(560, 0); $pfHint.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 6)
    $grid.Controls.Add($pfHint, 1, $row); $grid.SetColumnSpan($pfHint, 2); $row++
    $pfAdd.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'Source files (*.cpp;*.c;*.py;*.java;*.cc)|*.cpp;*.c;*.py;*.java;*.cc|All files (*.*)|*.*'
        $d.Title = 'Select a file you practice in (main.cpp, main.c, main.py ...)'
        if ($pfList.Items.Count) { $d.InitialDirectory = Split-Path ([string]$pfList.Items[$pfList.Items.Count - 1]) -Parent }
        if ($d.ShowDialog() -eq 'OK') {
            $newLang = (Get-CPLanguage $d.FileName).Name
            foreach ($existing in @($pfList.Items)) {
                if ((Get-CPLanguage ([string]$existing)).Name -eq $newLang -and ([string]$existing) -ine $d.FileName) {
                    $a = [System.Windows.Forms.MessageBox]::Show("You already have a $newLang practice file:`n$existing`n`nReplace it with:`n$($d.FileName)?", 'Practice files', 'YesNo', 'Question')
                    if ($a -ne 'Yes') { return }
                    $pfList.Items.Remove($existing)
                }
            }
            if (-not (@($pfList.Items) | Where-Object { ([string]$_) -ieq $d.FileName })) { [void]$pfList.Items.Add($d.FileName) }
        }
    })
    $pfRemove.Add_Click({ if ($pfList.SelectedIndex -ge 0) { $pfList.Items.RemoveAt($pfList.SelectedIndex) } })

    # repo folder
    $grid.Controls.Add((New-CPLabel 'Solutions repo folder:'), 0, $row)
    $repoBox = New-CPTextBox; $repoBox.Text = $Config.RepoPath
    $grid.Controls.Add($repoBox, 1, $row)
    $repoBrowse = New-CPButton 'Browse...'
    $repoBrowse.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Choose a folder for your solutions. An empty folder becomes a new repo (use "Make New Folder"); or pick your existing solutions repo.'
        $d.ShowNewFolderButton = $true
        if ($repoBox.Text -and (Test-Path -LiteralPath $repoBox.Text)) { $d.SelectedPath = $repoBox.Text }
        if ($d.ShowDialog() -eq 'OK') {
            Invoke-CPSafe -What 'Preparing the folder' { $use = Use-CPRepoFolder $d.SelectedPath; if ($use) { $repoBox.Text = $use } }
        }
    })
    $grid.Controls.Add($repoBrowse, 2, $row); $row++

    $repoBtns = New-Object System.Windows.Forms.FlowLayoutPanel
    $repoBtns.AutoSize = $true; $repoBtns.Dock = 'Fill'; $repoBtns.WrapContents = $true
    $cloneBtn = New-CPButton 'Clone a GitHub repo...'
    $createBtn = New-CPButton 'Create a new GitHub repo...'
    $connectBtn = New-CPButton 'Connect this folder to GitHub...'
    $repoBtns.Controls.Add($cloneBtn); $repoBtns.Controls.Add($createBtn); $repoBtns.Controls.Add($connectBtn)
    $repoHint = New-CPLabel 'GitHub is optional: an empty folder works on this PC alone. Connect it to GitHub any time to upload everything saved so far.'
    $repoHint.ForeColor = [System.Drawing.Color]::Gray; $repoHint.MaximumSize = New-Object System.Drawing.Size(560, 0); $repoHint.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 6)
    $grid.Controls.Add($repoBtns, 1, $row); $grid.SetColumnSpan($repoBtns, 2); $row++
    $grid.Controls.Add($repoHint, 1, $row); $grid.SetColumnSpan($repoHint, 2); $row++

    $cloneInto = {
        param([string]$Url)
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Choose where to put the repo folder (e.g. Desktop)'
        $d.SelectedPath = [Environment]::GetFolderPath('Desktop')
        if ($d.ShowDialog() -ne 'OK') { return }
        $name = [IO.Path]::GetFileNameWithoutExtension(($Url.TrimEnd('/') -split '/')[-1])
        $target = Join-Path $d.SelectedPath $name
        if (Test-Path -LiteralPath (Join-Path $target '.git')) { $repoBox.Text = $target; return }
        $f.Cursor = 'WaitCursor'
        $r = Invoke-CPGit $d.SelectedPath clone $Url $target
        $f.Cursor = 'Default'
        if ($r.Code -ne 0) { throw "git clone failed:`n$($r.Output)" }
        $repoBox.Text = $target
        [System.Windows.Forms.MessageBox]::Show("Cloned into:`n$target", 'CP Solution Saver') | Out-Null
    }
    $cloneBtn.Add_Click({
        Invoke-CPSafe -What 'Clone' {
            $url = [Microsoft.VisualBasic.Interaction]::InputBox('GitHub repo URL to clone (e.g. https://github.com/you/Problem-Solving-Solutions):', 'Clone repo', 'https://github.com/')
            if ($url -and $url -ne 'https://github.com/') { & $cloneInto $url.Trim() }
        }
    })
    $createBtn.Add_Click({
        Invoke-CPSafe -What 'Create repo' {
            $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name for the new GitHub repo:', 'Create repo', 'Problem-Solving-Solutions')
            if (-not $name) { return }
            $priv = [System.Windows.Forms.MessageBox]::Show('Make the repo private?  (No = public, visible on your profile)', 'Create repo', 'YesNo', 'Question')
            $f.Cursor = 'WaitCursor'
            $url = New-CPGitHubRepo -Name $name.Trim() -Description 'My accepted competitive programming solutions' -Private:($priv -eq 'Yes')
            $f.Cursor = 'Default'
            & $cloneInto $url
        }
    })

    $connectBtn.Add_Click({
        Invoke-CPSafe -What 'Connect to GitHub' {
            $path = $repoBox.Text.Trim('"', ' ')
            if (-not $path) { [System.Windows.Forms.MessageBox]::Show('Choose your solutions folder first.', 'Connect to GitHub') | Out-Null; return }
            $path = Use-CPRepoFolder $path; if (-not $path) { return }
            $repoBox.Text = $path
            $cur = (Invoke-CPGit $path remote get-url origin)
            if ($cur.Code -eq 0) {
                $a = [System.Windows.Forms.MessageBox]::Show("This folder is already connected to:`n$($cur.Output)`n`nConnect it to a different GitHub repo?", 'Connect to GitHub', 'YesNo', 'Question')
                if ($a -ne 'Yes') { return }
            }
            $how = [System.Windows.Forms.MessageBox]::Show("Create a new repo on your GitHub account for these solutions?`n`nYes  -  create a new repo (you'll sign in to GitHub if needed)`nNo   -  I already made an EMPTY repo on github.com and will paste its link", 'Connect to GitHub', 'YesNoCancel', 'Question')
            if ($how -eq 'Cancel') { return }
            if ($how -eq 'Yes') {
                $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name for the new GitHub repo:', 'Connect to GitHub', (Split-Path $path -Leaf))
                if (-not $name) { return }
                $priv = [System.Windows.Forms.MessageBox]::Show('Make the repo private?  (No = public, visible on your profile)', 'Connect to GitHub', 'YesNo', 'Question')
                $f.Cursor = 'WaitCursor'
                try { $url = New-CPGitHubRepo -Name $name.Trim() -Description 'My accepted competitive programming solutions' -Private:($priv -eq 'Yes') -Empty } finally { $f.Cursor = 'Default' }
            } else {
                $url = [Microsoft.VisualBasic.Interaction]::InputBox('Link of your empty GitHub repo:', 'Connect to GitHub', 'https://github.com/')
                if (-not $url -or $url -eq 'https://github.com/') { return }
            }
            $f.Cursor = 'WaitCursor'
            try { $up = Connect-CPGitHub -RepoPath $path -Url $url } finally { $f.Cursor = 'Default' }
            $cPush.Checked = $true
            $msg = if ($up) { "Connected and uploaded your saved solutions to:`n$url" } else { "Connected to:`n$url`n`nYour next save will upload there." }
            [System.Windows.Forms.MessageBox]::Show($msg, 'Connect to GitHub', 'OK', 'Information') | Out-Null
        }
    })

    # templates
    $grid.Controls.Add((New-CPLabel 'Code templates:'), 0, $row)
    $tplLabel = New-CPLabel 'Choose the template used by "Reset after saving", per language, or load one now.'
    $tplLabel.ForeColor = [System.Drawing.Color]::DimGray; $tplLabel.MaximumSize = New-Object System.Drawing.Size(520, 0)
    $grid.Controls.Add($tplLabel, 1, $row)
    $tplBtns = New-Object System.Windows.Forms.FlowLayoutPanel; $tplBtns.AutoSize = $true
    $tplEdit = New-CPButton 'Templates...'
    $tplEdit.Add_Click({ Invoke-CPSafe -What 'Templates' { Show-CPTemplatePicker -Config $Config -ConfigPath $ConfigPath | Out-Null } })
    $tplBtns.Controls.Add($tplEdit)
    $grid.Controls.Add($tplBtns, 2, $row); $row++

    # options
    $opts = New-Object System.Windows.Forms.FlowLayoutPanel
    $opts.FlowDirection = 'TopDown'; $opts.AutoSize = $true; $opts.Dock = 'Fill'; $opts.Margin = New-Object System.Windows.Forms.Padding(3, 10, 3, 3)
    $mk = { param($text, $val) $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $text; $c.AutoSize = $true; $c.Checked = [bool]$val; $c.Font = $script:CPFont; $opts.Controls.Add($c); $c }
    $cFetch = & $mk 'Look up problem name, difficulty and topics online (Codeforces, LeetCode, AtCoder, CSES)' $Config.AutoFetch
    $cPush  = & $mk 'Push to GitHub after saving' $Config.PushAfterSave
    $cReset = & $mk 'Reset the practice file to its template after a successful save (recommended)' $Config.ResetAfterSave
    $cIdx   = & $mk 'Update README progress and topic / difficulty indexes' $Config.UpdateIndexes
    $cClose = & $mk 'Close the save window after a successful save' $Config.CloseAfterSave
    $cDlg   = & $mk 'Quick save (Ctrl+Alt+Shift+F): show a Windows notification instead of the result window' ($Config.QuickSaveNotify -eq 'notification')
    $cStart = & $mk 'Start with Windows (keeps the shortcuts instant; runs quietly in the tray)' (Test-CPStartWithWindows)
    $cUpd   = & $mk 'Check for new versions automatically (asks before updating)' $Config.AutoUpdateCheck
    if (-not (Test-Path -LiteralPath (Get-CPLauncherPath))) { $cStart.Enabled = $false }
    $grid.Controls.Add($opts, 0, $row); $grid.SetColumnSpan($opts, 3); $row++

    # level cut-offs for numeric ratings
    $lvRow = New-Object System.Windows.Forms.FlowLayoutPanel; $lvRow.AutoSize = $true; $lvRow.WrapContents = $false; $lvRow.Margin = New-Object System.Windows.Forms.Padding(3, 4, 3, 3)
    $mkNum = { param($v) $n = New-Object System.Windows.Forms.NumericUpDown; $n.Minimum = 100; $n.Maximum = 4000; $n.Increment = 100; $n.Width = 70; $n.Font = $script:CPFont; $n.Value = [Math]::Max(100, [Math]::Min(4000, [int]$v)); $n }
    $nMed = & $mkNum $Config.LevelMediumFrom; $nHard = & $mkNum $Config.LevelHardFrom
    $lvRow.Controls.Add((New-CPLabel 'Level from a numeric rating:  Medium from'))
    $lvRow.Controls.Add($nMed); $lvRow.Controls.Add((New-CPLabel '  Hard from')); $lvRow.Controls.Add($nHard)
    $lvHint = New-CPLabel '  (below Medium = Easy)'; $lvHint.ForeColor = [System.Drawing.Color]::Gray; $lvRow.Controls.Add($lvHint)
    $grid.Controls.Add($lvRow, 0, $row); $grid.SetColumnSpan($lvRow, 3); $row++

    $upg = New-CPButton 'Add Difficulty/Topics fields to my practice files'' headers'
    $upg.Add_Click({
        Invoke-CPSafe -What 'Updating the headers' {
            $done = @()
            foreach ($p in @($pfList.Items)) { if (Test-Path -LiteralPath ([string]$p)) { if (Add-CPHeaderFields ([string]$p)) { $done += [IO.Path]::GetFileName([string]$p) } } }
            $msg = if ($done.Count) { "Added the missing header fields to: $($done -join ', ').`nYour code was not changed." } else { 'The headers already have all fields.' }
            [System.Windows.Forms.MessageBox]::Show($msg, 'CP Solution Saver') | Out-Null
        }
    })
    $grid.Controls.Add($upg, 0, $row); $grid.SetColumnSpan($upg, 3); $row++

    # bottom buttons
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel
    # pinned to the bottom of the window (outside the scrolling area), so Save is always visible
    $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $false; $btns.Dock = 'Bottom'; $btns.Height = 52
    $btns.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8); $btns.BackColor = [System.Drawing.Color]::White
    $ok = New-CPButton 'Save' 100; Set-CPPrimary $ok
    $cancel = New-CPButton 'Cancel' 90; $cancel.DialogResult = 'Cancel'
    $btns.Controls.Add($cancel); $btns.Controls.Add($ok)
    $grid.RowCount = $row

    $ok.Add_Click({
        $Config.PracticeFiles = @($pfList.Items | ForEach-Object { ([string]$_).Trim('"', ' ') })
        $active = Get-CPActivePracticeFile $Config
        $Config.MainCppPath = $(if ($active) { $active } elseif ($Config.PracticeFiles.Count) { $Config.PracticeFiles[0] } else { '' })
        $Config.RepoPath = $repoBox.Text.Trim('"', ' ')
        $Config.AutoFetch = $cFetch.Checked; $Config.PushAfterSave = $cPush.Checked
        $Config.ResetAfterSave = $cReset.Checked; $Config.UpdateIndexes = $cIdx.Checked
        $Config.QuickSaveNotify = $(if ($cDlg.Checked) { 'notification' } else { 'dialog' })
        $Config.CloseAfterSave = $cClose.Checked
        $Config.AutoUpdateCheck = $cUpd.Checked
        $Config.LevelMediumFrom = [int]$nMed.Value; $Config.LevelHardFrom = [int][Math]::Max($nHard.Value, $nMed.Value + 100)
        Set-CPLevelCutoffs $Config
        if ($cStart.Enabled) { try { Set-CPStartWithWindows $cStart.Checked } catch { } }
        if ($Config.RepoPath -and (Test-CPRepoFolder $Config.RepoPath) -ne 'repo') {
            try { $use = Use-CPRepoFolder $Config.RepoPath; if ($use) { $Config.RepoPath = $use; $repoBox.Text = $use } } catch { }
        }
        if ((Test-CPRepoFolder $Config.RepoPath) -eq 'repo') { [void](Confirm-CPGitIdentity $Config.RepoPath) }
        $problems = @(Test-CPConfig $Config)
        if ($problems.Count) {
            $a = [System.Windows.Forms.MessageBox]::Show(($problems -join "`n") + "`n`nSave anyway?", 'Settings', 'YesNo', 'Warning')
            if ($a -ne 'Yes') { return }
        }
        Save-CPConfig -Config $Config -Path $ConfigPath
        $f.DialogResult = 'OK'
        $f.Close()
    })

    $f.Controls.Add($grid); $f.Controls.Add($btns); $f.Controls.Add($hdr.Panel); $f.CancelButton = $cancel
    $f.Add_Shown({ Show-CPForeground $f })
    return ($f.ShowDialog() -eq 'OK')
}

# ============================================================================
#  Main window
# ============================================================================
function Show-CPMainWindow {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$ConfigPath)

    if (@(Test-CPConfig $Config).Count) {
        $ok = Show-CPSettingsDialog -Config $Config -ConfigPath $ConfigPath -Intro 'First, tell CP Solution Saver where your practice main.cpp and your solutions repo are.'
        if (-not $ok -or @(Test-CPConfig $Config).Count) { return }
    }

    $ui = @{}
    $st = @{ Info = $null; LoadedMtime = [datetime]::MinValue; Existing = $null; Busy = $false; FillingFiles = $false; Fetching = $false; Queue = $null; CloseAt = $null }

    $f = New-CPForm "CP Solution Saver $(Get-CPAppVersion)" 880 800 720 660
    $script:CPActiveForm = $f
    $hdr = New-CPHeader 'Save an accepted solution' 'Ctrl+S save & push   |   F5 reload   |   Esc close'
    $ui.Stats = $hdr.Right

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.ColumnCount = 3; $grid.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $row = 0

    # practice file (most recently saved one is picked) + status line
    $grid.Controls.Add((New-CPLabel 'Practice file:'), 0, $row)
    $ui.File = New-Object System.Windows.Forms.ComboBox
    $ui.File.DropDownStyle = 'DropDownList'; $ui.File.Font = $script:CPFont; $ui.File.Dock = 'Fill'
    $grid.Controls.Add($ui.File, 1, $row)
    $ui.Reload = New-CPButton 'Reload (F5)'
    $grid.Controls.Add($ui.Reload, 2, $row); $row++
    $ui.Source = New-CPLabel ''; $ui.Source.ForeColor = $script:CPMuted; $ui.Source.Font = $script:CPFontSmall
    $ui.Source.MaximumSize = New-Object System.Drawing.Size(700, 0); $ui.Source.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 4)
    $grid.Controls.Add($ui.Source, 1, $row); $grid.SetColumnSpan($ui.Source, 2); $row++

    # fields
    $grid.Controls.Add((New-CPLabel 'Problem name:'), 0, $row)
    $ui.Name = New-CPTextBox; $grid.Controls.Add($ui.Name, 1, $row); $grid.SetColumnSpan($ui.Name, 2); $row++

    $grid.Controls.Add((New-CPLabel 'Problem link: *'), 0, $row)
    $ui.Link = New-CPTextBox; $grid.Controls.Add($ui.Link, 1, $row)
    $ui.Fetch = New-CPButton 'Look up online'; $grid.Controls.Add($ui.Fetch, 2, $row); $row++

    $grid.Controls.Add((New-CPLabel 'Platform:'), 0, $row)
    $pp = New-Object System.Windows.Forms.TableLayoutPanel; $pp.Dock = 'Fill'; $pp.ColumnCount = 3; $pp.AutoSize = $true; $pp.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$pp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$pp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$pp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $ui.Platform = New-Object System.Windows.Forms.ComboBox; $ui.Platform.Dock = 'Fill'; $ui.Platform.Font = $script:CPFont
    foreach ($p in (Get-CPKnownPlatforms)) { [void]$ui.Platform.Items.Add($p) }
    $ui.Id = New-CPTextBox
    $pp.Controls.Add($ui.Platform, 0, 0); $pp.Controls.Add((New-CPLabel '  Problem ID:'), 1, 0); $pp.Controls.Add($ui.Id, 2, 0)
    $grid.Controls.Add($pp, 1, $row); $grid.SetColumnSpan($pp, 2); $row++

    $grid.Controls.Add((New-CPLabel 'Difficulty:'), 0, $row)
    $ui.Difficulty = New-Object System.Windows.Forms.ComboBox; $ui.Difficulty.Font = $script:CPFont; $ui.Difficulty.Width = 160
    $ui.Difficulty.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    foreach ($d in @('Easy', 'Medium', 'Hard')) { [void]$ui.Difficulty.Items.Add($d) }
    for ($r = 800; $r -le 3500; $r += 100) { [void]$ui.Difficulty.Items.Add([string]$r) }
    $diffRow = New-Object System.Windows.Forms.FlowLayoutPanel; $diffRow.AutoSize = $true; $diffRow.Margin = New-Object System.Windows.Forms.Padding(0)
    $diffRow.Controls.Add($ui.Difficulty)
    $diffRow.Controls.Add((New-CPLabel '   Level:'))
    $ui.Level = New-Object System.Windows.Forms.ComboBox; $ui.Level.DropDownStyle = 'DropDownList'; $ui.Level.Font = $script:CPFont; $ui.Level.Width = 90
    foreach ($l in @('Auto', 'Easy', 'Medium', 'Hard')) { [void]$ui.Level.Items.Add($l) }
    $ui.Level.SelectedIndex = 0
    $diffRow.Controls.Add($ui.Level)
    $ui.LevelAuto = New-CPLabel ''; $ui.LevelAuto.ForeColor = [System.Drawing.Color]::Gray
    $diffRow.Controls.Add($ui.LevelAuto)
    $ui.Star = New-Object System.Windows.Forms.CheckBox; $ui.Star.Text = ([string][char]0x2605 + ' Star this problem'); $ui.Star.AutoSize = $true
    $ui.Star.Margin = New-Object System.Windows.Forms.Padding(18, 6, 3, 3)
    $diffRow.Controls.Add($ui.Star)
    $grid.Controls.Add($diffRow, 1, $row); $grid.SetColumnSpan($diffRow, 2); $row++

    $grid.Controls.Add((New-CPLabel 'Topics:'), 0, $row)
    $ui.Topics = New-CPTextBox; $grid.Controls.Add($ui.Topics, 1, $row)
    $ui.PickTopics = New-CPButton 'Pick...'; $grid.Controls.Add($ui.PickTopics, 2, $row); $row++

    $grid.Controls.Add((New-CPLabel 'Notes:'), 0, $row)
    $ui.Notes = New-CPTextBox -Multiline; $grid.Controls.Add($ui.Notes, 1, $row); $grid.SetColumnSpan($ui.Notes, 2); $row++

    # target
    $grid.Controls.Add((New-CPLabel 'Will be saved as:'), 0, $row)
    $ui.Target = New-CPLabel '' $script:CPFontBold
    $grid.Controls.Add($ui.Target, 1, $row); $grid.SetColumnSpan($ui.Target, 2); $row++
    $ui.KeepBoth = New-Object System.Windows.Forms.CheckBox
    $ui.KeepBoth.Text = 'Keep the old solution too (save this one as a new version)'; $ui.KeepBoth.AutoSize = $true; $ui.KeepBoth.Visible = $false
    $grid.Controls.Add($ui.KeepBoth, 1, $row); $grid.SetColumnSpan($ui.KeepBoth, 2); $row++

    # options
    $opts = New-Object System.Windows.Forms.FlowLayoutPanel; $opts.AutoSize = $true; $opts.Dock = 'Fill'
    $mk = { param($t, $v) $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $t; $c.Checked = [bool]$v; $c.AutoSize = $true; $c.Margin = New-Object System.Windows.Forms.Padding(3, 6, 18, 3); $opts.Controls.Add($c); $c }
    $ui.OptPush  = & $mk 'Push to GitHub' $Config.PushAfterSave
    $ui.OptIdx   = & $mk 'Update README && indexes' $Config.UpdateIndexes
    $ui.OptReset = & $mk 'Reset to template after saving' $Config.ResetAfterSave
    $ui.OptClose = & $mk 'Close this window after saving' $Config.CloseAfterSave
    $grid.Controls.Add($opts, 0, $row); $grid.SetColumnSpan($opts, 3); $row++

    # buttons
    # two rows: the main actions, then the less frequent ones
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.AutoSize = $true; $btns.Dock = 'Fill'; $btns.WrapContents = $false
    $btns2 = New-Object System.Windows.Forms.FlowLayoutPanel; $btns2.AutoSize = $true; $btns2.Dock = 'Fill'; $btns2.WrapContents = $false
    $ui.Save = New-CPButton 'Save && Push   (Ctrl+S)' 200
    Set-CPPrimary $ui.Save; $ui.Save.Padding = New-Object System.Windows.Forms.Padding(14, 7, 14, 7)
    $ui.Rebuild = New-CPButton 'Rebuild index'
    $ui.OpenFolder = New-CPButton 'Open repo folder'
    $ui.OpenWeb = New-CPButton 'Open on GitHub'
    $ui.Settings = New-CPButton 'Settings'
    $ui.Browse = New-CPButton 'Solved problems...'
    $ui.Templates = New-CPButton 'Templates...'
    $ui.Help = New-CPButton 'How to use'
    $ui.Report = New-CPButton 'Report'
    foreach ($b in @($ui.Save, $ui.Browse, $ui.Templates, $ui.Settings)) { $btns.Controls.Add($b) }
    foreach ($b in @($ui.Report, $ui.OpenFolder, $ui.OpenWeb, $ui.Rebuild, $ui.Help)) { $b.Font = $script:CPFontSmall; $btns2.Controls.Add($b) }
    $grid.Controls.Add($btns, 0, $row); $grid.SetColumnSpan($btns, 3); $row++
    $grid.Controls.Add($btns2, 0, $row); $grid.SetColumnSpan($btns2, 3); $row++

    $ui.Status = New-CPLabel 'Ready.' $script:CPFontBold
    $grid.Controls.Add($ui.Status, 0, $row); $grid.SetColumnSpan($ui.Status, 3); $row++

    $ui.Log = New-Object System.Windows.Forms.TextBox
    $ui.Log.Multiline = $true; $ui.Log.ReadOnly = $true; $ui.Log.ScrollBars = 'Vertical'; $ui.Log.Font = $script:CPFontMono
    $ui.Log.Dock = 'Fill'; $ui.Log.BackColor = [System.Drawing.Color]::White; $ui.Log.BorderStyle = 'FixedSingle'
    $grid.Controls.Add($ui.Log, 0, $row); $grid.SetColumnSpan($ui.Log, 3)
    $grid.RowCount = $row + 1
    for ($i = 0; $i -lt $row; $i++) { [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $f.Controls.Add($grid)
    $f.Controls.Add($hdr.Panel)

    # ------------------------------------------------------------ behaviour
    $log = { param($m) $ui.Log.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }
    $setStatus = { param($m, $color) $ui.Status.Text = $m; $ui.Status.ForeColor = $color; [System.Windows.Forms.Application]::DoEvents() }

    $topicsFromBox = { @(Merge-CPTopics @(,$ui.Topics.Text)) }
    $updateLevelHint = {
        if ($ui.Level.SelectedIndex -le 0) {
            $lv = Get-CPLevel -Difficulty $ui.Difficulty.Text
            $ui.LevelAuto.Text = $(if ($lv) { "= $lv (from the difficulty)" } else { '(unrated - pick one if you like)' })
        } else { $ui.LevelAuto.Text = '' }
    }
    $ui.Difficulty.Add_TextChanged({ & $updateLevelHint })
    $ui.Level.Add_SelectedIndexChanged({ & $updateLevelHint })
    $ui.Star.Add_Click({ $st.StarTouched = $true })

    $refreshTarget = {
        if (-not $st.Info) { return }
        $st.Info.Name = $ui.Name.Text.Trim(); $st.Info.Platform = $ui.Platform.Text.Trim(); $st.Info.Id = $ui.Id.Text.Trim(); $st.Info.Link = $ui.Link.Text.Trim()
        Update-CPSolutionPath $st.Info
        if (-not $st.Info.Link) { $ui.Target.Text = '(enter the problem link - it is required, it identifies the problem)'; $ui.Target.ForeColor = $script:CPRed; $ui.KeepBoth.Visible = $false; return }
        if (-not $st.Info.RelPath) { $ui.Target.Text = '(enter a problem name)'; $ui.Target.ForeColor = $script:CPRed; $ui.KeepBoth.Visible = $false; return }
        $st.Existing = $null; $before = @()
        try {
            $before = @(Find-CPSolvedBefore -RepoPath $Config.RepoPath -Info $st.Info)
            $st.Existing = Find-CPExistingSolution -RepoPath $Config.RepoPath -Info $st.Info
        } catch { }
        if ($st.Existing) {
            $exItem = $before | Where-Object { $_.RelPath -eq $st.Existing } | Select-Object -First 1
            if (-not $st.StarTouched -and -not $st.Info.StarredSet -and $exItem -and $exItem.Starred) { $ui.Star.Checked = $true }
            $when = $exItem.DateSolved
            $ui.Target.Text = "$($st.Existing)   (solved before$(if ($when) { " on $when" }) - will be updated)"; $ui.Target.ForeColor = $script:CPOrange; $ui.KeepBoth.Visible = $true
        } elseif ($before.Count) {
            $ui.Target.Text = "$($st.Info.RelPath)   (new $($st.Info.Language) file; solved before in $(@($before | ForEach-Object { $_.Language } | Select-Object -Unique) -join ', '))"; $ui.Target.ForeColor = $script:CPGreen; $ui.KeepBoth.Visible = $false
        } else {
            $ui.Target.Text = "$($st.Info.RelPath)   (new - not solved before)"; $ui.Target.ForeColor = $script:CPGreen; $ui.KeepBoth.Visible = $false
        }
    }
    $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 450
    $timer.Add_Tick({ $timer.Stop(); & $refreshTarget })
    $kick = { $timer.Stop(); $timer.Start() }
    foreach ($c in @($ui.Name, $ui.Platform, $ui.Id, $ui.Link)) { $c.Add_TextChanged($kick) }

    $applyMetadata = {
        param($md)
        if (-not $md.Ok) { & $log $md.Message; return }
        if (-not $ui.Name.Text.Trim()) { $ui.Name.Text = $md.Name }
        if (-not $ui.Id.Text.Trim() -and $md.Id) { $ui.Id.Text = $md.Id }
        if (-not $ui.Difficulty.Text.Trim() -and $md.Difficulty) { $ui.Difficulty.Text = $md.Difficulty }
        $ui.Topics.Text = (@(Merge-CPTopics @((& $topicsFromBox), $md.Topics)) -join ', ')
        & $log "$($md.Message)  name: $($md.Name)  difficulty: $($md.Difficulty)  topics: $(@($md.Topics) -join ', ')"
    }

    $doFetch = {
        $link = $ui.Link.Text.Trim()
        if (-not $link) { & $log 'Enter the problem link first.'; return }
        if ($st.Fetching) { return }
        $st.Fetching = $true; $ui.Fetch.Enabled = $false; $ui.Fetch.Text = 'Looking up...'
        & $setStatus 'Looking the problem up online...' $script:CPMuted
        Start-CPJob -Owner $f -Script { param($l) Get-CPProblemMetadata $l } -Arguments @($link) -OnDone {
            param($md, $err)
            $st.Fetching = $false; $ui.Fetch.Enabled = $true; $ui.Fetch.Text = 'Look up online'
            if ($err) { & $log "Online lookup failed: $err" } elseif ($md) { & $applyMetadata $md }
            & $setStatus 'Ready.' $script:CPAccent
            & $refreshTarget
        }
    }

    $loadFile = {
        param([bool]$AllowFetch)
        $path = $Config.MainCppPath
        $code = Read-CPTextFile $path
        $st.LoadedMtime = (Get-Item -LiteralPath $path).LastWriteTime
        $st.Info = New-CPSolutionInfo -Code $code -Extension ([IO.Path]::GetExtension($path))
        $ui.OptReset.Text = "Reset $([IO.Path]::GetFileName($path)) to template after saving"
        $ui.Name.Text = $st.Info.Name; $ui.Link.Text = $st.Info.Link
        $ui.Platform.Text = $st.Info.Platform; $ui.Id.Text = $st.Info.Id
        $ui.Difficulty.Text = $st.Info.Difficulty; $ui.Topics.Text = (@($st.Info.Topics) -join ', ')
        $ui.Level.SelectedIndex = [Math]::Max(0, $ui.Level.Items.IndexOf($(if ($st.Info.LevelSet) { $st.Info.Level } else { 'Auto' })))
        $st.StarTouched = $false; $ui.Star.Checked = [bool]$st.Info.Starred
        & $updateLevelHint
        $ui.Notes.Text = ($st.Info.Notes -replace "\r?\n", "`r`n")
        $lines = @($code -split "`n").Count
        $ui.Source.Text = "$($st.Info.Language), $lines lines, saved $(Format-CPAgo $st.LoadedMtime)"; $ui.Source.ForeColor = [System.Drawing.Color]::DimGray
        & $log "Loaded $path"
        if (-not $st.Info.HasHeader) { & $log "No problem header found at the top of $([IO.Path]::GetFileName($path)) - fill the fields here (or use Settings > Add fields to headers)." }
        & $refreshTarget
        if ($AllowFetch -and $Config.AutoFetch -and $st.Info.Link) { & $doFetch }
    }

    $mtimeTimer = New-Object System.Windows.Forms.Timer; $mtimeTimer.Interval = 3000
    $mtimeTimer.Add_Tick({
        try {
            $m = (Get-Item -LiteralPath $Config.MainCppPath).LastWriteTime
            if ($m -ne $st.LoadedMtime) {
                $ui.Source.Text = "$([IO.Path]::GetFileName($Config.MainCppPath)) changed on disk $(Format-CPAgo $m) - click Reload (F5) to load the new version."
                $ui.Source.ForeColor = $script:CPOrange
            } else {
                $ui.Source.Text = ($ui.Source.Text -replace 'saved .*$', "saved $(Format-CPAgo $m)"); $ui.Source.ForeColor = [System.Drawing.Color]::DimGray
            }
        } catch { }
    })

    $doSave = {
        if ($st.Busy) { return }
        # use the latest code on disk, with the values from the form
        $code = Read-CPTextFile $Config.MainCppPath
        if ((Get-Item -LiteralPath $Config.MainCppPath).LastWriteTime -ne $st.LoadedMtime) { & $log 'Note: the file changed since it was loaded; saving the newest code from disk.' }
        $info = New-CPSolutionInfo -Code $code -Extension ([IO.Path]::GetExtension($Config.MainCppPath))
        $info.Name = $ui.Name.Text.Trim(); $info.Link = $ui.Link.Text.Trim(); $info.Platform = $ui.Platform.Text.Trim()
        $info.Id = $ui.Id.Text.Trim(); $info.Difficulty = $ui.Difficulty.Text.Trim(); $info.Topics = & $topicsFromBox
        $info.Notes = $ui.Notes.Text.Trim()
        if ($ui.Level.SelectedIndex -gt 0) { $info.Level = [string]$ui.Level.SelectedItem; $info.LevelSet = $true }
        else { $info.Level = Get-CPLevel -Difficulty $info.Difficulty; $info.LevelSet = $false }   # worked out here, with your cut-offs
        $info.Starred = $ui.Star.Checked; $info.StarredSet = $true
        if (-not $info.Platform) { $info.Platform = (Get-CPPlatformInfo $info.Link).Platform }
        if (-not $info.Link) { & $setStatus 'Enter the problem link first (required).' $script:CPRed; $ui.Link.Focus(); return }
        if (-not $info.Name) { & $setStatus 'Enter the problem name first.' $script:CPRed; return }
        # remember the option choices
        $Config.PushAfterSave = $ui.OptPush.Checked; $Config.UpdateIndexes = $ui.OptIdx.Checked
        $Config.ResetAfterSave = $ui.OptReset.Checked; $Config.CloseAfterSave = $ui.OptClose.Checked
        try { Save-CPConfig -Config $Config -Path $ConfigPath } catch { }
        if (-not (Confirm-CPGitIdentity $Config.RepoPath)) { & $setStatus 'Git needs your name and email before the first save (one time).' $script:CPRed; return }

        $st.Busy = $true; $ui.Save.Enabled = $false; $ui.Save.Text = 'Saving...'
        $ui.Log.Clear()
        & $setStatus $(if ($ui.OptPush.Checked) { 'Saving and pushing to GitHub...' } else { 'Saving...' }) $script:CPMuted
        $st.Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        Start-CPJob -Owner $f -Arguments @($info, $Config.RepoPath, $ui.OptPush.Checked, $ui.OptIdx.Checked, $ui.KeepBoth.Checked, $st.Queue) -Script {
            param($info, $repo, $push, $idx, $keep, $q)
            $sink = { param($m) $q.Enqueue($m) }.GetNewClosure()
            Save-CPSolution -Info $info -RepoPath $repo -Push:$push -UpdateIndexes:$idx -KeepBoth:$keep -Log $sink
        } -OnDone {
            param($res, $err)
            & $drainLog
            $st.Busy = $false; $ui.Save.Enabled = $true; $ui.Save.Text = 'Save && Push   (Ctrl+S)'
            if ($err -or -not $res) { & $log "ERROR: $err"; & $setStatus 'Something went wrong - see the details below.' $script:CPRed; return }
            if ($res.Success) {
                $file = [IO.Path]::GetFileName($Config.MainCppPath)
                $msg = if ($res.Pushed) { "Done! $($res.RelPath) is on GitHub." } elseif ($res.Commit -and $res.NoRemote) { "Saved $($res.RelPath) on this PC (not connected to GitHub)." } elseif ($res.Commit) { "Saved and committed $($res.RelPath) (not pushed)." } else { 'Already saved - this exact solution is in the repo, nothing new to push.' }
                & $setStatus $msg $script:CPGreen
                if ($ui.OptReset.Checked) {
                    Reset-CPPracticeFile -MainCppPath $Config.MainCppPath -Config $Config
                    & $log "$file reset to its template. (If Visual Studio asks, choose 'Yes' to reload it.)"
                    & $loadFile $false
                    & $setStatus $msg $script:CPGreen
                } else { & $refreshTarget }
                $ui.Stats.Text = Format-CPStats $Config.RepoPath
                if ($ui.OptClose.Checked) { $st.CloseAt = (Get-Date).AddMilliseconds(1400); $ui.Status.Text = "$msg  Closing..." }
            } else {
                & $setStatus 'Something went wrong - see the details below.' $script:CPRed
            }
        }
    }

    $drainLog = {
        if (-not $st.Queue) { return }
        $m = $null
        while ($st.Queue.TryDequeue([ref]$m)) { $ui.Log.AppendText("$m`r`n") }
    }
    $jobTimer = New-Object System.Windows.Forms.Timer; $jobTimer.Interval = 120
    $jobTimer.Add_Tick({
        & $drainLog
        Update-CPJobs
        if ($st.CloseAt -and (Get-Date) -ge $st.CloseAt) { $st.CloseAt = $null; $f.Close() }
    })

    $fillFiles = {
        $st.FillingFiles = $true
        $ui.File.Items.Clear()
        foreach ($p in @($Config.PracticeFiles)) { if ($p) { [void]$ui.File.Items.Add($p) } }
        if ($ui.File.Items.Count -eq 0 -and $Config.MainCppPath) { [void]$ui.File.Items.Add($Config.MainCppPath) }
        $i = -1; for ($k = 0; $k -lt $ui.File.Items.Count; $k++) { if (([string]$ui.File.Items[$k]) -ieq $Config.MainCppPath) { $i = $k } }
        $ui.File.SelectedIndex = $(if ($i -ge 0) { $i } elseif ($ui.File.Items.Count) { 0 } else { -1 })
        $st.FillingFiles = $false
    }
    $ui.File.Add_SelectedIndexChanged({
        if ($st.FillingFiles -or $ui.File.SelectedIndex -lt 0) { return }
        $Config.MainCppPath = [string]$ui.File.SelectedItem
        Invoke-CPSafe -What 'Loading the file' { $ui.Log.Clear(); & $loadFile $true }
    })
    $ui.Templates.Add_Click({
        Invoke-CPSafe -What 'Templates' {
            if (Show-CPTemplatePicker -Config $Config -ConfigPath $ConfigPath -Language ((Get-CPLanguage $Config.MainCppPath).Name)) { $ui.Log.Clear(); & $fillFiles; & $loadFile $false; & $log 'Template loaded (old file backed up).' }
        }
    })
    $ui.Browse.Add_Click({
        Invoke-CPSafe -What 'Solved problems' {
            Show-CPBrowser -Config $Config -OnLoaded { param($p) $ui.Log.Clear(); & $fillFiles; & $loadFile $false; & $log "Loaded $p into $([IO.Path]::GetFileName($Config.MainCppPath)) (old file backed up)." }
        }
    })
    $ui.Save.Add_Click({ Invoke-CPSafe -What 'Saving' $doSave })
    $ui.Help.Add_Click({ Invoke-CPSafe -What 'How to use' { [void](Show-CPWelcome) } })
    $ui.Report.Add_Click({ Invoke-CPSafe -What 'Analytics report' { $f.Cursor = 'WaitCursor'; try { Open-CPReport -Config $Config } finally { $f.Cursor = 'Default' } } })
    $f.Add_FormClosing({ param($s, $e) if ($st.Busy) { $e.Cancel = $true; $ui.Status.Text = 'Please wait - still saving...' } })
    $ui.Fetch.Add_Click({ Invoke-CPSafe -What 'Online lookup' $doFetch })
    $ui.Reload.Add_Click({ Invoke-CPSafe -What 'Reload' { $ui.Log.Clear(); & $loadFile $true } })
    $ui.PickTopics.Add_Click({
        Invoke-CPSafe -What 'Topic picker' {
            $sel = Show-CPTopicPicker -Selected (& $topicsFromBox) -RepoPath $Config.RepoPath
            if ($null -ne $sel) { $ui.Topics.Text = ($sel -join ', ') }
        }
    })
    $ui.Rebuild.Add_Click({
        if ($st.Busy) { return }
        $st.Busy = $true; $ui.Rebuild.Enabled = $false; $ui.Log.Clear()
        & $setStatus 'Rebuilding the indexes...' $script:CPMuted
        Start-CPJob -Owner $f -Arguments @($Config.RepoPath, $ui.OptPush.Checked) -Script {
            param($repo, $push)
            $out = New-Object System.Collections.Generic.List[string]
            $changed = Update-CPIndexes $repo
            Invoke-CPGit $repo (@('add', '--') + $changed) | Out-Null
            if ((Invoke-CPGit $repo diff --cached --quiet).Code -eq 0) { $out.Add('Indexes are already up to date.') }
            else {
                $r = Invoke-CPGit $repo commit -q -m 'Rebuild solution indexes'; $out.Add('Committed: Rebuild solution indexes')
                if ($push -and (Invoke-CPGit $repo remote).Output) { $r = Invoke-CPGit $repo push; $out.Add($(if ($r.Code -eq 0) { 'Pushed.' } else { "Push failed: $($r.Output)" })) }
            }
            ,$out.ToArray()
        } -OnDone {
            param($lines, $err)
            $st.Busy = $false; $ui.Rebuild.Enabled = $true
            if ($err) { & $log "ERROR: $err"; & $setStatus 'Rebuild failed.' $script:CPRed; return }
            foreach ($l in @($lines)) { & $log $l }
            & $setStatus 'Index rebuilt.' $script:CPGreen
            $ui.Stats.Text = Format-CPStats $Config.RepoPath
        }
    })
    $ui.OpenFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($Config.RepoPath)`"" })
    $ui.OpenWeb.Add_Click({
        Invoke-CPSafe -What 'Open on GitHub' {
            $u = Get-CPRepoWebUrl $Config.RepoPath
            if ($u) { Start-Process $u } else { throw 'This solutions folder is not connected to GitHub yet. Open Settings > Connect this folder to GitHub....' }
        }
    })
    $ui.Settings.Add_Click({
        Invoke-CPSafe -What 'Settings' {
            if (Show-CPSettingsDialog -Config $Config -ConfigPath $ConfigPath) {
                $ui.OptPush.Checked = $Config.PushAfterSave; $ui.OptIdx.Checked = $Config.UpdateIndexes; $ui.OptReset.Checked = $Config.ResetAfterSave
                & $fillFiles
                $ui.Log.Clear(); & $loadFile $true
            }
        }
    })
    $f.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'S') { $e.SuppressKeyPress = $true; Invoke-CPSafe -What 'Saving' $doSave }
        elseif ($e.KeyCode -eq 'F5') { Invoke-CPSafe -What 'Reload' { $ui.Log.Clear(); & $loadFile $true } }
        elseif ($e.KeyCode -eq 'Escape') { $f.Close() }
    })
    $f.Add_Shown({
        Show-CPForeground $f
        if (Get-Command Write-CPTrace -ErrorAction SilentlyContinue) { Write-CPTrace 'save window shown' }
        Open-CPPool
        $jobTimer.Start()
        & $fillFiles
        Invoke-CPSafe -What 'Loading the practice file' { & $loadFile $true }
        $ui.Stats.Text = Format-CPStats $Config.RepoPath
        $mtimeTimer.Start()
    })
    $f.Add_FormClosed({ $timer.Stop(); $mtimeTimer.Stop(); $jobTimer.Stop(); $script:CPActiveForm = $null })

    [void]$f.ShowDialog()
    $f.Dispose()
}

# ============================================================================
#  Notifications (used by quick save)
# ============================================================================
function Show-CPTopMessage {
    param([string]$Text, [string]$Title = 'CP Solution Saver', [string]$Buttons = 'OK', [string]$Icon = 'Information')
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.StartPosition = 'CenterScreen'
    $owner.FormBorderStyle = 'None'; $owner.Size = New-Object System.Drawing.Size(1, 1); $owner.Opacity = 0
    $owner.Show(); $owner.Activate()
    try { return [System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, $Buttons, $Icon) }
    finally { $owner.Close(); $owner.Dispose() }
}

function Show-CPNotification {
    <#
      Shows the result of a quick save. Success: a Windows notification
      (or a message box when $Mode = 'dialog'). Errors always use a message box
      and offer to open the full window; returns $true if the user wants that.
    #>
    param([string]$Title, [string[]]$Lines, [switch]$IsError, [string]$Mode = 'notification', [string]$LogFile)
    $text = ($Lines | Where-Object { $_ }) -join "`n"
    if ($IsError) {
        $msg = $text + "`n`nOpen CP Solution Saver to fix it?"
        if ($LogFile) { $msg = $text + "`n`n(Details: $LogFile)`n`nOpen CP Solution Saver to fix it?" }
        return ((Show-CPTopMessage -Text $msg -Title $Title -Buttons 'YesNo' -Icon 'Warning') -eq 'Yes')
    }
    if ($Mode -eq 'dialog') { Show-CPTopMessage -Text $text -Title $Title | Out-Null; return $false }
    try {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ico = Get-CPAppIcon
        $ni.Icon = $(if ($ico) { $ico } else { [System.Drawing.SystemIcons]::Information })
        $ni.Text = 'CP Solution Saver'
        $ni.Visible = $true
        $ni.BalloonTipTitle = $(if ($Title.Length -gt 60) { $Title.Substring(0, 60) } else { $Title })
        $ni.BalloonTipText = $(if ($text.Length -gt 250) { $text.Substring(0, 250) } else { $text })
        $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $ni.ShowBalloonTip(8000)
        $end = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        $ni.Visible = $false; $ni.Dispose()
    } catch {
        Show-CPTopMessage -Text $text -Title $Title | Out-Null
    }
    return $false
}

# ============================================================================
#  Solved problems browser
# ============================================================================
function ConvertTo-CPLikeLiteral([string]$s) {
    # escape a value for a DataView RowFilter LIKE pattern
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            "'" { [void]$sb.Append("''") }
            '[' { [void]$sb.Append('[[]') }
            ']' { [void]$sb.Append('[]]') }
            '*' { [void]$sb.Append('[*]') }
            '%' { [void]$sb.Append('[%]') }
            default { [void]$sb.Append($ch) }
        }
    }
    return $sb.ToString()
}

function Open-CPReport {
    <# Builds the analytics report from the solutions folder and opens it in the default browser. #>
    param([Parameter(Mandatory)]$Config)
    if ((Test-CPRepoFolder $Config.RepoPath) -ne 'repo') { throw 'Choose your solutions folder in Settings first.' }
    Set-CPLevelCutoffs $Config
    $path = Save-CPReport -RepoPath $Config.RepoPath
    Start-Process $path
}

function Show-CPBrowser {
    <#
      Lists every saved solution with search + filters and a code preview.
      "Load into main.cpp" backs main.cpp up, then replaces it.
      -OnLoaded: scriptblock called after a solution was loaded.
    #>
    param([Parameter(Mandatory)]$Config, [scriptblock]$OnLoaded)

    $f = New-CPForm 'CP Solution Saver - Solved problems' 1220 800 900 560
    $hdr = New-CPHeader 'Solved problems' 'Search, filter, preview, and load a solution back   |   Ctrl+F search   |   Enter load'
    $b = @{}

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'; $root.ColumnCount = 1; $root.RowCount = 4; $root.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))


    # filter row
    $flt = New-Object System.Windows.Forms.TableLayoutPanel
    # fixed height + Dock Fill (not AutoSize), so the search box gets all the spare width
    $flt.Dock = 'Fill'; $flt.AutoSize = $false; $flt.Height = 38; $flt.ColumnCount = 13; $flt.RowCount = 1; $flt.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    foreach ($w in @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100)) {
        if ($w) { [void]$flt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $w))) }
        else { [void]$flt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    }
    $mkCombo = { $c = New-Object System.Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.Font = $script:CPFont; $c.Width = 120; $c.DropDownWidth = 200; $c.Anchor = [System.Windows.Forms.AnchorStyles]::Left; $c }
    $b.Search = New-CPTextBox
    $b.Search.Dock = 'None'; $b.Search.Width = 170; $b.Search.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $b.Platform = & $mkCombo; $b.Platform.Width = 110; $b.Topic = & $mkCombo; $b.Topic.Width = 140; $b.Diff = & $mkCombo; $b.Diff.Width = 110; $b.Lang = & $mkCombo; $b.Lang.Width = 85
    $b.StarOnly = New-Object System.Windows.Forms.CheckBox; $b.StarOnly.Text = ([string][char]0x2605 + ' Starred'); $b.StarOnly.AutoSize = $true
    $b.StarOnly.Anchor = [System.Windows.Forms.AnchorStyles]::Left; $b.StarOnly.Margin = New-Object System.Windows.Forms.Padding(8, 3, 3, 3)
    $b.Clear = New-CPButton 'Clear'
    $flt.Controls.Add((New-CPLabel 'Search:'), 0, 0); $flt.Controls.Add($b.Search, 1, 0)
    $flt.Controls.Add((New-CPLabel ' Platform:'), 2, 0); $flt.Controls.Add($b.Platform, 3, 0)
    $flt.Controls.Add((New-CPLabel ' Topic:'), 4, 0); $flt.Controls.Add($b.Topic, 5, 0)
    $flt.Controls.Add((New-CPLabel ' Difficulty:'), 6, 0); $flt.Controls.Add($b.Diff, 7, 0)
    $flt.Controls.Add((New-CPLabel ' Language:'), 8, 0); $flt.Controls.Add($b.Lang, 9, 0)
    $flt.Controls.Add($b.StarOnly, 10, 0)
    $flt.Controls.Add($b.Clear, 11, 0)
    $root.Controls.Add($flt, 0, 1)

    # grid + preview
    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.SplitterWidth = 6
    $b.Grid = New-Object System.Windows.Forms.DataGridView
    $g = $b.Grid
    $g.Dock = 'Fill'; $g.ReadOnly = $true; $g.AllowUserToAddRows = $false; $g.AllowUserToDeleteRows = $false
    $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false; $g.RowHeadersVisible = $false
    $g.AutoSizeColumnsMode = 'Fill'; $g.BackgroundColor = [System.Drawing.Color]::White; $g.BorderStyle = 'FixedSingle'
    $g.EnableHeadersVisualStyles = $false; $g.ColumnHeadersDefaultCellStyle.BackColor = $script:CPBg; $g.ColumnHeadersDefaultCellStyle.ForeColor = $script:CPAccent
    $g.ColumnHeadersBorderStyle = 'Single'; $g.GridColor = [System.Drawing.Color]::FromArgb(234, 238, 242); $g.CellBorderStyle = 'SingleHorizontal'
    $g.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(221, 244, 255); $g.DefaultCellStyle.SelectionForeColor = $script:CPAccent
    $g.RowTemplate.Height = 28; $g.ColumnHeadersHeight = 32; $g.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $g.Font = $script:CPFont; $g.AllowUserToResizeRows = $false
    $g.ColumnHeadersDefaultCellStyle.Font = $script:CPFontBold
    $g.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)
    $split.Panel1.Controls.Add($g)

    $prevPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $prevPanel.Dock = 'Fill'; $prevPanel.ColumnCount = 1; $prevPanel.RowCount = 2
    [void]$prevPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$prevPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $b.PrevTitle = New-CPLabel 'Select a problem to preview its solution.' $script:CPFontBold
    $b.PrevTitle.AutoSize = $false; $b.PrevTitle.Dock = 'Fill'; $b.PrevTitle.AutoEllipsis = $true; $b.PrevTitle.Height = 26
    $b.Preview = New-Object System.Windows.Forms.TextBox
    $b.Preview.Multiline = $true; $b.Preview.ReadOnly = $true; $b.Preview.ScrollBars = 'Both'; $b.Preview.WordWrap = $false
    $b.Preview.Font = New-Object System.Drawing.Font('Consolas', 10); $b.Preview.Dock = 'Fill'; $b.Preview.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $prevPanel.Controls.Add($b.PrevTitle, 0, 0); $prevPanel.Controls.Add($b.Preview, 0, 1)
    $split.Panel2.Controls.Add($prevPanel)
    $root.Controls.Add($split, 0, 2)

    # bottom row
    $bottom = New-Object System.Windows.Forms.TableLayoutPanel
    $bottom.Dock = 'Fill'; $bottom.AutoSize = $true; $bottom.ColumnCount = 2
    [void]$bottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$bottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $b.Status = New-CPLabel ''
    $b.Status.AutoSize = $false; $b.Status.Dock = 'Fill'; $b.Status.AutoEllipsis = $true; $b.Status.TextAlign = 'MiddleLeft'
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.AutoSize = $true; $btns.WrapContents = $false
    $b.Load = New-CPButton 'Load into practice file' 190
    Set-CPPrimary $b.Load
    $b.OpenLink = New-CPButton 'Open problem page'
    $b.OpenFile = New-CPButton 'Open file'
    $b.Backups = New-CPButton 'Backups'
    $b.Refresh = New-CPButton 'Refresh'
    $b.Close = New-CPButton 'Close'
    $b.Star = New-CPButton ([string][char]0x2605 + ' Star') 100
    $b.Report = New-CPButton 'Report'
    foreach ($x in @($b.Load, $b.Star, $b.OpenLink, $b.OpenFile, $b.Report, $b.Backups, $b.Refresh, $b.Close)) { $btns.Controls.Add($x) }
    $bottom.Controls.Add($b.Status, 0, 0); $bottom.Controls.Add($btns, 1, 0)
    $root.Controls.Add($bottom, 0, 3)
    $f.Controls.Add($root)
    $f.Controls.Add($hdr.Panel)

    # ---------------------------------------------------------------- data
    $dt = New-Object System.Data.DataTable
    foreach ($c in @('#', 'Star', 'Name', 'Platform', 'ID', 'Difficulty', 'Level', 'Topics', 'Language', 'Solved', 'Path', 'Link', 'FullPath', 'TopicsKey', 'DiffGroup', 'DiffSort', 'DiffSortDesc', 'NumSort', 'Starred', 'SearchText')) { [void]$dt.Columns.Add($c, [string]) }
    $view = New-Object System.Data.DataView($dt)
    # sort: column + direction, remembered in the settings ("Num DESC" = newest number first)
    $sortParts = ([string]$Config.BrowserSort) -split ' '
    $st = @{ Total = 0; SortCol = $(if ($sortParts[0]) { $sortParts[0] } else { 'Num' }); SortDesc = ($sortParts[1] -ne 'ASC'); Loading = $false; StarBusy = $false }
    $starMark = [string][char]0x2605

    $fillCombo = {
        param($combo, $allText, $items)
        $prev = [string]$combo.SelectedItem
        $combo.Items.Clear(); [void]$combo.Items.Add($allText)
        foreach ($i in $items) { [void]$combo.Items.Add($i) }
        $idx = $combo.Items.IndexOf($prev); $combo.SelectedIndex = $(if ($idx -ge 0) { $idx } else { 0 })
    }

    $loadData = {
        $st.Loading = $true
        $dt.Rows.Clear()
        $all = @()
        try { $all = @(Get-CPAllSolutions $Config.RepoPath) } catch { $b.Status.Text = "Could not read the repo: $($_.Exception.Message)" }
        $plats = @{}; $topics = @{}; $diffs = @{}; $langs = @{}
        Set-CPLevelCutoffs $Config
        foreach ($s in $all) {
            $dg = Get-CPDifficultyGroup $s.Difficulty
            $tl = @($s.Topics | ForEach-Object { $_.ToLowerInvariant() })
            $r = $dt.NewRow()
            $r['#'] = [string]$s.Number; $r['NumSort'] = '{0:D6}' -f [int]$s.Number
            $r['Star'] = $(if ($s.Starred) { $starMark } else { '' }); $r['Starred'] = $(if ($s.Starred) { '1' } else { '0' })
            $r['Name'] = $s.Name; $r['Platform'] = $s.Platform; $r['ID'] = $s.Id; $r['Difficulty'] = $s.Difficulty
            $r['Level'] = $s.Level
            $r['Topics'] = ($tl -join ', '); $r['Language'] = $s.Language; $r['Solved'] = $s.DateSolved; $r['Path'] = $s.RelPath; $r['Link'] = $s.Link
            $r['FullPath'] = $s.FullPath; $r['TopicsKey'] = ',' + ($tl -join ',') + ','
            $r['DiffGroup'] = $dg.Label; $r['DiffSort'] = (Get-CPDifficultySortKey $s.Difficulty $s.Level)
            # for "hardest first": unrated problems still go to the end
            $r['DiffSortDesc'] = $(if ($s.Level) { $r['DiffSort'] } else { '0' + $r['DiffSort'] })
            $r['SearchText'] = (@($s.Name, $s.Id, $s.Platform, $s.RelPath, $s.Notes, ($tl -join ' '), $s.Link, $s.Level, "#$($s.Number)") -join ' ').ToLowerInvariant()
            $dt.Rows.Add($r)
            $plats[$s.Platform] = 1; foreach ($t in $tl) { $topics[$t] = 1 }; if ($dg.Label -ne 'Unrated' -and $dg.Label -notin @('Easy', 'Medium', 'Hard')) { $diffs[$dg.Label] = $dg.SortKey }; $langs[$s.Language] = 1
        }
        $st.Total = $all.Count
        & $fillCombo $b.Platform 'All platforms' @($plats.Keys | Sort-Object)
        & $fillCombo $b.Topic 'All topics' @($topics.Keys | Sort-Object)
        # levels first (across all platforms), then the exact ratings
        & $fillCombo $b.Diff 'All difficulties' @(@('Easy', 'Medium', 'Hard', 'Unrated') + @($diffs.Keys | Sort-Object { $diffs[$_] }))
        & $fillCombo $b.Lang 'All' @($langs.Keys | Sort-Object)
        $st.Loading = $false
        & $applyFilter
    }

    $setGlyph = {
        $glyphCol = if ($st.SortCol -eq 'Num') { '#' } else { $st.SortCol }
        foreach ($c in $g.Columns) { $c.HeaderCell.SortGlyphDirection = $(if ($c.Name -eq $glyphCol) { if ($st.SortDesc) { 'Descending' } else { 'Ascending' } } else { 'None' }) }
    }
    $applyFilter = {
        if ($st.Loading) { return }
        $conds = New-Object System.Collections.Generic.List[string]
        foreach ($term in ($b.Search.Text.ToLowerInvariant() -split '\s+' | Where-Object { $_ })) {
            $conds.Add("SearchText LIKE '%" + (ConvertTo-CPLikeLiteral $term) + "%'")
        }
        if ($b.Platform.SelectedIndex -gt 0) { $conds.Add("Platform = '" + ([string]$b.Platform.SelectedItem -replace "'", "''") + "'") }
        if ($b.Topic.SelectedIndex -gt 0) { $conds.Add("TopicsKey LIKE '%," + (ConvertTo-CPLikeLiteral ([string]$b.Topic.SelectedItem)) + ",%'") }
        if ($b.Diff.SelectedIndex -gt 0) {
            $dsel = [string]$b.Diff.SelectedItem
            if ($dsel -in @('Easy', 'Medium', 'Hard')) { $conds.Add("Level = '$dsel'") }
            elseif ($dsel -eq 'Unrated') { $conds.Add("Level = ''") }
            else { $conds.Add("DiffGroup = '" + ($dsel -replace "'", "''") + "'") }
        }
        if ($b.Lang.SelectedIndex -gt 0) { $conds.Add("Language = '" + ([string]$b.Lang.SelectedItem -replace "'", "''") + "'") }
        if ($b.StarOnly.Checked) { $conds.Add("Starred = '1'") }
        $view.RowFilter = ($conds -join ' AND ')
        $diffKey = if ($st.SortDesc) { 'DiffSortDesc' } else { 'DiffSort' }
        $sortCol = switch ($st.SortCol) { 'Difficulty' { $diffKey } 'Level' { $diffKey } 'Num' { 'NumSort' } '#' { 'NumSort' } 'Star' { 'Starred' } default { "[$($st.SortCol)]" } }
        $view.Sort = "$sortCol $(if ($st.SortDesc) { 'DESC' } else { 'ASC' }), NumSort DESC"
        & $setGlyph
        $b.Status.ForeColor = [System.Drawing.Color]::Black
        $b.Status.Text = if ($st.Total -eq 0) { 'No solutions saved yet. Save one first, then come back here.' } else { "Showing $($view.Count) of $($st.Total) solutions" }
        if ($view.Count -eq 0) { $b.Preview.Text = ''; $b.PrevTitle.Text = 'No match.' }
    }

    $g.DataSource = $view
    $g.Add_DataBindingComplete({
        foreach ($c in @('Link', 'FullPath', 'TopicsKey', 'DiffGroup', 'DiffSort', 'DiffSortDesc', 'NumSort', 'Starred', 'SearchText')) { if ($g.Columns[$c]) { $g.Columns[$c].Visible = $false } }
        $weights = @{ '#' = 5; Star = 3; Name = 24; Platform = 10; ID = 7; Difficulty = 8; Level = 7; Topics = 20; Language = 7; Solved = 9; Path = 20 }
        foreach ($k in $weights.Keys) { if ($g.Columns[$k]) { $g.Columns[$k].FillWeight = $weights[$k]; $g.Columns[$k].SortMode = 'Programmatic' } }
        if ($g.Columns['Star']) { $g.Columns['Star'].HeaderText = $starMark; $g.Columns['Star'].DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(212, 167, 44); $g.Columns['Star'].DefaultCellStyle.Alignment = 'MiddleCenter'; $g.Columns['Star'].ToolTipText = 'Starred (click the star cell or the Star button)' }
        if ($g.Columns['#']) { $g.Columns['#'].DefaultCellStyle.ForeColor = $script:CPMuted; $g.Columns['#'].ToolTipText = 'Problem number: #1 is the first problem you solved' }
        & $setGlyph
    })
    $g.Add_ColumnHeaderMouseClick({
        param($s, $e)
        $name = $g.Columns[$e.ColumnIndex].Name
        if ($name -eq '#') { $name = 'Num' }
        if ($st.SortCol -eq $name) { $st.SortDesc = -not $st.SortDesc } else { $st.SortCol = $name; $st.SortDesc = ($name -in @('Solved', 'Num', 'Star')) }
        & $applyFilter
        $Config.BrowserSort = "$($st.SortCol) $(if ($st.SortDesc) { 'DESC' } else { 'ASC' })"
        try { Save-CPConfig -Config $Config } catch { }
    })

    $current = {
        if ($g.SelectedRows.Count -eq 0) { return $null }
        $drv = $g.SelectedRows[0].DataBoundItem
        if ($null -eq $drv) { return $null }
        return $drv.Row
    }
    $g.Add_SelectionChanged({
        $r = & $current
        if (-not $r) { return }
        $b.PrevTitle.Text = "#$($r['#'])  $($r['Name'])   -   $($r['Path'])"
        $b.Star.Text = $(if ($r['Starred'] -eq '1') { 'Unstar' } else { $starMark + ' Star' })
        try { $b.Preview.Text = ([IO.File]::ReadAllText($r['FullPath']) -replace "(?<!`r)`n", "`r`n") } catch { $b.Preview.Text = "Could not read the file: $($_.Exception.Message)" }
    })

    $doLoad = {
        $r = & $current
        if (-not $r) { $b.Status.Text = 'Select a problem first.'; return }
        $target = Get-CPImportTarget -Config $Config -RelPath $r['Path']
        if (-not $target) { throw "No $($r['Language']) practice file is set up. Add one in Settings > Practice files, then try again." }
        $tn = [IO.Path]::GetFileName($target)
        $q = "Load '$($r['Name'])' into your $($tn)?`n`n$target`n`nThe current $tn is backed up first (button 'Backups' to find it)."
        if ([System.Windows.Forms.MessageBox]::Show($q, 'Load solution', 'YesNo', 'Question') -ne 'Yes') { return }
        $backup = Import-CPSolution -Config $Config -RelPath $r['Path']
        $Config.MainCppPath = $target
        $b.Status.Text = "Loaded $($r['Path']) into $tn (old $tn backed up)."
        $b.Status.ForeColor = $script:CPGreen
        if ($OnLoaded) { & $OnLoaded $r['Path'] }
        [System.Windows.Forms.MessageBox]::Show("Loaded into $tn.`n`nIf your editor asks whether to reload the file, choose Yes.", 'Load solution') | Out-Null
    }

    $doStar = {
        $r = & $current
        if (-not $r) { $b.Status.Text = 'Select a problem first.'; return }
        if ($st.StarBusy) { return }
        $newVal = ($r['Starred'] -ne '1')
        $rel = $r['Path']
        # show it right away; the file edit + commit + push run in the background
        $r['Starred'] = $(if ($newVal) { '1' } else { '0' }); $r['Star'] = $(if ($newVal) { $starMark } else { '' })
        $b.Star.Text = $(if ($newVal) { 'Unstar' } else { $starMark + ' Star' })
        $st.StarBusy = $true; $st.StarRel = $rel
        $b.Status.ForeColor = $script:CPMuted; $b.Status.Text = "$(if ($newVal) { 'Starring' } else { 'Unstarring' }) $($r['Name'])..."
        Start-CPJob -Owner $f -Arguments @($Config.RepoPath, $rel, $newVal, [bool]$Config.PushAfterSave, [bool]$Config.UpdateIndexes, [int]$Config.LevelMediumFrom, [int]$Config.LevelHardFrom) -Script {
            param($repo, $relPath, $val, $push, $idx, $lm, $lh)
            Set-CPLevelCutoffs @{ LevelMediumFrom = $lm; LevelHardFrom = $lh }
            Set-CPStarred -RepoPath $repo -RelPath $relPath -Starred $val -Push:$push -UpdateIndexes:$idx
        } -OnDone {
            param($res, $err)
            $st.StarBusy = $false
            if ($err -or -not $res -or -not $res.Success) {
                $b.Status.ForeColor = $script:CPRed
                $b.Status.Text = "Could not change the star: $(if ($err) { $err } else { $res.Message })"
                & $loadData
                return
            }
            $b.Status.ForeColor = $script:CPGreen
            $b.Status.Text = "Done: $($res.Message)"
            $cr = & $current
            if ($cr -and $cr['Path'] -eq $st.StarRel) { try { $b.Preview.Text = ([IO.File]::ReadAllText($cr['FullPath']) -replace "(?<!`r)`n", "`r`n") } catch { } }
        }
    }
    $b.Star.Add_Click({ Invoke-CPSafe -What 'Star' $doStar })
    $g.Add_CellClick({ param($s, $e) if ($e.RowIndex -ge 0 -and $g.Columns[$e.ColumnIndex].Name -eq 'Star') { Invoke-CPSafe -What 'Star' $doStar } })
    $b.StarOnly.Add_CheckedChanged({ & $applyFilter })
    $b.Report.Add_Click({ Invoke-CPSafe -What 'Analytics report' { $f.Cursor = 'WaitCursor'; try { Open-CPReport -Config $Config } finally { $f.Cursor = 'Default' } } })
    $b.Search.Add_TextChanged({ & $applyFilter })
    foreach ($c in @($b.Platform, $b.Topic, $b.Diff, $b.Lang)) { $c.Add_SelectedIndexChanged({ & $applyFilter }) }
    $b.Clear.Add_Click({ $st.Loading = $true; $b.Search.Text = ''; $b.Platform.SelectedIndex = 0; $b.Topic.SelectedIndex = 0; $b.Diff.SelectedIndex = 0; $b.Lang.SelectedIndex = 0; $b.StarOnly.Checked = $false; $st.Loading = $false; & $applyFilter })
    $b.Load.Add_Click({ Invoke-CPSafe -What 'Loading the solution' $doLoad })
    $g.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { Invoke-CPSafe -What 'Loading the solution' $doLoad } })
    $b.OpenLink.Add_Click({ $r = & $current; if ($r -and $r['Link']) { Start-Process $r['Link'] } else { $b.Status.Text = 'This problem has no link.' } })
    $b.OpenFile.Add_Click({ $r = & $current; if ($r) { Start-Process notepad.exe -ArgumentList "`"$($r['FullPath'])`"" } })
    $b.Backups.Add_Click({ $d = Get-CPBackupDir; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; Start-Process explorer.exe -ArgumentList "`"$d`"" })
    $b.Refresh.Add_Click({ Invoke-CPSafe -What 'Refresh' $loadData })
    $b.Close.Add_Click({ $f.Close() })
    $f.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'F') { $b.Search.Focus(); $e.SuppressKeyPress = $true }
        elseif ($e.KeyCode -eq 'Escape') { $f.Close() }
        elseif ($e.KeyCode -eq 'Enter' -and $g.Focused) { $e.SuppressKeyPress = $true; Invoke-CPSafe -What 'Loading the solution' $doLoad }
    })
    $f.Add_Shown({
        Show-CPForeground $f
        $split.SplitterDistance = [int]($split.Height * 0.52)
        Invoke-CPSafe -What 'Reading solutions' $loadData
        $hdr.Right.Text = Format-CPStats $Config.RepoPath
        $b.Search.Focus()
    })
    # background work (starring) finishes through this timer, also when no tray app is running
    $jobTick = New-Object System.Windows.Forms.Timer; $jobTick.Interval = 150
    $jobTick.Add_Tick({ Update-CPJobs })
    $jobTick.Start()
    [void]$f.ShowDialog()
    $jobTick.Stop(); $jobTick.Dispose()
    $f.Dispose()
}

# ============================================================================
#  Templates
# ============================================================================
function Show-CPTemplatePicker {
    <#
      Lists the code templates per language with a preview.
      "Load into ..." puts a template into the practice file of that language
      (after a backup); "Use for reset after saving" makes it that language's
      default. Returns $true if a template was loaded.
    #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$ConfigPath, [string]$Language)

    $f = New-CPForm 'CP Solution Saver - Code templates' 1000 700 780 520
    $hdr = New-CPHeader 'Code templates' 'Load a template into your practice file, or choose what "reset after saving" uses'
    $t = @{ Loaded = $false; Items = @() }

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'; $root.ColumnCount = 2; $root.RowCount = 4; $root.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 300)))
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    foreach ($rs in @('AutoSize', 'AutoSize', 'Percent', 'AutoSize')) {
        if ($rs -eq 'Percent') { [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) }
        else { [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    }

    $top = New-Object System.Windows.Forms.FlowLayoutPanel; $top.AutoSize = $true; $top.Dock = 'Fill'
    $top.Controls.Add((New-CPLabel 'Language:'))
    $lang = New-Object System.Windows.Forms.ComboBox; $lang.DropDownStyle = 'DropDownList'; $lang.Width = 140; $lang.Font = $script:CPFont
    $top.Controls.Add($lang)
    $openDir = New-CPButton 'Open templates folder'
    $top.Controls.Add($openDir)
    $hint = New-CPLabel '   Add your own: save a file named "C++ - My name.cpp" (or "Python - ....py") in that folder.'
    $hint.ForeColor = [System.Drawing.Color]::Gray
    $top.Controls.Add($hint)
    $root.Controls.Add($top, 0, 1); $root.SetColumnSpan($top, 2)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = 'Fill'; $list.Font = $script:CPFont; $list.IntegralHeight = $false
    $root.Controls.Add($list, 0, 2)
    $preview = New-Object System.Windows.Forms.TextBox
    $preview.Multiline = $true; $preview.ReadOnly = $true; $preview.ScrollBars = 'Both'; $preview.WordWrap = $false
    $preview.Font = New-Object System.Drawing.Font('Consolas', 10); $preview.Dock = 'Fill'; $preview.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $root.Controls.Add($preview, 1, 2)

    $bottom = New-Object System.Windows.Forms.TableLayoutPanel
    $bottom.Dock = 'Fill'; $bottom.AutoSize = $true; $bottom.ColumnCount = 2
    [void]$bottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$bottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $status = New-CPLabel ''; $status.AutoSize = $false; $status.Dock = 'Fill'; $status.AutoEllipsis = $true; $status.TextAlign = 'MiddleLeft'
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.AutoSize = $true; $btns.WrapContents = $false
    $load = New-CPButton 'Load into practice file' 190
    Set-CPPrimary $load
    $useReset = New-CPButton 'Use for "reset after saving"'
    $edit = New-CPButton 'Edit'
    $close = New-CPButton 'Close'
    foreach ($x in @($load, $useReset, $edit, $close)) { $btns.Controls.Add($x) }
    $bottom.Controls.Add($status, 0, 0); $bottom.Controls.Add($btns, 1, 0)
    $root.Controls.Add($bottom, 0, 3); $root.SetColumnSpan($bottom, 2)
    $f.Controls.Add($root)
    $f.Controls.Add($hdr.Panel)

    $defaultName = {
        param($language)
        $p = Get-CPDefaultTemplatePath -Config $Config -Extension (@($t.All | Where-Object { $_.Language -eq $language })[0].Ext)
        if ($p) { return [IO.Path]::GetFileNameWithoutExtension($p) } else { return '' }
    }
    $fillList = {
        $t.All = @(Get-CPTemplates)
        $language = [string]$lang.SelectedItem
        $t.Items = @($t.All | Where-Object { $_.Language -eq $language })
        $def = & $defaultName $language
        $list.Items.Clear()
        foreach ($i in $t.Items) { [void]$list.Items.Add($(if ($i.Name -eq $def) { "$($i.Name)    (used for reset)" } else { $i.Name })) }
        if ($list.Items.Count) { $list.SelectedIndex = 0 }
        $target = Get-CPPracticeFileFor -Config $Config -Extension $(if ($t.Items.Count) { $t.Items[0].Ext } else { '.cpp' })
        $load.Text = $(if ($target) { "Load into $([IO.Path]::GetFileName($target))" } else { "Load (no $language practice file)" })
        $load.Enabled = [bool]$target
        $status.Text = "Reset after saving uses: $def"; $status.ForeColor = [System.Drawing.Color]::Black
    }
    $current = { if ($list.SelectedIndex -ge 0 -and $list.SelectedIndex -lt $t.Items.Count) { return $t.Items[$list.SelectedIndex] } return $null }

    $list.Add_SelectedIndexChanged({
        $c = & $current
        if ($c) { try { $preview.Text = ([IO.File]::ReadAllText($c.Path) -replace "(?<!`r)`n", "`r`n") } catch { $preview.Text = $_.Exception.Message } }
    })
    $lang.Add_SelectedIndexChanged({ & $fillList })
    $openDir.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$(Get-CPTemplateDir)`"" })
    $edit.Add_Click({ $c = & $current; if ($c) { Start-Process notepad.exe -ArgumentList "`"$($c.Path)`"" } })
    $close.Add_Click({ $f.Close() })
    $useReset.Add_Click({
        Invoke-CPSafe -What 'Saving the choice' {
            $c = & $current; if (-not $c) { return }
            if (-not $Config.DefaultTemplates) { $Config.DefaultTemplates = [ordered]@{} }
            $Config.DefaultTemplates[$c.Language] = $c.Name
            Save-CPConfig -Config $Config -Path $ConfigPath
            $sel = $list.SelectedIndex; & $fillList; $list.SelectedIndex = $sel
            $status.Text = "Reset after saving now uses: $($c.Name)"; $status.ForeColor = $script:CPGreen
        }
    })
    $load.Add_Click({
        Invoke-CPSafe -What 'Loading the template' {
            $c = & $current; if (-not $c) { return }
            $target = Get-CPPracticeFileFor -Config $Config -Extension $c.Ext
            if (-not $target) { throw "No $($c.Language) practice file is set up. Add one in Settings > Practice files." }
            $q = "Replace the contents of`n$target`nwith the template '$($c.Name)'?`n`nThe current file is backed up first."
            if ([System.Windows.Forms.MessageBox]::Show($q, 'Load template', 'YesNo', 'Question') -ne 'Yes') { return }
            $keep = 30; if ($Config.BackupsToKeep) { $keep = [int]$Config.BackupsToKeep }
            Backup-CPPracticeFile -Path $target -Keep $keep | Out-Null
            Reset-CPPracticeFile -MainCppPath $target -TemplatePath $c.Path
            $Config.MainCppPath = $target
            $t.Loaded = $true
            $status.Text = "Loaded '$($c.Name)' into $([IO.Path]::GetFileName($target)) (old file backed up). If Visual Studio asks to reload, choose Yes."
            $status.ForeColor = $script:CPGreen
        }
    })
    $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $f.Close() } })
    $f.Add_Shown({
        Show-CPForeground $f
        Invoke-CPSafe -What 'Reading templates' {
            $all = @(Get-CPTemplates)
            $langs = @($all | ForEach-Object { $_.Language } | Select-Object -Unique)
            foreach ($l in $langs) { [void]$lang.Items.Add($l) }
            $want = if ($Language -and ($langs -contains $Language)) { $Language } elseif ($langs -contains 'C++') { 'C++' } else { $langs[0] }
            $lang.SelectedItem = $want
        }
    })
    [void]$f.ShowDialog()
    $f.Dispose()
    return $t.Loaded
}
