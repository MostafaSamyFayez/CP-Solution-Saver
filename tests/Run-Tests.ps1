<#
.SYNOPSIS
    Self-test for CP Solution Saver. Uses a temporary repo with a local
    "remote", so nothing touches your real repo or GitHub.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1           # offline tests
    powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Online   # also test Codeforces/LeetCode lookups
#>
param([switch]$Online, [string]$SrcDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src'))

# 'Continue': Windows PowerShell 5.1 turns git's stderr warnings into errors under 'Stop'.
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $SrcDir 'CPSaver.Core.psm1') -Force -DisableNameChecking

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}
function RunGit([string]$dir) { $a = @($args); $o = & git -C $dir @a 2>&1 | ForEach-Object { "$_" }; return ($o -join "`n") }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("cpsaver-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$oldDataDir = $env:CPSAVER_DATA_DIR
$env:CPSAVER_DATA_DIR = Join-Path $tmp 'appdata'   # keep backups / logs out of the real %APPDATA%
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

    Write-Host "`n[8] Quick save (no window)" -ForegroundColor Cyan
    $cfg.ResetAfterSave = $false; $cfg.AutoFetch = $false   # offline: online lookups are tested in [10]
    Set-Content -Path $main -Value "/*`n * Problem Name: Repetitions`n * Problem Link: https://cses.fi/problemset/task/1069`n * Difficulty: Easy`n * Topics: strings`n */`nint main(){}"
    $q = Invoke-CPQuickSave -Config $cfg
    Check 'quick save succeeded' $q.Success ($q.Summary -join ' / ')
    Check 'quick save title + summary' ($q.Title -eq 'Saved: Repetitions' -and ($q.Summary -join ' ') -match 'CSES/1069_Repetitions.cpp \(new\)' -and ($q.Summary -join ' ') -match 'Pushed to GitHub')
    Check 'quick save pushed' ((RunGit $remote log -1 --format=%s main) -eq 'Add CSES 1069 - Repetitions')
    Check 'quick save log file' (Test-Path $q.LogFile)
    $q2 = Invoke-CPQuickSave -Config $cfg
    Check 'quick save again -> already saved' ($q2.Success -and $q2.Title -like 'Already saved*')
    Set-Content -Path $main -Value "int main(){}"
    $q3 = Invoke-CPQuickSave -Config $cfg
    Check 'quick save without header -> clear error (link required)' ((-not $q3.Success) -and ($q3.Summary -join ' ') -match 'No problem link')
    Set-Content -Path $main -Value "/*`n * Problem Name: Missing Number`n * Problem Link: https://cses.fi/problemset/task/1083`n */`nint main(){ return 1; }"
    $out = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SrcDir 'CPSaver.ps1') -Quick -NoNotify -NoFetch -ConfigPath $cfgPath 2>&1 | Out-String
    Check 'cli -Quick exit 0 and saved' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $repo 'CSES/1083_Missing_Number.cpp'))) $out

    Write-Host "`n[9] Browse + load into main.cpp" -ForegroundColor Cyan
    $sols = @(Get-CPAllSolutions $repo)
    $rep = $sols | Where-Object { $_.Name -eq 'Repetitions' } | Select-Object -First 1
    Check 'solutions list has notes/fullpath fields' ($rep -and $rep.FullPath -and (Test-Path $rep.FullPath) -and $null -ne $rep.Notes)
    Set-Content -Path $main -Value "// my unsaved work"
    $bk = Import-CPSolution -Config $cfg -RelPath $rep.RelPath
    Check 'main.cpp now holds the loaded solution' ((Get-Content $main -Raw) -match 'Problem Name: Repetitions')
    Check 'old main.cpp backed up' ($bk -and (Test-Path $bk) -and ((Get-Content $bk -Raw) -match 'my unsaved work'))
    for ($i = 0; $i -lt 4; $i++) { Backup-CPPracticeFile -Path $main -Keep 3 | Out-Null; Start-Sleep -Milliseconds 20 }
    Check 'backups pruned to the newest 3' (@(Get-ChildItem (Get-CPBackupDir) -File).Count -eq 3)
    Check 'difficulty groups' ((Get-CPDifficultyGroup '1200').Label -eq 'Rating 1200' -and (Get-CPDifficultyGroup 'easy').Label -eq 'Easy' -and (Get-CPDifficultyGroup '').Label -eq 'Unrated')

    Write-Host "`n[10] Languages, link identity, dates, templates, settings" -ForegroundColor Cyan
    # python header (docstring) + save as .py
    $py = "`"`"`"`nProblem Name: Two Sum`nProblem Link: https://leetcode.com/problems/two-sum/description/`nTopics: array`n`"`"`"`n`nimport sys`nprint(1)`n"
    $hp = Read-CPHeader $py
    Check 'python docstring header parsed' ($hp.HasHeader -and $hp.Fields['Problem Name'] -eq 'Two Sum' -and $hp.Body.TrimStart().StartsWith('import sys'))
    $hh = Read-CPHeader "# Problem Name: Weird`n# Problem Link: https://cses.fi/problemset/task/1068`nn = int(input())`n"
    Check 'python # comment header parsed' ($hh.HasHeader -and $hh.Fields['Problem Link'] -match '1068' -and $hh.Body.StartsWith('n = int'))
    $hc = Read-CPHeader "// Problem Name: X`n// Problem Link: https://cses.fi/problemset/task/1069`n#include <stdio.h>`nint main(){}`n"
    Check '// header keeps #include in the body' ($hc.HasHeader -and $hc.Body.StartsWith('#include <stdio.h>'))
    Check 'no header in plain C++ (#include is not a comment)' (-not (Read-CPHeader "#include <iostream>`nint main(){}").HasHeader)
    $ipy = New-CPSolutionInfo -Code $py -Extension '.py'
    Check 'python file path' ($ipy.RelPath -eq 'LeetCode/Two_Sum.py' -and $ipy.Language -eq 'Python') "got $($ipy.RelPath)"
    $rpy = Save-CPSolution -Info $ipy -RepoPath $repo -UpdateIndexes
    $savedPy = Get-Content (Join-Path $repo 'LeetCode/Two_Sum.py') -Raw
    Check 'python saved with """ header, code kept' ($rpy.Success -and $savedPy.StartsWith('"""') -and $savedPy -match 'Problem Name: Two Sum' -and $savedPy -match 'import sys')
    Check 'python saved next to the C++ solution of the same problem (not over it)' ((Test-Path (Join-Path $repo 'LeetCode/Two_Sum.cpp')) -and ($rpy.Log -join ' ') -match 'another language')
    $ic = New-CPSolutionInfo -Code "/*`n * Problem Name: Missing Number`n * Problem Link: https://cses.fi/problemset/task/1083`n */`n#include <stdio.h>`nint main(void){return 0;}`n" -Extension '.c'
    Check 'C file path' ($ic.RelPath -eq 'CSES/1083_Missing_Number.c') "got $($ic.RelPath)"
    # link identity
    Check 'problem key: contest and problemset links are the same problem' ((Get-CPProblemKey 'https://codeforces.com/contest/4/problem/A') -eq (Get-CPProblemKey 'http://www.codeforces.com/problemset/problem/4/a?locale=en'))
    Check 'problem key: leetcode /description' ((Get-CPProblemKey 'https://leetcode.com/problems/two-sum/description/') -eq (Get-CPProblemKey 'https://leetcode.com/problems/two-sum'))
    Check 'problem key: other sites ignore query / trailing slash' ((Get-CPProblemKey 'https://example.com/p/7/?x=1') -eq (Get-CPProblemKey 'http://example.com/p/7'))
    $cf2 = "/*`n * Problem Name: Two Arrays (other spelling)`n * Problem Link: https://codeforces.com/problemset/problem/1234/A`n */`nint main(){}`n"
    $rk = Save-CPSolution -Info (New-CPSolutionInfo -Code $cf2) -RepoPath $repo -UpdateIndexes
    Check 'same problem via a different link spelling updates the same file' ($rk.IsUpdate -and $rk.RelPath -eq 'Codeforces/1234A_Two_Arrays.cpp') "got $($rk.RelPath)"
    $same = "/*`n * Problem Name: Watermelon`n * Problem Link: https://codeforces.com/problemset/problem/4/A`n */`nint main(){ return 4; }`n"
    $s1 = Save-CPSolution -Info (New-CPSolutionInfo -Code $same) -RepoPath $repo -UpdateIndexes
    $s2 = Save-CPSolution -Info (New-CPSolutionInfo -Code ($same -replace 'problemset/problem/4/A', 'contest/4/problem/A')) -RepoPath $repo -UpdateIndexes
    Check 'same code, link written differently -> nothing new (first link kept)' ($s1.Commit -and $s2.Success -and -not $s2.Commit -and ((Get-Content (Join-Path $repo $s1.RelPath) -Raw) -match 'problemset/problem/4/A'))
    $nolink = Save-CPSolution -Info (New-CPSolutionInfo -Code "/*`n * Problem Name: No Link`n */`nint main(){}") -RepoPath $repo
    Check 'saving without a link is refused' ((-not $nolink.Success) -and ($nolink.Log -join ' ') -match 'link is required')
    # date bug: same code saved again on a later day must not be a new change
    $dcode = "/*`n * Problem Name: Distinct Numbers`n * Problem Link: https://cses.fi/problemset/task/1621`n */`nint main(){ return 0; }`n"
    $d1 = New-CPSolutionInfo -Code $dcode; $d1.DateSolved = '2026-01-01'; $d1.DateAuto = $true
    $r1 = Save-CPSolution -Info $d1 -RepoPath $repo -UpdateIndexes
    $d2 = New-CPSolutionInfo -Code $dcode   # auto date = today
    $r2 = Save-CPSolution -Info $d2 -RepoPath $repo -UpdateIndexes
    Check 'same code on another day -> nothing new (first date kept)' ($r1.Commit -and $r2.Success -and -not $r2.Commit -and ((Get-Content (Join-Path $repo $r1.RelPath) -Raw) -match 'Date Solved: 2026-01-01'))
    $d3 = New-CPSolutionInfo -Code ($dcode -replace 'return 0;', 'return 0; /* faster */')
    $r3 = Save-CPSolution -Info $d3 -RepoPath $repo -UpdateIndexes
    Check 'changed code -> update, first date still kept' ($r3.Commit -like 'Update*' -and ((Get-Content (Join-Path $repo $r3.RelPath) -Raw) -match 'Date Solved: 2026-01-01'))
    # templates
    $tpls = @(Get-CPTemplates -Extension '.cpp')
    Check 'C++ templates installed (Basic first)' ($tpls.Count -ge 6 -and $tpls[0].Name -eq 'C++ - Basic')
    Check 'Python and C templates installed' (@(Get-CPTemplates -Extension '.py').Count -ge 3 -and @(Get-CPTemplates -Extension '.c').Count -ge 2)
    $pyT = Read-CPTextFile (@(Get-CPTemplates -Extension '.py')[0].Path)
    Check 'python template header is a docstring' ($pyT.StartsWith('"""') -and (Read-CPHeader $pyT).HasHeader)
    $tcfg = Get-CPDefaultConfig
    Check 'default reset template = Basic' ((Split-Path (Get-CPDefaultTemplatePath -Config $tcfg -Extension '.cpp') -Leaf) -eq 'C++ - Basic.cpp')
    $tcfg.DefaultTemplates['C++'] = 'C++ - Multiple test cases'
    Check 'chosen reset template used' ((Split-Path (Get-CPDefaultTemplatePath -Config $tcfg -Extension '.cpp') -Leaf) -eq 'C++ - Multiple test cases.cpp')
    $mainPy = Join-Path $tmp 'main.py'; Set-Content -Path $mainPy -Value 'print(42)'
    Reset-CPPracticeFile -MainCppPath $mainPy -Config $tcfg
    Check 'reset main.py uses the Python template' ((Get-Content $mainPy -Raw) -match 'def main')
    # settings: v3 config migrates to reset-on + dialog; practice files; active = newest
    $old = Join-Path $tmp 'old-config.json'
    Set-Content -Path $old -Value ('{ "MainCppPath": "' + ($main -replace '\\', '\\') + '", "RepoPath": "' + ($repo -replace '\\', '\\') + '", "ResetAfterSave": false, "QuickSaveNotify": "notification", "ConfigVersion": 3 }')
    $mc = Get-CPConfig $old
    Check 'old settings migrate: reset on, message box' ($mc.ResetAfterSave -eq $true -and $mc.QuickSaveNotify -eq 'dialog' -and @($mc.PracticeFiles).Count -eq 1)
    $mc.PracticeFiles = @($main, $mainPy)
    (Get-Item $main).LastWriteTime = (Get-Date).AddMinutes(-5); (Get-Item $mainPy).LastWriteTime = Get-Date
    Check 'active practice file = most recently saved' ((Get-CPActivePracticeFile $mc) -eq (Get-Item $mainPy).FullName)
    Save-CPConfig -Config $mc -Path $old
    $mc2 = Get-CPConfig $old
    Check 'practice files + default templates survive save/load' (@($mc2.PracticeFiles).Count -eq 2 -and $mc2.ResetAfterSave -eq $true)
    # quick save on main.py, then reset with the Python template
    $mc2.AutoFetch = $false
    Set-Content -Path $mainPy -Value "`"`"`"`nProblem Name: Weird Algorithm`nProblem Link: https://cses.fi/problemset/task/1068`n`"`"`"`nn = int(input())`n"
    (Get-Item $mainPy).LastWriteTime = Get-Date
    $qp = Invoke-CPQuickSave -Config $mc2
    Check 'quick save picks main.py and saves CSES/1068_Weird_Algorithm.py' ($qp.Success -and $qp.RelPath -eq 'CSES/1068_Weird_Algorithm.py') ($qp.Summary -join ' / ')
    Check 'quick save reset main.py to the Python template' ((Get-Content $mainPy -Raw) -match 'def main' -and ($qp.Summary -join ' ') -match 'main.py reset')
    $bk2 = Import-CPSolution -Config $mc2 -RelPath 'CSES/1068_Weird_Algorithm.py'
    Check 'loading a .py solution goes into main.py' ((Get-Content $mainPy -Raw) -match 'Weird Algorithm' -and $bk2)

    if ($Online) {
        Write-Host "`n[11] Online lookups" -ForegroundColor Cyan
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
    $env:CPSAVER_DATA_DIR = $oldDataDir
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ("`n{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 } else { exit 0 }
