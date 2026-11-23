<#
.SYNOPSIS
    Builds CP-Solution-Saver.zip (Install.bat + README + LICENSE + app\) and publishes it as a
    GitHub release for the current version. For maintainers; users never need this.

.DESCRIPTION
    Uses Git's existing GitHub sign-in (Git Credential Manager); the token is never printed.
    Push your commits first: the release is created on the commit you have checked out.
    Users then download one file:
        https://github.com/<owner>/<repo>/releases/latest/download/CP-Solution-Saver.zip

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File app\tools\New-Release.ps1            # build + publish
    powershell -ExecutionPolicy Bypass -File app\tools\New-Release.ps1 -NoUpload  # only build the zip
#>
param([switch]$NoUpload)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $root 'app\src\CPSaver.Core.psm1') -Force -DisableNameChecking
$ver = Get-CPAppVersion
$tag = "v$ver"
$assetName = 'CP-Solution-Saver.zip'

# 1. build the zip: one top folder with Install.bat, README.md, LICENSE and app\ (without this tools folder)
$stage = Join-Path ([IO.Path]::GetTempPath()) "cpsaver-release-$ver"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$top = Join-Path $stage 'CP-Solution-Saver'
New-Item -ItemType Directory -Path $top -Force | Out-Null
foreach ($f in @('Install.bat', 'README.md', 'LICENSE')) { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $top }
Copy-Item -LiteralPath (Join-Path $root 'app') -Destination $top -Recurse
Remove-Item -LiteralPath (Join-Path $top 'app\tools') -Recurse -Force -ErrorAction SilentlyContinue
$zip = Join-Path $stage $assetName
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($top, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host "Built $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) KB)" -ForegroundColor Green
if ($NoUpload) { return }

# 2. the GitHub repo and sign-in
$origin = (& git -C $root remote get-url origin).Trim()
if ($origin -notmatch 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') { throw "origin is not a GitHub repo: $origin" }
$owner = $Matches[1]; $repo = $Matches[2]
$token = Get-CPGitHubToken
if (-not $token) { throw 'No GitHub sign-in found in Git. Run "git push" once to sign in, then try again.' }
Initialize-CPWeb
$h = @{ Authorization = "token $token"; 'User-Agent' = 'CPSolutionSaver'; Accept = 'application/vnd.github+json' }
$api = "https://api.github.com/repos/$owner/$repo"

# 3. release notes = this version's section of the changelog
$notes = ''
$cl = Join-Path $root 'app\CHANGELOG.md'
if (Test-Path $cl) {
    $m = [regex]::Match((Get-Content -LiteralPath $cl -Raw), "(?ms)^## $([regex]::Escape($ver))[^\n]*\n(.*?)(?=^## |\z)")
    if ($m.Success) { $notes = $m.Groups[1].Value.Trim() }
}
$notes = "**Install:** download **$assetName** below, extract it, double-click **Install.bat**.`n`n$notes"

# 4. create (or reuse) the release, then replace the zip
$commit = (& git -C $root rev-parse HEAD).Trim()
$rel = $null
try { $rel = Invoke-RestMethod -Uri "$api/releases/tags/$tag" -Headers $h } catch { }
if (-not $rel) {
    $body = @{ tag_name = $tag; target_commitish = $commit; name = "CP Solution Saver $ver"; body = $notes; draft = $false; prerelease = $false } | ConvertTo-Json
    $rel = Invoke-RestMethod -Method Post -Uri "$api/releases" -Headers $h -Body $body -ContentType 'application/json'
    Write-Host "Created release $tag" -ForegroundColor Green
} else {
    $body = @{ body = $notes; name = "CP Solution Saver $ver" } | ConvertTo-Json
    $rel = Invoke-RestMethod -Method Patch -Uri "$api/releases/$($rel.id)" -Headers $h -Body $body -ContentType 'application/json'
    Write-Host "Updating release $tag" -ForegroundColor Yellow
}
foreach ($a in @($rel.assets)) {
    if ($a -and $a.name -eq $assetName) { Invoke-RestMethod -Method Delete -Uri "$api/releases/assets/$($a.id)" -Headers $h | Out-Null }
}
$up = "https://uploads.github.com/repos/$owner/$repo/releases/$($rel.id)/assets?name=$assetName"
$asset = Invoke-RestMethod -Method Post -Uri $up -Headers $h -InFile $zip -ContentType 'application/zip'
Write-Host "Uploaded $($asset.name)  ->  $($asset.browser_download_url)" -ForegroundColor Green
Write-Host "Release page: $($rel.html_url)"
Write-Host "Latest download link: https://github.com/$owner/$repo/releases/latest/download/$assetName"
