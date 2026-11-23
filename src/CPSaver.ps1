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
    CPSaver.ps1 -Quick             # quick save: no window, just a notification with the result
    CPSaver.ps1 -Browse            # browse / search solved problems and load one into main.cpp
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
    [switch]$Quick,
    [switch]$NoNotify,
    [switch]$Browse,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CPSaver.Core.psm1') -Force -DisableNameChecking

if ($Version) { "CP Solution Saver $(Get-CPAppVersion)"; return }
if (-not $ConfigPath) { $ConfigPath = Get-CPDefaultConfigPath }
$config = Get-CPConfig -Path $ConfigPath
if ($MainCpp) {
    # -MainCpp: use this practice file (and remember it in the list for this run)
    $config.MainCppPath = (Resolve-Path -LiteralPath $MainCpp).ProviderPath
    if (-not (@($config.PracticeFiles) | Where-Object { $_ -ieq $config.MainCppPath })) { $config.PracticeFiles = @($config.PracticeFiles) + @($config.MainCppPath) }
}
Initialize-CPTemplates | Out-Null

$isWindowsHost = ($env:OS -eq 'Windows_NT')

# ---------------------------------------------------------------- quick save
if ($Quick) {
    if ($NoFetch) { $config.AutoFetch = $false }
    if ($NoPush) { $config.PushAfterSave = $false }
    if ($NoReset) { $config.ResetAfterSave = $false }
    if ($MainCpp) { $config.PracticeFiles = @($config.MainCppPath) }
    $res = Invoke-CPQuickSave -Config $config -Log { param($m) Write-Verbose $m }
    $res.Log | ForEach-Object { Write-Output $_ }
    if ($isWindowsHost -and -not $NoNotify) {
        . (Join-Path $PSScriptRoot 'CPSaver.Gui.ps1')
        $open = Show-CPNotification -Title $res.Title -Lines $res.Summary -IsError:(-not $res.Success) -Mode ([string]$config.QuickSaveNotify) -LogFile $res.LogFile
        if ($open) { Show-CPMainWindow -Config $config -ConfigPath $ConfigPath }
    }
    if ($res.Success) { exit 0 } else { exit 1 }
}

# ---------------------------------------------------------------- GUI
if (-not $Cli -and -not $RebuildIndex -and $isWindowsHost) {
    . (Join-Path $PSScriptRoot 'CPSaver.Gui.ps1')
    if ($Settings) { Show-CPSettingsDialog -Config $config -ConfigPath $ConfigPath | Out-Null }
    elseif ($Browse) {
        if (@(Test-CPConfig $config).Count) { Show-CPSettingsDialog -Config $config -ConfigPath $ConfigPath -Intro 'Set up your practice file and solutions repo first.' | Out-Null }
        Show-CPBrowser -Config $config
    }
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

$practice = if ($MainCpp) { $config.MainCppPath } else { Get-CPActivePracticeFile $config }
$code = Read-CPTextFile $practice
$fetch = (-not $NoFetch) -and [bool]$config.AutoFetch
$info = New-CPSolutionInfo -Code $code -Fetch:$fetch -Extension ([IO.Path]::GetExtension($practice))

if (-not $info.Link -and -not $Yes) { $info.Link = (Read-Host 'Problem Link is empty (required). Enter it').Trim(); $info.Platform = (Get-CPPlatformInfo $info.Link).Platform; if (-not $info.Id) { $info.Id = (Get-CPPlatformInfo $info.Link).Id } }
if (-not $info.Link) { Say 'The problem link is required (fill "Problem Link:" in the header). It identifies the problem.' Red; exit 1 }
if (-not $info.Name -and -not $Yes) { $info.Name = (Read-Host 'Problem Name is empty. Enter it').Trim() }
if (-not $info.Name) { Say 'A problem name is required (fill "Problem Name:" in the header).' Red; exit 1 }
Update-CPSolutionPath $info

Say ''
Say "  File       : $practice ($($info.Language))" DarkGray
Say "  Problem    : $($info.Name)" White
Say "  Link       : $($info.Link)"
Say "  Platform   : $($info.Platform)   ID: $($info.Id)"
Say "  Difficulty : $($info.Difficulty)"
Say "  Topics     : $(@($info.Topics) -join ', ')"
Say "  Will save  : $($info.RelPath)" Cyan
if ($info.Metadata) { Say "  ($($info.Metadata.Message))" DarkGray }
$existing = Find-CPExistingSolution -RepoPath $repo -Info $info
if ($existing) { Say "  Note: solved before - saved as $existing ($(if ($KeepBoth) { 'will keep both' } else { 'will update it' }))" Yellow }
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
    $doReset = (Read-Host "Reset $([IO.Path]::GetFileName($practice)) to the template for the next problem? (y/N)") -match '^[yY]'
}
if ($doReset) { Reset-CPPracticeFile -MainCppPath $practice -Config $config; Say "$([IO.Path]::GetFileName($practice)) reset to the template." DarkGray }
exit 0
