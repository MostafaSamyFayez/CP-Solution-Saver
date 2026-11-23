<#
.SYNOPSIS
    CP Solution Saver - save an accepted solution from your practice main.cpp
    into your GitHub solutions repo (organized by platform, indexed by topic
    and difficulty), then commit and push.

.DESCRIPTION
    With no switches it opens the window (GUI).

.EXAMPLE
    CPSaver.ps1                    # open the window
    CPSaver.ps1 -Cli               # console mode, asks before saving
    CPSaver.ps1 -Cli -Yes          # console mode, no questions
    CPSaver.ps1 -RebuildIndex      # regenerate README stats + Index/*.md and push
    CPSaver.ps1 -Settings          # open the settings window
#>
[CmdletBinding()]
param(
    [switch]$Cli,
    [switch]$Yes,
    [switch]$RebuildIndex,
    [switch]$Settings,
    [string]$ConfigPath,
    [string]$MainCpp,
    [switch]$NoFetch,
    [switch]$NoPush,
    [switch]$NoReset,
    [switch]$KeepBoth,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CPSaver.Core.psm1') -Force -DisableNameChecking

if ($Version) { "CP Solution Saver $(Get-CPAppVersion)"; return }
if (-not $ConfigPath) { $ConfigPath = Get-CPDefaultConfigPath }
$config = Get-CPConfig -Path $ConfigPath
if ($MainCpp) { $config.MainCppPath = $MainCpp }
Initialize-CPTemplate $config.TemplatePath

$isWindowsHost = ($env:OS -eq 'Windows_NT')

# ---------------------------------------------------------------- GUI
if (-not $Cli -and -not $RebuildIndex -and $isWindowsHost) {
    . (Join-Path $PSScriptRoot 'CPSaver.Gui.ps1')
    if ($Settings) { Show-CPSettingsDialog -Config $config -ConfigPath $ConfigPath | Out-Null }
    else { Show-CPMainWindow -Config $config -ConfigPath $ConfigPath }
    return
}

# ---------------------------------------------------------------- console
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

$problems = @(Test-CPConfig $config)
if ($RebuildIndex) { $problems = @($problems | Where-Object { $_ -notlike 'Practice file*' }) }
if ($problems.Count) {
    $problems | ForEach-Object { Say "Config problem: $_" Red }
    Say "Fix it with:  CPSaver.ps1 -Settings   (or edit $ConfigPath)" Yellow
    exit 2
}
$repo = $config.RepoPath

if ($RebuildIndex) {
    $changed = Update-CPIndexes $repo
    Invoke-CPGit $repo (@('add', '--') + $changed) | Out-Null
    if ((Invoke-CPGit $repo diff --cached --quiet).Code -eq 0) { Say 'Indexes already up to date.' Green; exit 0 }
    $r = Invoke-CPGit $repo commit -q -m 'Rebuild solution indexes'
    if ($r.Code -ne 0) { Say $r.Output Red; exit 1 }
    Say 'Committed: Rebuild solution indexes' Green
    if (-not $NoPush -and $config.PushAfterSave) {
        $r = Invoke-CPGit $repo push
        if ($r.Code -ne 0) { Say "Push failed: $($r.Output)" Red; exit 1 }
        Say 'Pushed.' Green
    }
    exit 0
}

$code = Read-CPTextFile $config.MainCppPath
$fetch = (-not $NoFetch) -and [bool]$config.AutoFetch
$info = New-CPSolutionInfo -Code $code -Fetch:$fetch

if (-not $info.Name -and -not $Yes) { $info.Name = (Read-Host 'Problem Name is empty. Enter it').Trim() }
if (-not $info.Name) { Say 'A problem name is required (fill "Problem Name:" in the header).' Red; exit 1 }
Update-CPSolutionPath $info

Say ''
Say "  Problem    : $($info.Name)" White
Say "  Link       : $($info.Link)"
Say "  Platform   : $($info.Platform)   ID: $($info.Id)"
Say "  Difficulty : $($info.Difficulty)"
Say "  Topics     : $(@($info.Topics) -join ', ')"
Say "  Will save  : $($info.RelPath)" Cyan
if ($info.Metadata) { Say "  ($($info.Metadata.Message))" DarkGray }
$existing = Find-CPExistingSolution -RepoPath $repo -Info $info
if ($existing) { Say "  Note: already saved as $existing ($(if ($KeepBoth) { 'will keep both' } else { 'will update it' }))" Yellow }
Say ''

if (-not $Yes) {
    $ans = Read-Host 'Save and push? (Y/n)'
    if ($ans -match '^[nN]') { Say 'Cancelled.'; exit 0 }
}

$push = (-not $NoPush) -and [bool]$config.PushAfterSave
$res = Save-CPSolution -Info $info -RepoPath $repo -Push:$push -UpdateIndexes:([bool]$config.UpdateIndexes) -KeepBoth:$KeepBoth `
    -Log { param($m) $c = if ($m -like 'ERROR*') { 'Red' } elseif ($m -like 'WARNING*') { 'Yellow' } else { 'Gray' }; Write-Host "  $m" -ForegroundColor $c }

if (-not $res.Success) { exit 1 }
Say 'Done.' Green

$doReset = (-not $NoReset) -and [bool]$config.ResetAfterSave
if (-not $NoReset -and -not $Yes -and -not $config.ResetAfterSave) {
    $doReset = (Read-Host 'Reset main.cpp to the template for the next problem? (y/N)') -match '^[yY]'
}
if ($doReset) { Reset-CPPracticeFile -MainCppPath $config.MainCppPath -TemplatePath $config.TemplatePath; Say 'main.cpp reset to template.' DarkGray }
exit 0
