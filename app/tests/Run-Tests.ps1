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
# git needs a name + email to commit; on a PC (or CI machine) without one, use a test identity
$oldGitGlobal = $env:GIT_CONFIG_GLOBAL
if (-not "$(& git config user.email 2>$null)".Trim() -or -not "$(& git config user.name 2>$null)".Trim()) {
    $env:GIT_CONFIG_GLOBAL = Join-Path $tmp 'test-identity.gitconfig'
    & git config --global user.name 'CP Saver Tests' 2>$null; & git config --global user.email 'tests@example.com' 2>$null
}
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
    Check 'difficulty index has the Medium level (1300)' ($byDiff -match '## Medium')

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

    Write-Host "`n[13] Local-only repo (just 'git init', no GitHub, no commits yet)" -ForegroundColor Cyan
    $local = Join-Path $tmp 'local-only'
    New-Item -ItemType Directory -Path $local | Out-Null
    RunGit $local init -q | Out-Null
    RunGit $local config user.email test@example.com | Out-Null; RunGit $local config user.name tester | Out-Null
    $li = New-CPSolutionInfo -Code $code
    $lr = Save-CPSolution -Info $li -RepoPath $local -Push -UpdateIndexes
    Check 'first save into an empty git init folder succeeds' $lr.Success ($lr.Log -join ' / ')
    Check 'nothing pushed, commit kept locally' ((-not $lr.Pushed) -and (($lr.Log -join ' ') -match 'kept locally'))
    Check 'commit is in the local history' ((RunGit $local log -1 --format=%s) -eq 'Add Codeforces 1234A - Two Arrays')
    Check 'README + indexes created' ((Test-Path (Join-Path $local 'README.md')) -and (Test-Path (Join-Path $local 'Index/BY_TOPIC.md')))
    $lr2 = Save-CPSolution -Info (New-CPSolutionInfo -Code $code) -RepoPath $local -Push -UpdateIndexes
    Check 'saving the same code again = no change' ($lr2.Success -and (($lr2.Log -join ' ') -match 'No changes'))
    Check 'listed in solved problems' (@(Get-CPAllSolutions -RepoPath $local).Count -eq 1)
    Check 'no GitHub link -> no web page offered' ((Get-CPRepoWebUrl $local) -eq $null -and (Get-CPFileWebUrl -RepoPath $local -RelPath 'a/b.cpp') -eq $null)
    Check 'result says not connected' ($lr.NoRemote)
    # no name/email configured anywhere -> clear message, nothing written
    $noId = Join-Path $tmp 'no-identity'
    New-Item -ItemType Directory -Path $noId | Out-Null
    RunGit $noId init -q | Out-Null
    $emptyCfg = Join-Path $tmp 'empty.gitconfig'; Set-Content -Path $emptyCfg -Value ''
    $oldG = $env:GIT_CONFIG_GLOBAL; $oldS = $env:GIT_CONFIG_NOSYSTEM
    $env:GIT_CONFIG_GLOBAL = $emptyCfg; $env:GIT_CONFIG_NOSYSTEM = '1'
    try { $nr = Save-CPSolution -Info (New-CPSolutionInfo -Code $code) -RepoPath $noId }
    finally { $env:GIT_CONFIG_GLOBAL = $oldG; $env:GIT_CONFIG_NOSYSTEM = $oldS }
    Check 'missing git name/email -> clear message' ((-not $nr.Success) -and (($nr.Log -join ' ') -match 'git config --global user.name'))
    Check 'missing git name/email -> nothing written' (-not (Test-Path (Join-Path $noId 'Codeforces')))

    Write-Host "`n[14] First-time setup helpers" -ForegroundColor Cyan
    # an empty folder becomes a repo by itself on the first save
    $fresh = Join-Path $tmp 'brand-new'
    New-Item -ItemType Directory -Path $fresh | Out-Null
    Check 'empty folder detected' ((Test-CPRepoFolder $fresh) -eq 'empty')
    $tmpMain = Join-Path $tmp 'cfgtest-main.cpp'; Set-Content $tmpMain '// x'
    Check 'empty folder is a valid setting' (@(Test-CPConfig @{ PracticeFiles = @($tmpMain); MainCppPath = ''; RepoPath = $fresh }).Count -eq 0)
    $fr = Save-CPSolution -Info (New-CPSolutionInfo -Code $code) -RepoPath $fresh -Push -UpdateIndexes
    Check 'save into an empty folder creates the repo and commits' ($fr.Success -and (Test-Path (Join-Path $fresh '.git')) -and (($fr.Log -join ' ') -match 'Created a new local git repo')) ($fr.Log -join ' / ')
    Check 'new repo uses branch main' ((RunGit $fresh rev-parse --abbrev-ref HEAD) -eq 'main')
    Check 'repo detected' ((Test-CPRepoFolder $fresh) -eq 'repo')
    $withFiles = Join-Path $tmp 'has-files'; New-Item -ItemType Directory -Path $withFiles | Out-Null; Set-Content (Join-Path $withFiles 'x.txt') 'x'
    Check 'folder with files is not used silently' (((Test-CPRepoFolder $withFiles) -eq 'files') -and (-not (Save-CPSolution -Info (New-CPSolutionInfo -Code $code) -RepoPath $withFiles).Success))
    Check 'Initialize-CPRepo keeps existing files' (((Initialize-CPRepo $withFiles) -ne $null) -and (Test-Path (Join-Path $withFiles '.git')) -and (Test-Path (Join-Path $withFiles 'x.txt')))
    # connect a local repo to "GitHub" (a bare repo standing in for it) and upload what was saved
    $gh = Join-Path $tmp 'github-stand-in.git'; RunGit $tmp init -q --bare $gh | Out-Null
    $badUrl = $false; try { Connect-CPGitHub -RepoPath $fresh -Url 'not a link' | Out-Null } catch { $badUrl = $true }
    Check 'connect rejects a non-link' $badUrl
    $up = $false; try { $up = Connect-CPGitHub -RepoPath $fresh -Url $gh } catch { Write-Host "    $($_.Exception.Message)" }
    Check 'connect uploads what was saved locally' ($up -and ((RunGit $gh log -1 --format=%s main) -eq 'Add Codeforces 1234A - Two Arrays'))
    $later = Save-CPSolution -Info (New-CPSolutionInfo -Code ($code -replace 'int main\(\)\{\}', 'int main(){ return 1; }')) -RepoPath $fresh -Push
    Check 'after connecting, saves push' ($later.Success -and $later.Pushed) ($later.Log -join ' / ')
    # git name/email: set once from the app
    $gcfg = Join-Path $tmp 'id.gitconfig'; Set-Content -Path $gcfg -Value ''
    $oldG = $env:GIT_CONFIG_GLOBAL; $oldS = $env:GIT_CONFIG_NOSYSTEM
    $env:GIT_CONFIG_GLOBAL = $gcfg; $env:GIT_CONFIG_NOSYSTEM = '1'
    try {
        Check 'no identity detected' (-not (Get-CPGitIdentity $noId).Ok)
        $bad = $false; try { Set-CPGitIdentity -Name 'A' -Email 'not-an-email' } catch { $bad = $true }
        Check 'bad email rejected' $bad
        $emptyMsg = ''; try { Set-CPGitIdentity -Name 'A' -Email '' } catch { $emptyMsg = $_.Exception.Message }
        Check 'empty email -> friendly message' ($emptyMsg -like 'Enter a valid email*') $emptyMsg
        Set-CPGitIdentity -Name 'Test User' -Email 'test@example.com'
        $id = Get-CPGitIdentity $noId
        Check 'identity saved and read back' ($id.Ok -and $id.Name -eq 'Test User' -and $id.Email -eq 'test@example.com')
        $nr2 = Save-CPSolution -Info (New-CPSolutionInfo -Code $code) -RepoPath $noId
        Check 'save works once the identity is set' $nr2.Success ($nr2.Log -join ' / ')
    } finally { $env:GIT_CONFIG_GLOBAL = $oldG; $env:GIT_CONFIG_NOSYSTEM = $oldS }
    # old .bat launchers next to the project are cleaned up (only ours)
    $proj = Join-Path $tmp 'proj'; $projSrc = Join-Path $proj 'src'; New-Item -ItemType Directory -Path $projSrc -Force | Out-Null
    Set-Content (Join-Path $projSrc 'main.cpp') '// x'
    Set-Content (Join-Path $proj 'my.sln') ''
    Set-Content (Join-Path $proj 'save_solution.bat') "@echo off`r`nstart """" ""C:\x\CPSaverLauncher.exe"" open"
    Set-Content (Join-Path $proj 'quick_save.bat') "@echo off`r`nstart """" wscript.exe ""C:\x\CPSaver.vbs"" -Quick"
    Set-Content (Join-Path $proj 'solved_problems.bat') "@echo off`r`necho this one is the user's own"
    $gone = @(Remove-CPPracticeLaunchers -Config @{ PracticeFiles = @((Join-Path $projSrc 'main.cpp')); MainCppPath = '' })
    Check 'our old launchers removed' (($gone.Count -eq 2) -and -not (Test-Path (Join-Path $proj 'save_solution.bat')) -and -not (Test-Path (Join-Path $proj 'quick_save.bat')))
    Check 'a .bat the user wrote is kept' (Test-Path (Join-Path $proj 'solved_problems.bat'))
    # welcome tour flag
    $tcfgPath = Join-Path $tmp 'tour.json'
    $tc = Get-CPConfig $tcfgPath
    Check 'new install shows the tour once' ($tc.TutorialShown -eq $false)
    $tc.TutorialShown = $true; Save-CPConfig -Config $tc -Path $tcfgPath
    Check 'tour remembered as shown' ((Get-CPConfig $tcfgPath).TutorialShown -eq $true)

    Write-Host "`n[15] Updates" -ForegroundColor Cyan
    Check 'version compare: newer' ((Compare-CPVersion '2.10.0' '2.9.9') -eq 1)
    Check 'version compare: v prefix + missing parts' ((Compare-CPVersion 'v2.5' '2.5.0') -eq 0)
    Check 'version compare: older' ((Compare-CPVersion '2.4.2' '2.5.0') -eq -1)
    $fakeRel = [pscustomobject]@{ tag_name = 'v9.0.0'; body = 'notes'; html_url = 'https://example.com/r'; published_at = '2026-01-01T00:00:00Z'
        assets = @([pscustomobject]@{ name = 'other.zip'; browser_download_url = 'https://example.com/other.zip' }, [pscustomobject]@{ name = 'CP-Solution-Saver.zip'; browser_download_url = 'https://example.com/cp.zip' }) }
    $ri = ConvertTo-CPReleaseInfo $fakeRel
    Check 'release info: version + zip asset' ($ri.Version -eq '9.0.0' -and $ri.ZipUrl -eq 'https://example.com/cp.zip' -and $ri.Page -eq 'https://example.com/r')
    Check 'newer release is offered' (Test-CPUpdateAvailable -Release $ri)
    Check 'skipped version is not offered automatically' (-not (Test-CPUpdateAvailable -Release $ri -SkippedVersion '9.0.0'))
    Check 'skipped version is offered when checking by hand' (Test-CPUpdateAvailable -Release $ri -SkippedVersion '9.0.0' -IgnoreSkipped)
    $same = @{ Version = (Get-CPAppVersion); ZipUrl = 'x'; Notes = ''; Page = '' }
    Check 'same version is not offered' (-not (Test-CPUpdateAvailable -Release $same))
    $env:CPSAVER_CURRENT_VERSION = '1.0.0'
    try { Check 'CPSAVER_CURRENT_VERSION pretends an older install' (Test-CPUpdateAvailable -Release $same) } finally { $env:CPSAVER_CURRENT_VERSION = $null }
    Check 'release without the zip is not offered' (-not (Test-CPUpdateAvailable -Release @{ Version = '99.0'; ZipUrl = ''; Notes = ''; Page = '' }))
    $now = [datetime]'2026-11-23 20:00'
    Check 'check due: never checked' (Test-CPUpdateCheckDue -Config @{ AutoUpdateCheck = $true; LastUpdateCheck = '' } -Now $now)
    Check 'check due: 13 hours ago' (Test-CPUpdateCheckDue -Config @{ AutoUpdateCheck = $true; LastUpdateCheck = '2026-11-23 07:00' } -Now $now)
    Check 'not due: 1 hour ago' (-not (Test-CPUpdateCheckDue -Config @{ AutoUpdateCheck = $true; LastUpdateCheck = '2026-11-23 19:00' } -Now $now))
    Check 'not due: turned off' (-not (Test-CPUpdateCheckDue -Config @{ AutoUpdateCheck = $false; LastUpdateCheck = '' } -Now $now))
    Check 'new settings default to checking' ((Get-CPConfig (Join-Path $tmp 'upd.json')).AutoUpdateCheck -eq $true)

    Write-Host "`n[16] Level, stars, numbers, report" -ForegroundColor Cyan
    Check 'level from rating' ((Get-CPLevel '800') -eq 'Easy' -and (Get-CPLevel '1500') -eq 'Medium' -and (Get-CPLevel '1800') -eq 'Hard')
    Check 'level from words' ((Get-CPLevel 'medium') -eq 'Medium' -and (Get-CPLevel 'EASY') -eq 'Easy')
    Check 'level written by hand wins' ((Get-CPLevel -Difficulty '900' -Level 'Hard') -eq 'Hard')
    Check 'unknown difficulty = no level' ((Get-CPLevel '') -eq '' -and (Get-CPLevel 'Div2 B') -eq '')
    Set-CPLevelCutoffs @{ LevelMediumFrom = 1000; LevelHardFrom = 1400 }
    Check 'cut-offs from the settings' ((Get-CPLevel '1100') -eq 'Medium' -and (Get-CPLevel '1400') -eq 'Hard')
    Set-CPLevelCutoffs @{ LevelMediumFrom = 1200; LevelHardFrom = 1800 }
    Check 'difficulty sort: level, then rating' (((@('1900', 'Easy', '1300', '800', '', 'Hard') | Sort-Object { Get-CPDifficultySortKey $_ }) -join ',') -eq 'Easy,800,1300,Hard,1900,')
    $lv = Join-Path $tmp 'levels'; New-Item -ItemType Directory -Path $lv | Out-Null; Initialize-CPRepo $lv | Out-Null
    RunGit $lv config user.email t@e.com | Out-Null; RunGit $lv config user.name t | Out-Null
    $mk = { param($name, $link, $diff, $date, $extra) "/*`n * Problem Name: $name`n * Problem Link: $link`n * Difficulty: $diff`n * Date Solved: $date`n$extra */`nint main(){}`n" }
    $r1 = Save-CPSolution -Info (New-CPSolutionInfo -Code (& $mk 'Old One' 'https://codeforces.com/problemset/problem/1/A' '1500' '2026-01-05' '')) -RepoPath $lv -UpdateIndexes
    $r2 = Save-CPSolution -Info (New-CPSolutionInfo -Code (& $mk 'Starry' 'https://cses.fi/problemset/task/1068' '' '2026-02-01' " * Level: Medium`n * Starred: yes`n")) -RepoPath $lv -UpdateIndexes
    $r3 = Save-CPSolution -Info (New-CPSolutionInfo -Code (& $mk 'Newest' 'https://leetcode.com/problems/two-sum/' 'Easy' '2026-03-01' '')) -RepoPath $lv -UpdateIndexes
    $py = "`"`"`"`nProblem Name: Old One`nProblem Link: https://codeforces.com/contest/1/problem/A`nDifficulty: 1500`nDate Solved: 2026-04-01`n`"`"`"`nprint(1)`n"
    $r4 = Save-CPSolution -Info (New-CPSolutionInfo -Code $py -Extension '.py') -RepoPath $lv -UpdateIndexes
    Check 'saves with level and star' ($r1.Success -and $r2.Success -and $r3.Success -and $r4.Success)
    $txt1 = Read-CPTextFile (Join-Path $lv $r1.RelPath)
    Check 'level written into the header' ($txt1 -match 'Level: Medium')
    $sols = @(Get-CPAllSolutions $lv)
    $old = @($sols | Where-Object { $_.Name -eq 'Old One' })
    Check 'numbers follow the solve order' ((($sols | Where-Object { $_.Name -eq 'Starry' }).Number -eq 2) -and (($sols | Where-Object { $_.Name -eq 'Newest' }).Number -eq 3))
    Check 'same problem in two languages shares a number' ($old.Count -eq 2 -and $old[0].Number -eq 1 -and $old[1].Number -eq 1)
    $starry = $sols | Where-Object { $_.Name -eq 'Starry' }
    Check 'star and hand-written level read back' ($starry.Starred -and $starry.Level -eq 'Medium')
    # saving again without "Starred" in the header keeps the star and the level chosen by hand
    $r2b = Save-CPSolution -Info (New-CPSolutionInfo -Code (& $mk 'Starry' 'https://cses.fi/problemset/task/1068' '' '2026-02-01' '').Replace('int main(){}', 'int main(){ return 0; }')) -RepoPath $lv -UpdateIndexes
    $starry = Get-CPAllSolutions $lv | Where-Object { $_.Name -eq 'Starry' }
    Check 're-save keeps the star and the level' ($r2b.Success -and $r2b.IsUpdate -and $starry.Starred -and $starry.Level -eq 'Medium')
    $us = Set-CPStarred -RepoPath $lv -RelPath $starry.RelPath -Starred $false -UpdateIndexes
    Check 'unstar from the list commits' ($us.Success -and -not (Get-CPAllSolutions $lv | Where-Object { $_.Name -eq 'Starry' }).Starred -and (RunGit $lv log -1 --format=%s) -like 'Unstar *')
    $ss = Set-CPStarred -RepoPath $lv -RelPath $r3.RelPath -Starred $true -UpdateIndexes
    $readme = Read-CPTextFile (Join-Path $lv 'README.md')
    Check 'README lists starred problems and levels' ($ss.Success -and $readme -match '### Starred' -and $readme -match 'By level:')
    $byDiff = Read-CPTextFile (Join-Path $lv 'Index/BY_DIFFICULTY.md')
    Check 'difficulty index grouped by level, with numbers' ($byDiff -match '## Medium' -and $byDiff -match '\| # \| Problem')
    Check 'old headers: "Level: 1500" counts as the difficulty' ((New-CPSolutionInfo -Code "/*`n * Problem Name: X`n * Problem Link: https://x.com/1`n * Level: 1500`n */`n").Difficulty -eq '1500')
    $rd = Get-CPReportData -RepoPath $lv -Today ([datetime]'2026-03-02')
    Check 'report data: problems counted once' ($rd.Total -eq 3 -and $rd.Files -eq 4)
    Check 'report data: streaks' ($rd.LongestStreak -ge 1 -and $rd.CurrentStreak -eq 1)
    $rp = Save-CPReport -RepoPath $lv -Path (Join-Path $tmp 'report.html')
    $html = [IO.File]::ReadAllText($rp)
    Check 'report page is written' ((Test-Path $rp) -and $html -match '<svg' -and $html -match 'Problem solving report' -and $html -match 'Starred')
    $bars = New-CPSvgHBars -Rows @(@{ Label = 'a'; Value = 1 }, @{ Label = 'b'; Value = 4 }) -Width 400 -LabelWidth 100
    $widths = @([regex]::Matches($bars, 'x="100" y="\d+" width="([\d.]+)"') | ForEach-Object { [double]$_.Groups[1].Value })
    Check 'chart bars are scaled to the values (PS 5.1 too)' ($widths.Count -eq 2 -and [Math]::Abs($widths[1] - 4 * $widths[0]) -lt 1) ($widths -join ',')
    $emptyRepo = Join-Path $tmp 'empty-report'; New-Item -ItemType Directory -Path $emptyRepo | Out-Null; Initialize-CPRepo $emptyRepo | Out-Null
    $er = $null; try { $er = New-CPReportHtml -RepoPath $emptyRepo } catch { Write-Host "    $($_.Exception.Message)" }
    Check 'report works with no solutions yet' ($er -and $er -match 'Nothing yet')

    if ($Online) {
        Write-Host "`n[11] Online lookups" -ForegroundColor Cyan
        $cf = Get-CPProblemMetadata 'https://codeforces.com/problemset/problem/4/A'
        Check 'Codeforces 4A -> Watermelon, 800, tags' ($cf.Ok -and $cf.Name -eq 'Watermelon' -and $cf.Difficulty -eq '800' -and @($cf.Topics).Count -gt 0) $cf.Message
        $lcm = Get-CPProblemMetadata 'https://leetcode.com/problems/two-sum/'
        Check 'LeetCode two-sum -> 0001 Two Sum Easy' ($lcm.Ok -and $lcm.Name -eq 'Two Sum' -and $lcm.Id -eq '0001' -and $lcm.Difficulty -eq 'Easy') $lcm.Message
        $cs = Get-CPProblemMetadata 'https://cses.fi/problemset/task/1068'
        Check 'CSES 1068 -> Weird Algorithm' ($cs.Ok -and $cs.Name -eq 'Weird Algorithm') $cs.Message
        $lr = $null; try { $lr = Get-CPLatestRelease } catch { Write-Host "    $($_.Exception.Message)" }
        Check 'latest release found on GitHub' ($lr -and $lr.Version -and $lr.ZipUrl) "$($lr.Version) $($lr.ZipUrl)"
        if ($lr -and $lr.ZipUrl) {
            $inst = $null; try { $inst = Save-CPUpdatePackage -Release $lr } catch { Write-Host "    $($_.Exception.Message)" }
            Check 'update package downloads and contains the installer' ($inst -and (Test-Path $inst)) "$inst"
            if ($inst) { Remove-Item -LiteralPath (Split-Path (Split-Path (Split-Path $inst -Parent) -Parent) -Parent) -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $ac = Get-CPProblemMetadata 'https://atcoder.jp/contests/abc086/tasks/abc086_a'
        Check 'AtCoder abc086_a -> Product' ($ac.Ok -and $ac.Name -eq 'Product') "$($ac.Message) name='$($ac.Name)'"
    }
}
finally {
    $env:CPSAVER_DATA_DIR = $oldDataDir
    $env:GIT_CONFIG_GLOBAL = $oldGitGlobal
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# Every button in the windows must do something (a missing click handler is easy to miss)
Write-Host "`n[12] GUI buttons are wired" -ForegroundColor Cyan
foreach ($sf in @('CPSaver.ps1', 'CPSaver.Gui.ps1', 'CPSaver.Tray.ps1', 'CPSaver.Core.psm1', '..\install.ps1', '..\uninstall.ps1', '..\tools\New-Release.ps1')) {
    $perr = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $SrcDir $sf), [ref]$null, [ref]$perr)
    Check "$sf has no syntax errors" (@($perr).Count -eq 0) ((@($perr) | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')
}
$guiText = Get-Content -Raw -LiteralPath (Join-Path $SrcDir 'CPSaver.Gui.ps1')
foreach ($m in [regex]::Matches($guiText, '\$ui\.(\w+) = New-CPButton')) {
    $bn = $m.Groups[1].Value
    Check "button '$bn' has a click handler" ($guiText -match ('\$ui\.' + $bn + '\.Add_Click'))
}
$guiOnly = $guiText -replace '(?ms)^function Write-CPGuiTrace.*?^}', ''
Check "the GUI file calls Write-CPTrace only behind a check (it lives in the tray file)" (-not ([regex]::Matches($guiOnly, '(?m)^(?!.*Get-Command Write-CPTrace).*\bWrite-CPTrace\b').Count))
Check "'Check for updates' button in the save window and in Settings" ((([regex]::Matches($guiText, "New-CPButton 'Check for updates'")).Count -ge 2) -and (([regex]::Matches($guiText, 'Invoke-CPUpdateCheck -Owner \$f')).Count -ge 2))

Write-Host ("`n{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 } else { exit 0 }
