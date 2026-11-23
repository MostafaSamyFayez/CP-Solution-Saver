<#
.SYNOPSIS
    Self-test for CP Solution Saver. Uses a temporary repo with a local
    "remote", so nothing touches your real repo or GitHub.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1           # offline tests
    powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Online   # also test Codeforces/LeetCode lookups
#>
param([switch]$Online, [string]$SrcDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src'))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $SrcDir 'CPSaver.Core.psm1') -Force -DisableNameChecking

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}
function RunGit([string]$dir) { $a = @($args); $o = & git -C $dir @a 2>&1 | ForEach-Object { "$_" }; return ($o -join "`n") }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("cpsaver-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Host "`n[1] Header parsing" -ForegroundColor Cyan
    $code = "/*`r`n * Name: Two Arrays`r`n * Link: https://codeforces.com/contest/1234/problem/a`r`n * Tags: greedy, Sortings`r`n * Rating: 1300`r`n * Time Complexity: O(n log n)`r`n * Notes: first line`r`n *   second line`r`n */`r`n`r`n#include <iostream>`r`nint main(){}`r`n"
    $h = Read-CPHeader $code
    Check 'aliases map to canonical keys' ($h.Fields['Problem Name'] -eq 'Two Arrays' -and $h.Fields['Difficulty'] -eq '1300' -and $h.Fields['Topics'] -eq 'greedy, Sortings')
    Check 'extra field kept' ($h.Fields['Time Complexity'] -eq 'O(n log n)')
    Check 'multi-line notes' ($h.Fields['Notes'] -match 'first line' -and $h.Fields['Notes'] -match 'second line')
    Check 'body after header' ($h.Body.TrimStart().StartsWith('#include'))
    $plain = "/* just a comment */`nint main(){}"
    Check 'ordinary comment is not a header' (-not (Read-CPHeader $plain).HasHeader)

    Write-Host "`n[2] Platform detection" -ForegroundColor Cyan
    $cases = @(
        @('https://codeforces.com/contest/1234/problem/A', 'Codeforces', '1234A'),
        @('https://codeforces.com/problemset/problem/4/A', 'Codeforces', '4A'),
        @('https://codeforces.com/gym/104114/problem/B', 'Codeforces', '104114B'),
        @('https://leetcode.com/problems/two-sum/description/', 'LeetCode', ''),
        @('https://atcoder.jp/contests/abc300/tasks/abc300_a', 'AtCoder', 'abc300_a'),
        @('https://cses.fi/problemset/task/1068', 'CSES', '1068'),
        @('https://www.spoj.com/problems/PRIME1/', 'SPOJ', 'PRIME1'),
        @('https://www.codechef.com/problems/FLOW001', 'CodeChef', 'FLOW001'),
        @('https://example.com/p/1', 'Other', '')
    )
    foreach ($c in $cases) { $p = Get-CPPlatformInfo $c[0]; Check "$($c[1]) $($c[2])" ($p.Platform -eq $c[1] -and $p.Id -eq $c[2]) "got $($p.Platform) $($p.Id)" }

    Write-Host "`n[3] Saving into a temporary repo" -ForegroundColor Cyan
    $remote = Join-Path $tmp 'remote.git'; $repo = Join-Path $tmp 'solutions'
    RunGit $tmp init -q --bare $remote | Out-Null
    RunGit $tmp clone -q $remote $repo | Out-Null
    RunGit $repo config user.email test@example.com | Out-Null; RunGit $repo config user.name tester | Out-Null
    RunGit $repo symbolic-ref HEAD refs/heads/main | Out-Null
    Set-Content -Path (Join-Path $repo 'README.md') -Value "# My solutions`n`nHand-written intro stays.`n"
    RunGit $repo add -A | Out-Null; RunGit $repo commit -q -m init | Out-Null; RunGit $repo push -q -u origin main | Out-Null

    $info = New-CPSolutionInfo -Code $code
    Check 'file path from id + name' ($info.RelPath -eq 'Codeforces/1234A_Two_Arrays.cpp') "got $($info.RelPath)"
    $r = Save-CPSolution -Info $info -RepoPath $repo -Push -UpdateIndexes
    Check 'save succeeded' $r.Success ($r.Log -join ' / ')
    Check 'pushed' $r.Pushed
    $saved = Get-Content (Join-Path $repo 'Codeforces/1234A_Two_Arrays.cpp') -Raw
    Check 'saved header normalized' ($saved -match 'Problem Name: Two Arrays' -and $saved -match 'Platform: Codeforces' -and $saved -match 'Problem ID: 1234A' -and $saved -match 'Date Solved: \d{4}-\d\d-\d\d')
    Check 'code kept' ($saved -match '#include <iostream>')
    Check 'commit message' ((RunGit $repo log -1 --format=%s) -eq 'Add Codeforces 1234A - Two Arrays')
    Check 'remote has commit' ((RunGit $remote log -1 --format=%s main) -eq 'Add Codeforces 1234A - Two Arrays')
    $readme = Get-Content (Join-Path $repo 'README.md') -Raw
    Check 'README keeps intro + has stats' ($readme -match 'Hand-written intro stays' -and $readme -match 'CPSAVER:STATS:START' -and $readme -match '\*\*1\*\* problems solved')
    $byTopic = Get-Content (Join-Path $repo 'Index/BY_TOPIC.md') -Raw
    Check 'topic index has greedy and sortings' ($byTopic -match '## greedy' -and $byTopic -match '## sortings')
    $byDiff = Get-Content (Join-Path $repo 'Index/BY_DIFFICULTY.md') -Raw
    Check 'difficulty index has Rating 1300' ($byDiff -match '## Rating 1300')

    Write-Host "`n[4] Same problem again" -ForegroundColor Cyan
    $code2 = $code -replace 'Two Arrays', 'Two Arrays (renamed)' -replace 'int main\(\)\{\}', 'int main(){ return 0; }'
    $info2 = New-CPSolutionInfo -Code $code2
    $r2 = Save-CPSolution -Info $info2 -RepoPath $repo -Push -UpdateIndexes
    Check 'same link updates the existing file' ($r2.IsUpdate -and $r2.RelPath -eq 'Codeforces/1234A_Two_Arrays.cpp') "got $($r2.RelPath)"
    Check 'commit says Update' ((RunGit $repo log -1 --format=%s) -like 'Update Codeforces 1234A*')
    $r3 = Save-CPSolution -Info (New-CPSolutionInfo -Code $code2) -RepoPath $repo -Push -UpdateIndexes -KeepBoth
    Check 'keep both -> _v2' ($r3.RelPath -eq 'Codeforces/1234A_Two_Arrays_v2.cpp') "got $($r3.RelPath)"
    $r4 = Save-CPSolution -Info (New-CPSolutionInfo -Code $code2) -RepoPath $repo -Push -UpdateIndexes
    Check 'identical save -> nothing to commit' ($r4.Success -and -not $r4.Commit)

    Write-Host "`n[5] LeetCode without id, untagged" -ForegroundColor Cyan
    $lc = "/*`n * Problem Name: Two Sum`n * Problem Link: https://leetcode.com/problems/two-sum/`n * Difficulty: Easy`n */`nclass Solution {};`n"
    $i5 = New-CPSolutionInfo -Code $lc
    $r5 = Save-CPSolution -Info $i5 -RepoPath $repo -UpdateIndexes
    Check 'LeetCode path' ($r5.RelPath -eq 'LeetCode/Two_Sum.cpp') "got $($r5.RelPath)"
    $byDiff = Get-Content (Join-Path $repo 'Index/BY_DIFFICULTY.md') -Raw
    Check 'Easy group present' ($byDiff -match '## Easy')
    Check 'untagged topic group' ((Get-Content (Join-Path $repo 'Index/BY_TOPIC.md') -Raw) -match '## untagged')
    Check 'all solutions scanned' (@(Get-CPAllSolutions $repo).Count -eq 3)

    Write-Host "`n[6] Template + header upgrade" -ForegroundColor Cyan
    $tpl = Join-Path $tmp 'template.cpp'; $main = Join-Path $tmp 'main.cpp'
    Set-Content -Path $main -Value "/*`n * Problem Name: `n * Problem Link: `n * Notes: `n */`nint main(){}"
    Check 'missing fields added' (Add-CPHeaderFields $main)
    $m = Get-Content $main -Raw
    Check 'header has Topics + Difficulty, code kept' ($m -match 'Topics:' -and $m -match 'Difficulty:' -and $m -match 'int main')
    Reset-CPPracticeFile -MainCppPath $main -TemplatePath $tpl
    Check 'reset writes template' ((Get-Content $main -Raw) -match 'Problem Name:' -and (Test-Path $tpl))

    Write-Host "`n[7] Console mode end to end" -ForegroundColor Cyan
    $cfgPath = Join-Path $tmp 'config.json'
    $cfg = Get-CPDefaultConfig; $cfg.MainCppPath = $main; $cfg.RepoPath = $repo; $cfg.TemplatePath = $tpl; $cfg.ResetAfterSave = $true
    Save-CPConfig -Config $cfg -Path $cfgPath
    Set-Content -Path $main -Value "/*`n * Problem Name: Weird Algorithm`n * Problem Link: https://cses.fi/problemset/task/1068`n * Topics: introductory, simulation`n */`nint main(){}"
    $exe = (Get-Process -Id $PID).Path
    $out = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SrcDir 'CPSaver.ps1') -Cli -Yes -NoFetch -ConfigPath $cfgPath 2>&1 | Out-String
    Check 'cli exit code 0' ($LASTEXITCODE -eq 0) $out
    Check 'cli saved CSES file' (Test-Path (Join-Path $repo 'CSES/1068_Weird_Algorithm.cpp')) $out
    Check 'cli reset main.cpp' ((Get-Content $main -Raw) -notmatch 'Weird Algorithm')
    Check 'cli pushed' ((RunGit $remote log -1 --format=%s main) -eq 'Add CSES 1068 - Weird Algorithm')

    if ($Online) {
        Write-Host "`n[8] Online lookups" -ForegroundColor Cyan
        $cf = Get-CPProblemMetadata 'https://codeforces.com/problemset/problem/4/A'
        Check 'Codeforces 4A -> Watermelon, 800, tags' ($cf.Ok -and $cf.Name -eq 'Watermelon' -and $cf.Difficulty -eq '800' -and @($cf.Topics).Count -gt 0) $cf.Message
        $lcm = Get-CPProblemMetadata 'https://leetcode.com/problems/two-sum/'
        Check 'LeetCode two-sum -> 0001 Two Sum Easy' ($lcm.Ok -and $lcm.Name -eq 'Two Sum' -and $lcm.Id -eq '0001' -and $lcm.Difficulty -eq 'Easy') $lcm.Message
        $cs = Get-CPProblemMetadata 'https://cses.fi/problemset/task/1068'
        Check 'CSES 1068 -> Weird Algorithm' ($cs.Ok -and $cs.Name -eq 'Weird Algorithm') $cs.Message
        $ac = Get-CPProblemMetadata 'https://atcoder.jp/contests/abc086/tasks/abc086_a'
        Check 'AtCoder abc086_a -> Product' ($ac.Ok -and $ac.Name -eq 'Product') "$($ac.Message) name='$($ac.Name)'"
    }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ("`n{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 } else { exit 0 }
