<#
.SYNOPSIS
    Removes CP Solution Saver (app files and shortcuts).
    Your solutions repo is never touched. Settings are kept unless -RemoveSettings.
#>
param([switch]$RemoveSettings, [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\CPSolutionSaver'))

Set-Location $env:TEMP
# stop the tray app first (its files are in use)
try {
    $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\CPSolutionSaver_cmd_exit'); [void]$ev.Set(); $ev.Dispose()
    for ($i = 0; $i -lt 60; $i++) { try { $m = [System.Threading.Mutex]::OpenExisting('Local\CPSolutionSaver_Host'); $m.Dispose(); Start-Sleep -Milliseconds 100 } catch { break } }
    Start-Sleep -Milliseconds 300
    Write-Host 'Stopped CP Solution Saver (tray).'
} catch { }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*CPSaver.ps1*-Tray*' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch { } }
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'CP Solution Saver.lnk'
if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup -Force; Write-Host "Removed $startup" }
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
