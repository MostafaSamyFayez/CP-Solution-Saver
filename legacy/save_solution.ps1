<#
  save_solution.ps1
  -----------------
  Saves the current main.cpp as a named solution file inside your solutions
  git repo, then commits and pushes it.

  It reads the header at the top of main.cpp:
      /*
       * Problem Name: Two Arrays
       * Problem Link: https://codeforces.com/contest/1234/problem/A
       * Notes: greedy
       */

  and produces e.g.  <repo>\Codeforces\1234A_Two_Arrays.cpp
  with commit message "Add Codeforces 1234A - Two Arrays".

  First run asks for the path of your local solutions repo clone and remembers
  it in save_solution.config.json next to this script.
#>

param(
    [string]$MainCpp = (Join-Path $PSScriptRoot "Problem_Solving_Practice_Code_2026\main.cpp"),
    [switch]$NoPush,     # commit only, don't push
    [switch]$NoReset     # don't offer to reset main.cpp to the blank template
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail($msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# ---------- config: where is the solutions repo? ----------
$configPath = Join-Path $PSScriptRoot "save_solution.config.json"
$config = $null
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
}
if (-not $config -or -not $config.RepoPath -or -not (Test-Path (Join-Path $config.RepoPath ".git"))) {
    Write-Host "Enter the full path of your local solutions repo (a folder that is a git clone):" -ForegroundColor Cyan
    $repoInput = (Read-Host "Repo path").Trim('"', ' ')
    if (-not (Test-Path (Join-Path $repoInput ".git"))) {
        Fail "'$repoInput' is not a git repository. Clone your repo first (git clone <url>)."
    }
    $config = [pscustomobject]@{ RepoPath = (Resolve-Path $repoInput).Path }
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json), $utf8NoBom)
    Write-Host "Saved repo path to $configPath" -ForegroundColor DarkGray
}
$repo = $config.RepoPath

# ---------- read main.cpp ----------
if (-not (Test-Path $MainCpp)) { Fail "main.cpp not found at $MainCpp" }
$code = [IO.File]::ReadAllText($MainCpp)

function Get-HeaderField([string]$text, [string]$field) {
    $m = [regex]::Match($text, "(?im)^\s*\*?\s*$([regex]::Escape($field))\s*:[ \t]*(.*)$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ""
}

$name = Get-HeaderField $code "Problem Name"
$link = Get-HeaderField $code "Problem Link"

if (-not $name) { $name = (Read-Host "Problem Name is empty in main.cpp. Enter it").Trim() }
if (-not $link) { $link = (Read-Host "Problem Link is empty. Enter it (or leave blank)").Trim() }
if (-not $name) { Fail "A problem name is required." }

# ---------- work out platform + problem id from the link ----------
$platform = "Other"
$id = ""
switch -Regex ($link) {
    'codeforces\.com/(?:contest|gym)/(\d+)/problem/(\w+)'   { $platform = "Codeforces"; $id = "$($Matches[1])$($Matches[2])"; break }
    'codeforces\.com/problemset/problem/(\d+)/(\w+)'        { $platform = "Codeforces"; $id = "$($Matches[1])$($Matches[2])"; break }
    'codeforces\.com'                                       { $platform = "Codeforces"; break }
    'leetcode\.com/problems/([\w-]+)'                       { $platform = "LeetCode";   break }
    'atcoder\.jp/contests/[\w-]+/tasks/([\w-]+)'            { $platform = "AtCoder";    $id = $Matches[1]; break }
    'cses\.fi/problemset/task/(\d+)'                        { $platform = "CSES";       $id = $Matches[1]; break }
    'vjudge\.net'                                           { $platform = "VJudge";     break }
    'hackerrank\.com'                                       { $platform = "HackerRank"; break }
    'spoj\.com/problems/(\w+)'                              { $platform = "SPOJ";       $id = $Matches[1]; break }
}

# ---------- build a safe file name ----------
$safeName = ($name -replace '[\\/:*?"<>|]', '' -replace '[^\w\-]+', '_').Trim('_')
$fileBase = if ($id) { "${id}_$safeName" } else { $safeName }
$destDir  = Join-Path $repo $platform
$destFile = Join-Path $destDir "$fileBase.cpp"

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

if (Test-Path $destFile) {
    $ans = Read-Host "$platform\$fileBase.cpp already exists. Overwrite? (y/N)"
    if ($ans -notmatch '^[yY]') {
        $i = 2
        while (Test-Path (Join-Path $destDir "${fileBase}_v$i.cpp")) { $i++ }
        $fileBase = "${fileBase}_v$i"
        $destFile = Join-Path $destDir "$fileBase.cpp"
    }
}

Copy-Item -LiteralPath $MainCpp -Destination $destFile -Force
Write-Host "Saved -> $destFile" -ForegroundColor Green

# ---------- git add / commit / push ----------
$label  = if ($id) { "$platform $id - $name" } else { "$platform - $name" }
$relPath = "$platform/$fileBase.cpp"

Push-Location $repo
try {
    git add -- "$relPath"
    if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "No changes to commit (identical file already in repo)." -ForegroundColor Yellow
    } else {
        git commit -m "Add $label"
        if ($LASTEXITCODE -ne 0) { Fail "git commit failed." }

        if (-not $NoPush) {
            git pull --rebase --autostash
            if ($LASTEXITCODE -ne 0) { Fail "git pull --rebase failed. Resolve it in $repo, then run 'git push'." }
            git push
            if ($LASTEXITCODE -ne 0) { Fail "git push failed. Your commit is saved locally; run 'git push' in $repo." }
            Write-Host "Pushed: $label" -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}

# ---------- reset main.cpp for the next problem ----------
if (-not $NoReset) {
    $ans = Read-Host "Reset main.cpp to a blank template for the next problem? (y/N)"
    if ($ans -match '^[yY]') {
        $template = @"
/*
 * Problem Name:
 * Problem Link:
 * Notes:
 */

#include <iostream>
#include <vector>
#include <string>
#include <algorithm>

using namespace std;
int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);

    return 0;
}
"@
        [IO.File]::WriteAllText($MainCpp, ($template -replace "`r?`n", "`r`n"), $utf8NoBom)
        Write-Host "main.cpp reset." -ForegroundColor DarkGray
    }
}
