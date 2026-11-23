# CPSaver.Gui.ps1 - Windows Forms user interface for CP Solution Saver.
# Dot-sourced by CPSaver.ps1 after CPSaver.Core.psm1 is imported.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:CPFont      = New-Object System.Drawing.Font('Segoe UI', 9.75)
$script:CPFontBold  = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
$script:CPFontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$script:CPFontMono  = New-Object System.Drawing.Font('Consolas', 9)
$script:CPGreen     = [System.Drawing.Color]::FromArgb(0, 128, 0)
$script:CPOrange    = [System.Drawing.Color]::FromArgb(200, 110, 0)
$script:CPRed       = [System.Drawing.Color]::FromArgb(190, 30, 30)
$script:CPAccent    = [System.Drawing.Color]::FromArgb(36, 41, 47)

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
    try { return [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')) } catch { return $null }
}

function New-CPLabel([string]$Text, $Font = $script:CPFont) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $true; $l.Font = $Font
    $l.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $l.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
    return $l
}

function New-CPButton([string]$Text, [int]$Width = 0) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Font = $script:CPFont; $b.AutoSize = $true
    $b.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $b.Padding = New-Object System.Windows.Forms.Padding(8, 3, 8, 3)
    if ($Width) { $b.MinimumSize = New-Object System.Drawing.Size($Width, 0) }
    return $b
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

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Pick topics'; $f.Font = $script:CPFont; $f.StartPosition = 'CenterParent'
    $f.Size = New-Object System.Drawing.Size(380, 520); $f.MinimizeBox = $false; $f.MaximizeBox = $false
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
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
    $ok = New-CPButton 'OK' 80; $ok.DialogResult = 'OK'
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
function Show-CPSettingsDialog {
    <# Returns $true if saved. Edits $Config in place. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$ConfigPath, [string]$Intro)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'CP Solution Saver - Settings'; $f.Font = $script:CPFont; $f.StartPosition = 'CenterScreen'
    $f.Size = New-Object System.Drawing.Size(760, 520); $f.MinimumSize = New-Object System.Drawing.Size(640, 480)
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $ico = Get-CPAppIcon; if ($ico) { $f.Icon = $ico }

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.ColumnCount = 3; $grid.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $row = 0

    $title = New-CPLabel 'Settings' $script:CPFontTitle
    $grid.Controls.Add($title, 0, $row); $grid.SetColumnSpan($title, 3); $row++
    if ($Intro) {
        $il = New-CPLabel $Intro; $il.MaximumSize = New-Object System.Drawing.Size(700, 0); $il.ForeColor = $script:CPOrange
        $grid.Controls.Add($il, 0, $row); $grid.SetColumnSpan($il, 3); $row++
    }

    # practice file
    $grid.Controls.Add((New-CPLabel 'Practice file (main.cpp):'), 0, $row)
    $mainBox = New-CPTextBox; $mainBox.Text = $Config.MainCppPath
    $grid.Controls.Add($mainBox, 1, $row)
    $mainBrowse = New-CPButton 'Browse...'
    $mainBrowse.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'C++ files (*.cpp)|*.cpp|All files (*.*)|*.*'; $d.Title = 'Select the main.cpp you practice in'
        if ($mainBox.Text -and (Test-Path -LiteralPath $mainBox.Text)) { $d.InitialDirectory = Split-Path $mainBox.Text -Parent }
        if ($d.ShowDialog() -eq 'OK') { $mainBox.Text = $d.FileName }
    })
    $grid.Controls.Add($mainBrowse, 2, $row); $row++

    # repo folder
    $grid.Controls.Add((New-CPLabel 'Solutions repo folder:'), 0, $row)
    $repoBox = New-CPTextBox; $repoBox.Text = $Config.RepoPath
    $grid.Controls.Add($repoBox, 1, $row)
    $repoBrowse = New-CPButton 'Browse...'
    $repoBrowse.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Select your local clone of the solutions repo'
        if ($repoBox.Text -and (Test-Path -LiteralPath $repoBox.Text)) { $d.SelectedPath = $repoBox.Text }
        if ($d.ShowDialog() -eq 'OK') { $repoBox.Text = $d.SelectedPath }
    })
    $grid.Controls.Add($repoBrowse, 2, $row); $row++

    $repoBtns = New-Object System.Windows.Forms.FlowLayoutPanel
    $repoBtns.AutoSize = $true; $repoBtns.Dock = 'Fill'; $repoBtns.WrapContents = $true
    $cloneBtn = New-CPButton 'Clone a GitHub repo...'
    $createBtn = New-CPButton 'Create a new GitHub repo...'
    $repoBtns.Controls.Add($cloneBtn); $repoBtns.Controls.Add($createBtn)
    $grid.Controls.Add($repoBtns, 1, $row); $grid.SetColumnSpan($repoBtns, 2); $row++

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
            $url = New-CPGitHubRepo -Name $name.Trim() -Description 'My accepted competitive programming solutions (C++)' -Private:($priv -eq 'Yes')
            $f.Cursor = 'Default'
            & $cloneInto $url
        }
    })

    # template
    $grid.Controls.Add((New-CPLabel 'New-problem template:'), 0, $row)
    $tplLabel = New-CPLabel $Config.TemplatePath; $tplLabel.ForeColor = [System.Drawing.Color]::DimGray
    $grid.Controls.Add($tplLabel, 1, $row)
    $tplBtns = New-Object System.Windows.Forms.FlowLayoutPanel; $tplBtns.AutoSize = $true
    $tplEdit = New-CPButton 'Edit'
    $tplEdit.Add_Click({ Initialize-CPTemplate $Config.TemplatePath; Start-Process notepad.exe -ArgumentList "`"$($Config.TemplatePath)`"" })
    $tplBtns.Controls.Add($tplEdit)
    $grid.Controls.Add($tplBtns, 2, $row); $row++

    # options
    $opts = New-Object System.Windows.Forms.FlowLayoutPanel
    $opts.FlowDirection = 'TopDown'; $opts.AutoSize = $true; $opts.Dock = 'Fill'; $opts.Margin = New-Object System.Windows.Forms.Padding(3, 10, 3, 3)
    $mk = { param($text, $val) $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $text; $c.AutoSize = $true; $c.Checked = [bool]$val; $c.Font = $script:CPFont; $opts.Controls.Add($c); $c }
    $cFetch = & $mk 'Look up problem name, difficulty and topics online (Codeforces, LeetCode, AtCoder, CSES)' $Config.AutoFetch
    $cPush  = & $mk 'Push to GitHub after saving' $Config.PushAfterSave
    $cReset = & $mk 'Reset main.cpp to the template after saving' $Config.ResetAfterSave
    $cIdx   = & $mk 'Update README progress and topic / difficulty indexes' $Config.UpdateIndexes
    $grid.Controls.Add($opts, 0, $row); $grid.SetColumnSpan($opts, 3); $row++

    $upg = New-CPButton 'Add Difficulty/Topics fields to my main.cpp header'
    $upg.Add_Click({
        Invoke-CPSafe -What 'Updating main.cpp' {
            if (-not (Test-Path -LiteralPath $mainBox.Text)) { throw 'Choose the practice file first.' }
            $changed = Add-CPHeaderFields $mainBox.Text
            $msg = if ($changed) { 'Added the missing header fields. Your code was not changed.' } else { 'The header already has all fields.' }
            [System.Windows.Forms.MessageBox]::Show($msg, 'CP Solution Saver') | Out-Null
        }
    })
    $grid.Controls.Add($upg, 0, $row); $grid.SetColumnSpan($upg, 3); $row++

    # bottom buttons
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel
    $btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'; $btns.Margin = New-Object System.Windows.Forms.Padding(3, 14, 3, 3)
    $ok = New-CPButton 'Save' 90
    $cancel = New-CPButton 'Cancel' 90; $cancel.DialogResult = 'Cancel'
    $btns.Controls.Add($cancel); $btns.Controls.Add($ok)
    $grid.Controls.Add($btns, 0, $row); $grid.SetColumnSpan($btns, 3); $row++
    $grid.RowCount = $row

    $ok.Add_Click({
        $Config.MainCppPath = $mainBox.Text.Trim('"', ' ')
        $Config.RepoPath = $repoBox.Text.Trim('"', ' ')
        $Config.AutoFetch = $cFetch.Checked; $Config.PushAfterSave = $cPush.Checked
        $Config.ResetAfterSave = $cReset.Checked; $Config.UpdateIndexes = $cIdx.Checked
        $problems = @(Test-CPConfig $Config)
        if ($problems.Count) {
            $a = [System.Windows.Forms.MessageBox]::Show(($problems -join "`n") + "`n`nSave anyway?", 'Settings', 'YesNo', 'Warning')
            if ($a -ne 'Yes') { return }
        }
        Save-CPConfig -Config $Config -Path $ConfigPath
        $f.DialogResult = 'OK'
        $f.Close()
    })

    $f.Controls.Add($grid); $f.CancelButton = $cancel
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
    $st = @{ Info = $null; LoadedMtime = [datetime]::MinValue; Existing = $null; Busy = $false }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "CP Solution Saver $(Get-CPAppVersion)"; $f.Font = $script:CPFont; $f.StartPosition = 'CenterScreen'
    $f.Size = New-Object System.Drawing.Size(860, 760); $f.MinimumSize = New-Object System.Drawing.Size(700, 620)
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi; $f.KeyPreview = $true
    $ico = Get-CPAppIcon; if ($ico) { $f.Icon = $ico }

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.ColumnCount = 3; $grid.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $row = 0

    $title = New-CPLabel 'Save an accepted solution' $script:CPFontTitle; $title.ForeColor = $script:CPAccent
    $grid.Controls.Add($title, 0, $row); $grid.SetColumnSpan($title, 3); $row++

    # source line
    $ui.Source = New-CPLabel ''; $ui.Source.ForeColor = [System.Drawing.Color]::DimGray
    $ui.Source.MaximumSize = New-Object System.Drawing.Size(700, 0)
    $grid.Controls.Add($ui.Source, 0, $row); $grid.SetColumnSpan($ui.Source, 2)
    $ui.Reload = New-CPButton 'Reload main.cpp'
    $grid.Controls.Add($ui.Reload, 2, $row); $row++

    # fields
    $grid.Controls.Add((New-CPLabel 'Problem name:'), 0, $row)
    $ui.Name = New-CPTextBox; $grid.Controls.Add($ui.Name, 1, $row); $grid.SetColumnSpan($ui.Name, 2); $row++

    $grid.Controls.Add((New-CPLabel 'Problem link:'), 0, $row)
    $ui.Link = New-CPTextBox; $grid.Controls.Add($ui.Link, 1, $row)
    $ui.Fetch = New-CPButton 'Look up online'; $grid.Controls.Add($ui.Fetch, 2, $row); $row++

    $grid.Controls.Add((New-CPLabel 'Platform / ID:'), 0, $row)
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
    $dh = New-CPLabel 'rating (800, 1200...) or Easy / Medium / Hard'; $dh.ForeColor = [System.Drawing.Color]::Gray
    $diffRow.Controls.Add($dh)
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
    $ui.OptReset = & $mk 'Reset main.cpp after saving' $Config.ResetAfterSave
    $grid.Controls.Add($opts, 0, $row); $grid.SetColumnSpan($opts, 3); $row++

    # buttons
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.AutoSize = $true; $btns.Dock = 'Fill'; $btns.WrapContents = $true
    $ui.Save = New-CPButton 'Save && Push   (Ctrl+S)' 190
    $ui.Save.Font = $script:CPFontBold; $ui.Save.BackColor = [System.Drawing.Color]::FromArgb(31, 136, 61); $ui.Save.ForeColor = [System.Drawing.Color]::White
    $ui.Save.FlatStyle = 'Flat'; $ui.Save.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
    $ui.Rebuild = New-CPButton 'Rebuild index'
    $ui.OpenFolder = New-CPButton 'Open repo folder'
    $ui.OpenWeb = New-CPButton 'Open on GitHub'
    $ui.Settings = New-CPButton 'Settings'
    foreach ($b in @($ui.Save, $ui.Rebuild, $ui.OpenFolder, $ui.OpenWeb, $ui.Settings)) { $btns.Controls.Add($b) }
    $grid.Controls.Add($btns, 0, $row); $grid.SetColumnSpan($btns, 3); $row++

    $ui.Status = New-CPLabel 'Ready.' $script:CPFontBold
    $grid.Controls.Add($ui.Status, 0, $row); $grid.SetColumnSpan($ui.Status, 3); $row++

    $ui.Log = New-Object System.Windows.Forms.TextBox
    $ui.Log.Multiline = $true; $ui.Log.ReadOnly = $true; $ui.Log.ScrollBars = 'Vertical'; $ui.Log.Font = $script:CPFontMono
    $ui.Log.Dock = 'Fill'; $ui.Log.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $grid.Controls.Add($ui.Log, 0, $row); $grid.SetColumnSpan($ui.Log, 3)
    $grid.RowCount = $row + 1
    for ($i = 0; $i -lt $row; $i++) { [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $f.Controls.Add($grid)

    # ------------------------------------------------------------ behaviour
    $log = { param($m) $ui.Log.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }
    $setStatus = { param($m, $color) $ui.Status.Text = $m; $ui.Status.ForeColor = $color; [System.Windows.Forms.Application]::DoEvents() }

    $topicsFromBox = { @(Merge-CPTopics @(,$ui.Topics.Text)) }

    $refreshTarget = {
        if (-not $st.Info) { return }
        $st.Info.Name = $ui.Name.Text.Trim(); $st.Info.Platform = $ui.Platform.Text.Trim(); $st.Info.Id = $ui.Id.Text.Trim(); $st.Info.Link = $ui.Link.Text.Trim()
        Update-CPSolutionPath $st.Info
        if (-not $st.Info.RelPath) { $ui.Target.Text = '(enter a problem name)'; $ui.Target.ForeColor = $script:CPRed; $ui.KeepBoth.Visible = $false; return }
        $st.Existing = $null
        try { $st.Existing = Find-CPExistingSolution -RepoPath $Config.RepoPath -Info $st.Info } catch { }
        if ($st.Existing) {
            $ui.Target.Text = "$($st.Existing)   (already saved - will be updated)"; $ui.Target.ForeColor = $script:CPOrange; $ui.KeepBoth.Visible = $true
        } else {
            $ui.Target.Text = "$($st.Info.RelPath)   (new)"; $ui.Target.ForeColor = $script:CPGreen; $ui.KeepBoth.Visible = $false
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
        $f.Cursor = 'WaitCursor'; & $setStatus 'Looking the problem up online...' ([System.Drawing.Color]::DimGray)
        try { & $applyMetadata (Get-CPProblemMetadata $link) } finally { $f.Cursor = 'Default'; & $setStatus 'Ready.' ([System.Drawing.Color]::Black) }
        & $refreshTarget
    }

    $loadFile = {
        param([bool]$AllowFetch)
        $path = $Config.MainCppPath
        $code = Read-CPTextFile $path
        $st.LoadedMtime = (Get-Item -LiteralPath $path).LastWriteTime
        $st.Info = New-CPSolutionInfo -Code $code
        $ui.Name.Text = $st.Info.Name; $ui.Link.Text = $st.Info.Link
        $ui.Platform.Text = $st.Info.Platform; $ui.Id.Text = $st.Info.Id
        $ui.Difficulty.Text = $st.Info.Difficulty; $ui.Topics.Text = (@($st.Info.Topics) -join ', ')
        $ui.Notes.Text = ($st.Info.Notes -replace "\r?\n", "`r`n")
        $lines = @($code -split "`n").Count
        $ui.Source.Text = "From: $path   ($lines lines, saved $(Format-CPAgo $st.LoadedMtime))"
        & $log "Loaded $path"
        if (-not $st.Info.HasHeader) { & $log 'No problem header found at the top of main.cpp - fill the fields here (or use Settings > Add fields to header).' }
        & $refreshTarget
        if ($AllowFetch -and $Config.AutoFetch -and $st.Info.Link) { & $doFetch }
    }

    $mtimeTimer = New-Object System.Windows.Forms.Timer; $mtimeTimer.Interval = 3000
    $mtimeTimer.Add_Tick({
        try {
            $m = (Get-Item -LiteralPath $Config.MainCppPath).LastWriteTime
            if ($m -ne $st.LoadedMtime) {
                $ui.Source.Text = "main.cpp changed on disk $(Format-CPAgo $m) - click 'Reload main.cpp' to load the new version."
                $ui.Source.ForeColor = $script:CPOrange
            } else {
                $ui.Source.Text = ($ui.Source.Text -replace 'saved .*\)$', "saved $(Format-CPAgo $m))"); $ui.Source.ForeColor = [System.Drawing.Color]::DimGray
            }
        } catch { }
    })

    $doSave = {
        if ($st.Busy) { return }
        $st.Busy = $true; $ui.Save.Enabled = $false
        try {
            # use the latest code on disk, with the values from the form
            $code = Read-CPTextFile $Config.MainCppPath
            if ((Get-Item -LiteralPath $Config.MainCppPath).LastWriteTime -ne $st.LoadedMtime) { & $log 'Note: main.cpp changed since it was loaded; saving the newest code from disk.' }
            $info = New-CPSolutionInfo -Code $code
            $info.Name = $ui.Name.Text.Trim(); $info.Link = $ui.Link.Text.Trim(); $info.Platform = $ui.Platform.Text.Trim()
            $info.Id = $ui.Id.Text.Trim(); $info.Difficulty = $ui.Difficulty.Text.Trim(); $info.Topics = & $topicsFromBox
            $info.Notes = $ui.Notes.Text.Trim()
            if (-not $info.Platform) { $info.Platform = (Get-CPPlatformInfo $info.Link).Platform }
            if (-not $info.Name) { & $setStatus 'Enter the problem name first.' $script:CPRed; return }
            $ui.Log.Clear()
            & $setStatus 'Saving...' ([System.Drawing.Color]::DimGray)
            $f.Cursor = 'WaitCursor'
            $res = Save-CPSolution -Info $info -RepoPath $Config.RepoPath -Push:$ui.OptPush.Checked -UpdateIndexes:$ui.OptIdx.Checked -KeepBoth:$ui.KeepBoth.Checked -Log $log
            $f.Cursor = 'Default'
            if ($res.Success) {
                $msg = if ($res.Pushed) { "Done! $($res.RelPath) is on GitHub." } elseif ($res.Commit) { "Saved and committed $($res.RelPath) (not pushed)." } else { 'Nothing new to save - this exact solution is already in the repo.' }
                & $setStatus $msg $script:CPGreen
                if ($ui.OptReset.Checked) {
                    Reset-CPPracticeFile -MainCppPath $Config.MainCppPath -TemplatePath $Config.TemplatePath
                    & $log 'main.cpp reset to the template. (If Visual Studio asks, choose "Yes" to reload it.)'
                    & $loadFile $false
                } else { & $refreshTarget }
            } else {
                & $setStatus 'Something went wrong - see the details below.' $script:CPRed
            }
            # remember the option choices
            $Config.PushAfterSave = $ui.OptPush.Checked; $Config.UpdateIndexes = $ui.OptIdx.Checked; $Config.ResetAfterSave = $ui.OptReset.Checked
            Save-CPConfig -Config $Config -Path $ConfigPath
        } finally { $st.Busy = $false; $ui.Save.Enabled = $true; $f.Cursor = 'Default' }
    }

    $ui.Save.Add_Click({ Invoke-CPSafe -What 'Saving' $doSave })
    $ui.Fetch.Add_Click({ Invoke-CPSafe -What 'Online lookup' $doFetch })
    $ui.Reload.Add_Click({ Invoke-CPSafe -What 'Reload' { $ui.Log.Clear(); & $loadFile $true } })
    $ui.PickTopics.Add_Click({
        Invoke-CPSafe -What 'Topic picker' {
            $sel = Show-CPTopicPicker -Selected (& $topicsFromBox) -RepoPath $Config.RepoPath
            if ($null -ne $sel) { $ui.Topics.Text = ($sel -join ', ') }
        }
    })
    $ui.Rebuild.Add_Click({
        Invoke-CPSafe -What 'Rebuild index' {
            $ui.Log.Clear(); $f.Cursor = 'WaitCursor'
            $changed = Update-CPIndexes $Config.RepoPath
            Invoke-CPGit $Config.RepoPath (@('add', '--') + $changed) | Out-Null
            if ((Invoke-CPGit $Config.RepoPath diff --cached --quiet).Code -eq 0) { & $log 'Indexes are already up to date.' }
            else {
                $r = Invoke-CPGit $Config.RepoPath commit -q -m 'Rebuild solution indexes'; & $log "Committed: Rebuild solution indexes $($r.Output)"
                if ($ui.OptPush.Checked) { $r = Invoke-CPGit $Config.RepoPath push; & $log $(if ($r.Code -eq 0) { 'Pushed.' } else { "Push failed: $($r.Output)" }) }
            }
            $f.Cursor = 'Default'; & $setStatus 'Index rebuilt.' $script:CPGreen
        }
    })
    $ui.OpenFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($Config.RepoPath)`"" })
    $ui.OpenWeb.Add_Click({
        Invoke-CPSafe -What 'Open on GitHub' {
            $u = Get-CPRepoWebUrl $Config.RepoPath
            if ($u) { Start-Process $u } else { throw 'This repo has no GitHub remote.' }
        }
    })
    $ui.Settings.Add_Click({
        Invoke-CPSafe -What 'Settings' {
            if (Show-CPSettingsDialog -Config $Config -ConfigPath $ConfigPath) {
                $ui.OptPush.Checked = $Config.PushAfterSave; $ui.OptIdx.Checked = $Config.UpdateIndexes; $ui.OptReset.Checked = $Config.ResetAfterSave
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
        $f.Activate()
        Invoke-CPSafe -What 'Loading main.cpp' { & $loadFile $true }
        $mtimeTimer.Start()
    })
    $f.Add_FormClosed({ $timer.Stop(); $mtimeTimer.Stop() })

    [void]$f.ShowDialog()
    $f.Dispose()
}
