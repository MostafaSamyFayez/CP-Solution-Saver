<#
.SYNOPSIS
    Removes CP Solution Saver (app files and shortcuts).
    Your solutions repo is never touched. Settings are kept unless -RemoveSettings.
#>
param([switch]$RemoveSettings, [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'))

Set-Location $env:TEMP
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CP Solution Saver'
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CP Solution Saver.lnk'
foreach ($p in @($menu, $desk, $InstallDir)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "Removed $p" }
}
$data = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'CPSolutionSaver'
if ($RemoveSettings) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "Removed $data" }
else { Write-Host "Kept your settings and template in $data (run with -RemoveSettings to delete them)." }
Write-Host 'CP Solution Saver was uninstalled. Your solutions repo was not changed.' -ForegroundColor Green
Write-Host 'Note: a save_solution.bat launcher next to your practice project (if any) can be deleted by hand.'
