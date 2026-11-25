#Requires -Version 5.1
<#
    CPSaver.Core.psm1
    Core logic for CP Solution Saver (no UI code here, so it can be tested and
    used from the command line).

    Works on Windows PowerShell 5.1 (built into Windows 10/11) and PowerShell 7.
#>

# ----------------------------------------------------------------------------
#  Paths and configuration
# ----------------------------------------------------------------------------

$script:AppName    = 'CPSolutionSaver'
$script:AppVersion = '2.8.0'

function Get-CPAppVersion { $script:AppVersion }

function Get-CPDataDir {
    # CPSAVER_DATA_DIR lets the self-tests use a temporary folder instead of %APPDATA%
    if ($env:CPSAVER_DATA_DIR) {
        if (-not (Test-Path $env:CPSAVER_DATA_DIR)) { New-Item -ItemType Directory -Path $env:CPSAVER_DATA_DIR -Force | Out-Null }
        return $env:CPSAVER_DATA_DIR
    }
    $base = [Environment]::GetFolderPath('ApplicationData')
    if (-not $base) { $base = Join-Path $HOME '.config' }
    $dir = Join-Path $base $script:AppName
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-CPDefaultConfigPath { Join-Path (Get-CPDataDir) 'config.json' }

function Get-CPDefaultConfig {
    [ordered]@{
        MainCppPath      = ''        # the active practice file (kept for older versions; see PracticeFiles)
        PracticeFiles    = @()       # one practice file per language, e.g. main.cpp, main.c, main.py
        RepoPath         = ''
        TemplatePath     = (Join-Path (Get-CPDataDir) 'template.cpp')   # legacy (v2.0); templates now live in templates\
        DefaultTemplates = [ordered]@{}   # extension -> template name used by "Reset after saving"
        AutoFetch        = $true
        PushAfterSave    = $true
        ResetAfterSave   = $true
        CloseAfterSave   = $true     # close the window after a successful save
        UpdateIndexes    = $true
        QuickSaveNotify  = 'dialog'  # 'dialog' (message box in the middle of the screen) or 'notification'
        BackupsToKeep    = 30
        TutorialShown    = $false    # the welcome tour is shown once, on first run
        AutoUpdateCheck  = $true     # look for a newer release on GitHub now and then (asks before updating)
        LevelMediumFrom  = 1200      # numeric ratings: below this = Easy
        LevelHardFrom    = 1800      # ... below this = Medium, this and above = Hard
        BrowserSort      = 'Num DESC' # last sort in Solved problems (column + ASC/DESC)
        CodeViewerDark   = $false     # code viewer: dark colours
        CodeViewerLineNumbers = $true # code viewer: line numbers
        LastUpdateCheck  = ''        # 'yyyy-MM-dd HH:mm' of the last automatic check
        SkippedVersion   = ''        # "Skip this version" in the update window
        ConfigVersion    = 4
    }
}

function Get-CPConfig {
    param([string]$Path = (Get-CPDefaultConfigPath))
    $cfg = Get-CPDefaultConfig
    $oldVersion = 4
    if (Test-Path $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            $oldVersion = 1
            foreach ($p in $raw.PSObject.Properties) {
                if ($p.Name -eq 'DefaultTemplates') {
                    $d = [ordered]@{}
                    if ($p.Value) { foreach ($q in $p.Value.PSObject.Properties) { $d[$q.Name] = [string]$q.Value } }
                    $cfg.DefaultTemplates = $d
                } elseif ($p.Name -eq 'PracticeFiles') {
                    $cfg.PracticeFiles = @($p.Value | Where-Object { $_ } | ForEach-Object { [string]$_ })
                } else { $cfg[$p.Name] = $p.Value }
            }
            if ($raw.PSObject.Properties['ConfigVersion']) { $oldVersion = [int]$raw.ConfigVersion }
        } catch {
            Write-Warning "Could not read config $Path : $($_.Exception.Message). Using defaults."
        }
    }
    if ($oldVersion -lt 4) {
        # v2.2: reset after saving and the centered message box became the defaults
        $cfg.ResetAfterSave = $true
        $cfg.QuickSaveNotify = 'dialog'
        $cfg.ConfigVersion = 4
    }
    # older configs only had MainCppPath
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($f in @($cfg.PracticeFiles) + @($cfg.MainCppPath)) {
        if ($f -and -not ($list | Where-Object { $_ -ieq $f })) { $list.Add([string]$f) }
    }
    $cfg.PracticeFiles = $list.ToArray()
    $active = Get-CPActivePracticeFile $cfg
    if ($active) { $cfg.MainCppPath = $active }
    Set-CPLevelCutoffs $cfg
    return $cfg
}

function Save-CPConfig {
    param([Parameter(Mandatory)]$Config, [string]$Path = (Get-CPDefaultConfigPath))
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $copy = [ordered]@{}
    foreach ($k in $Config.Keys) { $copy[$k] = $Config[$k] }
    $copy.PracticeFiles = @($Config.PracticeFiles)
    $copy.DefaultTemplates = [pscustomobject]$Config.DefaultTemplates
    $json = ([pscustomobject]$copy) | ConvertTo-Json -Depth 5
    Write-CPTextFile -Path $Path -Text $json
}

function Get-CPActivePracticeFile {
    <# The practice file saved most recently (that's the one you just worked on). #>
    param([Parameter(Mandatory)]$Config)
    $files = @(@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object LastWriteTime -Descending)
    if ($files.Count) { return $files[0].FullName }
    return $null
}

function Get-CPPracticeFileFor {
    <# The configured practice file for an extension (.cpp, .c, .py ...), or $null. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Extension)
    $lang = Get-CPLanguage $Extension
    foreach ($f in @($Config.PracticeFiles) + @($Config.MainCppPath)) {
        if ($f -and ((Get-CPLanguage $f).Name -eq $lang.Name)) { return $f }
    }
    return $null
}

function Remove-CPPracticeLaunchers {
    <# Deletes save_solution.bat / quick_save.bat / solved_problems.bat that older versions put next to
       the practice project (only files this app wrote: they start CPSaverLauncher.exe or CPSaver.vbs). Returns the deleted paths. #>
    param([Parameter(Mandatory)]$Config)
    $removed = New-Object System.Collections.Generic.List[string]
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($pf in @(@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ })) {
        $d = Split-Path $pf -Parent
        for ($i = 0; $i -lt 3 -and $d; $i++) { if (-not ($dirs -contains $d)) { $dirs.Add($d) }; $d = Split-Path $d -Parent }
    }
    foreach ($d in $dirs) {
        foreach ($n in @('save_solution.bat', 'quick_save.bat', 'solved_problems.bat')) {
            $f = Join-Path $d $n
            if (-not (Test-Path -LiteralPath $f)) { continue }
            try {
                if ((Get-Content -LiteralPath $f -Raw) -match 'CPSaverLauncher\.exe|CPSaver\.vbs') { Remove-Item -LiteralPath $f -Force; $removed.Add($f) }
            } catch { }
        }
    }
    return $removed.ToArray()
}

function Test-CPConfig {
    <# Returns a list of problems with the config (empty list = OK). #>
    param([Parameter(Mandatory)]$Config)
    $problems = New-Object System.Collections.Generic.List[string]
    $existing = @(@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($existing.Count -eq 0) {
        $problems.Add("No practice file found (main.cpp / main.c / main.py): '$((@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ }) -join "', '")'")
    }
    switch (Test-CPRepoFolder $Config.RepoPath) {
        'none'  { $problems.Add('Choose a folder for your solutions (an empty folder is fine - it becomes a new repo).') }
        'files' { $problems.Add("Solutions folder is not a git repository and is not empty: '$($Config.RepoPath)'") }
    }
    return $problems.ToArray()
}

# ----------------------------------------------------------------------------
#  File helpers (UTF-8 without BOM, keep the file's own line endings)
# ----------------------------------------------------------------------------

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-CPTextFile {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
}

function Write-CPTextFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $dir = Split-Path $full -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($full, $Text, $script:Utf8NoBom)
}

function Get-CPNewline {
    param([string]$Text)
    if ($Text -match "`r`n") { return "`r`n" }
    if ($Text -match "`n")   { return "`n" }
    return [Environment]::NewLine
}

# ----------------------------------------------------------------------------
#  Problem header
# ----------------------------------------------------------------------------
#  /*
#   * Problem Name: Watermelon
#   * Problem Link: https://codeforces.com/problemset/problem/4/A
#   * Platform: Codeforces          (optional, detected from link)
#   * Difficulty: 800               (optional, fetched for Codeforces/LeetCode)
#   * Topics: math, brute force     (optional, comma separated, fetched too)
#   * Notes: anything
#   */

$script:CanonicalKeys = [ordered]@{
    'problem name' = 'Problem Name'; 'name' = 'Problem Name'; 'title' = 'Problem Name'
    'problem link' = 'Problem Link'; 'link' = 'Problem Link'; 'url' = 'Problem Link'; 'problem url' = 'Problem Link'
    'platform'     = 'Platform';     'judge' = 'Platform';    'site' = 'Platform'
    'problem id'   = 'Problem ID';   'id' = 'Problem ID'
    'difficulty'   = 'Difficulty';   'rating' = 'Difficulty'
    'level'        = 'Level'
    'starred'      = 'Starred';      'star' = 'Starred';      'favorite' = 'Starred'; 'favourite' = 'Starred'
    'topics'       = 'Topics';       'topic' = 'Topics';      'tags' = 'Topics'; 'tag' = 'Topics'
    'date solved'  = 'Date Solved';  'date' = 'Date Solved';  'solved' = 'Date Solved'
    'notes'        = 'Notes';        'note' = 'Notes';        'comments' = 'Notes'
}
$script:HeaderOrder = @('Problem Name', 'Problem Link', 'Platform', 'Problem ID', 'Difficulty', 'Level', 'Topics', 'Date Solved', 'Starred', 'Notes')

# ----------------------------------------------------------------------------
#  Level (Easy / Medium / Hard) and stars
# ----------------------------------------------------------------------------
#  Level comes from the header's "Level:" when set, otherwise from the difficulty: LeetCode-style
#  words are used as they are, numeric ratings (Codeforces style) are grouped by two cut-offs.
$script:LevelMediumFrom = 1200
$script:LevelHardFrom = 1800

function Set-CPLevelCutoffs {
    <# Uses the config's cut-offs (LevelMediumFrom / LevelHardFrom) for numeric ratings. #>
    param($Config)
    if ($Config -and [int]$Config.LevelMediumFrom -gt 0) { $script:LevelMediumFrom = [int]$Config.LevelMediumFrom }
    if ($Config -and [int]$Config.LevelHardFrom -gt 0) { $script:LevelHardFrom = [int]$Config.LevelHardFrom }
}

function ConvertTo-CPLevelName([string]$Text) {
    <# 'easy' / 'Medium ' / 'HARD' -> 'Easy' / 'Medium' / 'Hard'; anything else -> '' #>
    switch -Regex (([string]$Text).Trim()) {
        '^(?i)(easy|beginner|basic|school)$' { return 'Easy' }
        '^(?i)(medium|mid|intermediate)$'    { return 'Medium' }
        '^(?i)(hard|expert|difficult)$'      { return 'Hard' }
    }
    return ''
}

function Get-CPRatingNumber([string]$Difficulty) {
    <# The numeric rating in a difficulty ("1200", "Rating 1200", "r1200") or 0. #>
    $m = [regex]::Match(([string]$Difficulty).Trim(), '^(?:rating\s*:?\s*|r\s*)?(\d{3,4})$', 'IgnoreCase')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-CPLevel {
    <# Easy / Medium / Hard from a difficulty: words as they are, ratings by the cut-offs; '' if unknown. #>
    param([string]$Difficulty, [string]$Level = '')
    $l = ConvertTo-CPLevelName $Level
    if ($l) { return $l }
    $w = ConvertTo-CPLevelName $Difficulty
    if ($w) { return $w }
    $n = Get-CPRatingNumber $Difficulty
    if ($n -ge 100) {
        if ($n -lt $script:LevelMediumFrom) { return 'Easy' }
        if ($n -lt $script:LevelHardFrom) { return 'Medium' }
        return 'Hard'
    }
    return ''
}

function Get-CPLevelRank([string]$Level) {
    switch ($Level) { 'Easy' { return 1 } 'Medium' { return 2 } 'Hard' { return 3 } }
    return 9
}

function Get-CPDifficultySortKey {
    <# Sorts by level, then rating, then text: Easy 800 < Easy 1100 < Medium < Hard < unrated. #>
    param([string]$Difficulty, [string]$Level = '')
    $lv = Get-CPLevel -Difficulty $Difficulty -Level $Level
    return ('{0}{1:D5}{2}' -f (Get-CPLevelRank $lv), (Get-CPRatingNumber $Difficulty), ([string]$Difficulty).ToLowerInvariant())
}

function Test-CPTruthy([string]$Value) {
    <# "yes" / "true" / "1" / "*" / "y" -> $true #>
    return (([string]$Value).Trim() -match '^(?i)(yes|y|true|1|\*|x)$')
}


function Get-CPCanonicalKey([string]$Key) {
    $k = ($Key.Trim() -replace '\s+', ' ').ToLowerInvariant()
    if ($script:CanonicalKeys.Contains($k)) { return $script:CanonicalKeys[$k] }
    return $null
}

function Read-CPHeaderLines {
    <# Parses "Key: value" lines (comment markers already removed). Returns @{ Fields; SawKnown }. #>
    param([string[]]$Lines, [string]$Newline)
    $fields = [ordered]@{}
    $lastKey = $null
    $sawKnown = $false
    foreach ($line in $Lines) {
        if ($line.Trim() -eq '') { continue }
        $km = [regex]::Match($line, '^\s*([A-Za-z][A-Za-z ]{0,29}?)\s*:\s?(.*)$')
        if ($km.Success -and $km.Groups[1].Value -notmatch '^(https?|ftp)$') {
            $canon = Get-CPCanonicalKey $km.Groups[1].Value
            $key = if ($canon) { $canon } else { $km.Groups[1].Value.Trim() }
            if ($canon) { $sawKnown = $true }
            # a "Key:" that is really a continuation (e.g. "Idea: ...") after Notes stays in Notes
            if (-not $canon -and $lastKey -eq 'Notes') {
                $fields['Notes'] = ($fields['Notes'] + $Newline + $line.Trim()).Trim()
                continue
            }
            $fields[$key] = $km.Groups[2].Value.Trim()
            $lastKey = $key
        } elseif ($lastKey) {
            $fields[$lastKey] = ($fields[$lastKey] + $Newline + $line.Trim()).Trim()
        }
    }
    return @{ Fields = $fields; SawKnown = $sawKnown }
}

function Read-CPHeader {
    <#
      Parses the problem header at the top of a source file. Accepted forms:
        /* ... */                 (C, C++, Java, ...)
        """ ... """ or ''' '''    (Python docstring)
        consecutive // or # comment lines
      An optional #! line before it is kept (Prefix).
      Returns @{ Fields = [ordered] key->value ; HasHeader ; Body ; Newline ; Prefix ; Style }
      Unknown "Key: value" lines are kept as extra fields; lines without a key
      continue the previous field (multi-line notes).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Code)

    $nl = Get-CPNewline $Code
    $none = @{ Fields = [ordered]@{}; HasHeader = $false; Body = $Code; Newline = $nl; Prefix = ''; Style = '' }
    $text = $Code.TrimStart([char]0xFEFF)
    $prefix = ''
    $pm = [regex]::Match($text, '^(#![^\r\n]*\r?\n)')
    if ($pm.Success) { $prefix = $pm.Groups[1].Value; $text = $text.Substring($pm.Length) }

    $style = ''; $inner = $null; $consumed = 0
    $m = [regex]::Match($text, '^\s*/\*(.*?)\*/[ \t]*\r?\n?', 'Singleline')
    if ($m.Success) {
        $style = 'block'; $consumed = $m.Length
        $inner = @($m.Groups[1].Value -split "\r?\n" | ForEach-Object { $_ -replace '^\s*\*?[ \t]?', '' })
    }
    if (-not $style) {
        $m = [regex]::Match($text, '^\s*("""|' + "'''" + ')(.*?)\1[ \t]*\r?\n?', 'Singleline')
        if ($m.Success) {
            $style = 'docstring'; $consumed = $m.Length
            $inner = @($m.Groups[2].Value -split "\r?\n" | ForEach-Object { $_ -replace '^\s*[#*]?[ \t]?', '' })
        }
    }
    if (-not $style) {
        # // lines, or # lines that are not C preprocessor directives (#include, #define, ...)
        $m = [regex]::Match($text, '^(?:[ \t]*(?://|#(?!\s*(?:include|define|pragma|ifn?def|if|endif|else|elif|undef|import|error|line)\b))[^\r\n]*(?:\r?\n|$))+')
        if ($m.Success) {
            $style = 'line'; $consumed = $m.Length
            $inner = @($m.Value -split "\r?\n" | ForEach-Object { $_ -replace '^\s*(//+|#+)[ \t]?', '' })
        }
    }
    if (-not $style) { return $none }

    $parsed = Read-CPHeaderLines -Lines $inner -Newline $nl
    if (-not $parsed.SawKnown) { return $none }   # a normal comment, not our header
    return @{ Fields = $parsed.Fields; HasHeader = $true; Body = $text.Substring($consumed); Newline = $nl; Prefix = $prefix; Style = $style }
}

function Get-CPLanguage {
    <# Language info from a file name or extension: @{ Name; Ext; Style ('block' | 'python') } #>
    param([string]$PathOrExt)
    $ext = if ($PathOrExt -match '^\.\w+$') { $PathOrExt } else { [IO.Path]::GetExtension([string]$PathOrExt) }
    $ext = ([string]$ext).ToLowerInvariant()
    switch ($ext) {
        '.cpp'  { return @{ Name = 'C++'; Ext = '.cpp'; Style = 'block' } }
        '.cc'   { return @{ Name = 'C++'; Ext = '.cc'; Style = 'block' } }
        '.cxx'  { return @{ Name = 'C++'; Ext = '.cxx'; Style = 'block' } }
        '.c'    { return @{ Name = 'C'; Ext = '.c'; Style = 'block' } }
        '.py'   { return @{ Name = 'Python'; Ext = '.py'; Style = 'python' } }
        '.java' { return @{ Name = 'Java'; Ext = '.java'; Style = 'block' } }
        '.js'   { return @{ Name = 'JavaScript'; Ext = '.js'; Style = 'block' } }
        '.cs'   { return @{ Name = 'C#'; Ext = '.cs'; Style = 'block' } }
        '.kt'   { return @{ Name = 'Kotlin'; Ext = '.kt'; Style = 'block' } }
        '.go'   { return @{ Name = 'Go'; Ext = '.go'; Style = 'block' } }
        '.rs'   { return @{ Name = 'Rust'; Ext = '.rs'; Style = 'block' } }
    }
    if ($ext) { return @{ Name = $ext.TrimStart('.').ToUpper(); Ext = $ext; Style = 'block' } }
    return @{ Name = 'C++'; Ext = '.cpp'; Style = 'block' }
}

function Get-CPSourceExtensions { @('.cpp', '.cc', '.cxx', '.c', '.py', '.java', '.js', '.cs', '.kt', '.go', '.rs') }

function ConvertTo-CPHeader {
    <# -Style 'block' => /* ... */ ; 'python' => """ ... """ #>
    param([Parameter(Mandatory)]$Fields, [string]$Newline = "`r`n", [string]$Style = 'block')
    $py = ($Style -eq 'python')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($(if ($py) { '"""' } else { '/*' }))
    $lead = if ($py) { '' } else { ' * ' }
    $cont = if ($py) { '    ' } else { ' *   ' }
    $keys = @($script:HeaderOrder | Where-Object { $Fields.Contains($_) })
    $keys += @($Fields.Keys | Where-Object { $script:HeaderOrder -notcontains $_ })
    foreach ($k in $keys) {
        $v = [string]$Fields[$k]
        if ($v -eq '' -and $k -notin @('Problem Name', 'Problem Link', 'Topics', 'Difficulty', 'Level', 'Notes')) { continue }
        $parts = $v -split "\r?\n"
        $lines.Add(("{0}{1}: {2}" -f $lead, $k, $parts[0]).TrimEnd())
        for ($i = 1; $i -lt $parts.Count; $i++) { $lines.Add(($cont + $parts[$i]).TrimEnd()) }
    }
    $lines.Add($(if ($py) { '"""' } else { ' */' }))
    return ($lines -join $Newline)
}

function Get-CPProblemKey {
    <#
      A stable identity for a problem, from its link: different spellings of
      the same problem give the same key (e.g. codeforces.com/contest/4/problem/A
      and codeforces.com/problemset/problem/4/A -> 'codeforces:4A').
    #>
    param([string]$Link)
    if (-not $Link -or -not $Link.Trim()) { return '' }
    $pi = Get-CPPlatformInfo $Link
    switch ($pi.Platform) {
        'Codeforces' { if ($pi.Id) { return 'codeforces:' + $pi.Id.ToUpperInvariant() } }
        'LeetCode'   { if ($pi.Slug) { return 'leetcode:' + $pi.Slug } }
        'AtCoder'    { if ($pi.Id) { return 'atcoder:' + $pi.Id.ToLowerInvariant() } }
        'CSES'       { if ($pi.Id) { return 'cses:' + $pi.Id } }
        'SPOJ'       { if ($pi.Id) { return 'spoj:' + $pi.Id } }
        'CodeChef'   { if ($pi.Id) { return 'codechef:' + $pi.Id } }
        'Kattis'     { if ($pi.Id) { return 'kattis:' + $pi.Id.ToLowerInvariant() } }
        'HackerRank' { if ($pi.Slug) { return 'hackerrank:' + $pi.Slug.ToLowerInvariant() } }
        'VJudge'     { if ($pi.Id) { return 'vjudge:' + $pi.Id.ToLowerInvariant() } }
    }
    $u = ($Link.Trim() -replace '[#?].*$', '') -replace '^https?://(www\.)?', ''
    $u = $u -replace '/+(description|problem|submissions|editorial)?/*$', ''
    return 'url:' + $u.TrimEnd('/').ToLowerInvariant()
}

# ----------------------------------------------------------------------------
#  Platform detection
# ----------------------------------------------------------------------------

function Get-CPPlatformInfo {
    <# Returns @{ Platform; Id; Slug; ContestId; Index } from a problem URL. #>
    param([string]$Link)
    $r = @{ Platform = 'Other'; Id = ''; Slug = ''; ContestId = ''; Index = '' }
    if (-not $Link) { return $r }
    $l = $Link.Trim()

    $m = [regex]::Match($l, 'codeforces\.com/(?:contest|gym)/(\d+)/problem/([A-Za-z0-9]+)', 'IgnoreCase')
    if (-not $m.Success) { $m = [regex]::Match($l, 'codeforces\.com/problemset/problem/(\d+)/([A-Za-z0-9]+)', 'IgnoreCase') }
    if ($m.Success) { $r.Platform = 'Codeforces'; $r.ContestId = $m.Groups[1].Value; $r.Index = $m.Groups[2].Value.ToUpper(); $r.Id = $r.ContestId + $r.Index; return $r }
    if ($l -match 'codeforces\.com') { $r.Platform = 'Codeforces'; return $r }

    $m = [regex]::Match($l, 'leetcode\.(?:com|cn)/problems/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'LeetCode'; $r.Slug = $m.Groups[1].Value.ToLower(); return $r }

    $m = [regex]::Match($l, 'atcoder\.jp/contests/([\w-]+)/tasks/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'AtCoder'; $r.ContestId = $m.Groups[1].Value; $r.Id = $m.Groups[2].Value; return $r }

    $m = [regex]::Match($l, 'cses\.fi/(?:problemset|alon)/task/(\d+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'CSES'; $r.Id = $m.Groups[1].Value; return $r }

    $m = [regex]::Match($l, 'spoj\.com/problems/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'SPOJ'; $r.Id = $m.Groups[1].Value.ToUpper(); return $r }

    $m = [regex]::Match($l, 'codechef\.com/(?:[\w-]+/)?problems/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'CodeChef'; $r.Id = $m.Groups[1].Value.ToUpper(); return $r }

    $m = [regex]::Match($l, 'open\.kattis\.com/(?:contests/\w+/)?problems/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'Kattis'; $r.Id = $m.Groups[1].Value; return $r }

    $m = [regex]::Match($l, 'hackerrank\.com/(?:challenges|contests/[\w-]+/challenges)/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'HackerRank'; $r.Slug = $m.Groups[1].Value; return $r }

    $m = [regex]::Match($l, 'vjudge\.net/problem/([\w-]+)', 'IgnoreCase')
    if ($m.Success) { $r.Platform = 'VJudge'; $r.Id = $m.Groups[1].Value; return $r }
    if ($l -match 'vjudge\.net') { $r.Platform = 'VJudge'; return $r }

    if ($l -match 'onlinejudge\.org|uva\.onlinejudge') { $r.Platform = 'UVa'; return $r }
    if ($l -match 'eolymp\.com/\w+/problems/(\d+)') { $r.Platform = 'Eolymp'; $r.Id = $Matches[1]; return $r }
    return $r
}

function Get-CPKnownPlatforms {
    @('Codeforces', 'AtCoder', 'LeetCode', 'CSES', 'CodeChef', 'SPOJ', 'Kattis', 'HackerRank', 'VJudge', 'UVa', 'Eolymp', 'Other')
}

# ----------------------------------------------------------------------------
#  Online metadata (name, difficulty, topics)
# ----------------------------------------------------------------------------

function Initialize-CPWeb {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-CPPageTitle {
    param([string]$Url, [int]$TimeoutSec = 8)
    Initialize-CPWeb
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -Headers @{ 'User-Agent' = 'Mozilla/5.0 CPSolutionSaver' }
    $m = [regex]::Match($resp.Content, '<title[^>]*>(.*?)</title>', 'Singleline,IgnoreCase')
    if ($m.Success) { return [Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim() -replace '\s+', ' ' }
    return ''
}

function Get-CPProblemMetadata {
    <#
      Looks the problem up online (one retry if the site times out). Never
      throws: returns @{ Ok; Name; Id; Difficulty; Topics (string[]); Message }.
    #>
    param([string]$Link, [int]$TimeoutSec = 12)
    $r = Get-CPProblemMetadataOnce -Link $Link -TimeoutSec $TimeoutSec
    if (-not $r.Ok -and $r.Message -match 'timed out|timeout|unable to connect|underlying connection') {
        Start-Sleep -Milliseconds 500
        $r = Get-CPProblemMetadataOnce -Link $Link -TimeoutSec ($TimeoutSec + 8)
    }
    return $r
}

function Get-CPProblemMetadataOnce {
    param([string]$Link, [int]$TimeoutSec = 12)
    $res = @{ Ok = $false; Name = ''; Id = ''; Difficulty = ''; Topics = @(); Message = '' }
    if (-not $Link) { $res.Message = 'No link.'; return $res }
    $info = Get-CPPlatformInfo $Link
    Initialize-CPWeb
    try {
        switch ($info.Platform) {
            'Codeforces' {
                if (-not $info.ContestId) { throw 'Could not read contest/problem from the link.' }
                $p = Get-CPCodeforcesProblem -ContestId $info.ContestId -Index $info.Index -TimeoutSec $TimeoutSec
                $res.Name = $p.name
                $res.Id = $info.Id
                if ($p.rating) { $res.Difficulty = [string]$p.rating }
                $res.Topics = @($p.tags | Where-Object { $_ -and -not $_.StartsWith('*') })
            }
            'LeetCode' {
                $q = @{
                    query     = 'query q($titleSlug: String!) { question(titleSlug: $titleSlug) { questionFrontendId title difficulty topicTags { name } } }'
                    variables = @{ titleSlug = $info.Slug }
                } | ConvertTo-Json -Depth 5
                $j = Invoke-RestMethod -Uri 'https://leetcode.com/graphql' -Method Post -Body $q -ContentType 'application/json' -TimeoutSec $TimeoutSec `
                    -Headers @{ 'Referer' = "https://leetcode.com/problems/$($info.Slug)/"; 'User-Agent' = 'Mozilla/5.0 CPSolutionSaver' }
                $qq = $j.data.question
                if (-not $qq) { throw 'LeetCode did not return this problem.' }
                $res.Name = $qq.title
                $res.Id = ('{0:D4}' -f [int]$qq.questionFrontendId)
                $res.Difficulty = $qq.difficulty
                $res.Topics = @($qq.topicTags | ForEach-Object { $_.name.ToLowerInvariant() })
            }
            'AtCoder' {
                $t = Get-CPPageTitle -Url ($Link.Split('?')[0] + '?lang=en') -TimeoutSec $TimeoutSec
                # "A - Product" (sometimes followed by " - AtCoder ...")
                $t = ($t -replace '\s*-\s*AtCoder.*$', '')
                $res.Name = ($t -replace '^[A-Za-z0-9]+\s*-\s*', '').Trim()
                $res.Id = $info.Id
            }
            'CSES' {
                $t = Get-CPPageTitle -Url $Link -TimeoutSec ([Math]::Max($TimeoutSec, 15))
                $res.Name = ($t -replace '^CSES\s*-\s*', '').Trim()
                $res.Id = $info.Id
            }
            default {
                $t = Get-CPPageTitle -Url $Link -TimeoutSec $TimeoutSec
                $res.Name = ($t -split '\s+[\|\-]\s+')[0].Trim()
                $res.Id = $info.Id
            }
        }
        $res.Ok = [bool]$res.Name
        if (-not $res.Ok) { $res.Message = 'No problem name found online.' } else { $res.Message = "Fetched from $($info.Platform)." }
    } catch {
        $res.Message = "Online lookup failed: $(Get-CPWebError $_)"
    }
    return $res
}

function ConvertFrom-CPJson {
    <# ConvertFrom-Json without the 2 MB limit of Windows PowerShell 5.1. #>
    param([Parameter(Mandatory)][string]$Text)
    if ($PSVersionTable.PSVersion.Major -ge 6) { return ($Text | ConvertFrom-Json) }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    return $ser.DeserializeObject($Text)
}

function Get-CPCodeforcesProblem {
    <#
      Finds a Codeforces problem and returns @{ name; rating; tags }.
      Tries the full problem list first (cached for a day as a small TSV in
      %APPDATA%\CPSolutionSaver), then the contest's standings (needed for
      problems that are not in the problemset, e.g. gym).
    #>
    param([string]$ContestId, [string]$Index, [int]$TimeoutSec = 8)
    $errors = @()
    $find = {
        param($lines)
        foreach ($ln in $lines) {
            $c = $ln -split "`t"
            if ($c.Count -ge 5 -and $c[0] -eq $ContestId -and $c[1] -eq $Index) {
                return [pscustomobject]@{ name = $c[2]; rating = $c[3]; tags = @($c[4] -split ';' | Where-Object { $_ }) }
            }
        }
        return $null
    }
    if ([int]$ContestId -lt 100000) {
        try {
            $cache = Join-Path (Get-CPDataDir) 'codeforces-problems.tsv'
            $p = $null
            if ((Test-Path $cache) -and ((Get-Date) - (Get-Item $cache).LastWriteTime).TotalHours -lt 24) {
                $p = & $find ([IO.File]::ReadAllLines($cache))
            }
            if (-not $p) {
                $resp = Invoke-WebRequest -Uri 'https://codeforces.com/api/problemset.problems' -UseBasicParsing -TimeoutSec ([Math]::Max($TimeoutSec, 25)) -Headers @{ 'User-Agent' = 'CPSolutionSaver' }
                $all = ConvertFrom-CPJson $resp.Content
                if ($all.status -ne 'OK') { throw "$($all.comment)" }
                $sb = New-Object System.Text.StringBuilder
                foreach ($q in $all.result.problems) {
                    $nm = ([string]$q.name) -replace "[`t`r`n]", ' '
                    [void]$sb.Append([string]$q.contestId).Append("`t").Append([string]$q.index).Append("`t").Append($nm).Append("`t").Append([string]$q.rating).Append("`t").Append((@($q.tags) -join ';')).Append("`n")
                }
                Write-CPTextFile -Path $cache -Text $sb.ToString()
                $p = & $find ($sb.ToString() -split "`n")
            }
            if ($p) { return $p }
            $errors += 'not in the problemset list'
        } catch { $errors += "problemset: $(Get-CPWebError $_)" }
    }
    try {
        $api = "https://codeforces.com/api/contest.standings?contestId=$ContestId&from=1&count=1"
        $j = Invoke-RestMethod -Uri $api -TimeoutSec $TimeoutSec -Headers @{ 'User-Agent' = 'CPSolutionSaver' }
        if ($j.status -ne 'OK') { throw "$($j.comment)" }
        $q = $j.result.problems | Where-Object { $_.index -eq $Index } | Select-Object -First 1
        if ($q) { return [pscustomobject]@{ name = $q.name; rating = [string]$q.rating; tags = @($q.tags) } }
        $errors += "problem $Index not in contest $ContestId"
    } catch { $errors += "standings: $(Get-CPWebError $_)" }
    throw ('Codeforces lookup failed (' + ($errors -join '; ') + ')')
}

function Get-CPWebError($err) {
    $m = $err.Exception.Message
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        $d = $err.ErrorDetails.Message
        try { $c = ($d | ConvertFrom-Json).comment; if ($c) { $d = $c } } catch { }
        if ($d.Length -gt 200) { $d = $d.Substring(0, 200) }
        $m = "$m $d"
    }
    return $m
}

function Merge-CPTopics {
    <# Union of topic lists, case-insensitive, keeping the first spelling. #>
    param([object[]]$Lists)
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($list in $Lists) {
        foreach ($t in @($list)) {
            if ($null -eq $t) { continue }
            foreach ($piece in ([string]$t -split '[,;]')) {
                $x = $piece.Trim()
                if (-not $x) { continue }
                $k = $x.ToLowerInvariant()
                if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $out.Add($x) }
            }
        }
    }
    return $out.ToArray()
}

# ----------------------------------------------------------------------------
#  Building the solution info
# ----------------------------------------------------------------------------

function Get-CPSafeFileName([string]$Text) {
    $s = $Text -replace '[\\/:*?"<>|]', '' -replace ("[`'" + [char]0x2019 + "]"), '' -replace '[^\w\-]+', '_'
    $s = $s.Trim('_')
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80).TrimEnd('_') }
    return $s
}

function New-CPSolutionInfo {
    <#
      Combines the header of the code with online metadata into everything
      needed to save the solution. Returns a hashtable:
        Name, Link, Platform, Id, Difficulty, Level (as written, may be ''),
        LevelSet, Starred, StarredSet, Topics (string[]), Notes,
        DateSolved, DateAuto, Extra (other header fields), Body, Newline,
        Prefix, Ext, Language, Style, Key, FileBase, RelPath,
        Metadata (fetch result or $null)
      -Extension: the practice file's extension (.cpp, .c, .py ...); decides
      the saved file's extension and header style.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Code,
        [switch]$Fetch,
        [string]$Extension = '.cpp',
        [hashtable]$Overrides = @{}
    )
    $h = Read-CPHeader $Code
    $f = $h.Fields
    function _get($k) { if ($f.Contains($k)) { return [string]$f[$k] } else { return '' } }
    $lang = Get-CPLanguage $Extension

    $info = @{
        Name       = _get 'Problem Name'
        Link       = _get 'Problem Link'
        Platform   = _get 'Platform'
        Id         = _get 'Problem ID'
        Difficulty = _get 'Difficulty'
        Level      = ConvertTo-CPLevelName (_get 'Level')
        LevelSet   = $false
        Starred    = (Test-CPTruthy (_get 'Starred'))
        StarredSet = $f.Contains('Starred')
        Topics     = @(Merge-CPTopics @(,(_get 'Topics')))
        Notes      = _get 'Notes'
        DateSolved = _get 'Date Solved'
        DateAuto   = $false
        Extra      = [ordered]@{}
        Body       = $h.Body
        Newline    = $h.Newline
        Prefix     = $h.Prefix
        HasHeader  = $h.HasHeader
        Ext        = $lang.Ext
        Language   = $lang.Name
        Style      = $lang.Style
        Metadata   = $null
    }
    # "Level: 1500" (older headers used Level for the rating) counts as the difficulty
    if (-not $info.Difficulty -and $f.Contains('Level') -and -not $info.Level -and (Get-CPRatingNumber (_get 'Level'))) { $info.Difficulty = _get 'Level' }
    $info.LevelSet = [bool]$info.Level
    foreach ($k in $f.Keys) { if ($script:HeaderOrder -notcontains $k) { $info.Extra[$k] = $f[$k] } }
    foreach ($k in $Overrides.Keys) { $info[$k] = $Overrides[$k] }

    $pi = Get-CPPlatformInfo $info.Link
    if (-not $info.Platform -and $info.Link) { $info.Platform = $pi.Platform }
    if (-not $info.Id) { $info.Id = $pi.Id }

    if ($Fetch -and $info.Link) {
        $md = Get-CPProblemMetadata $info.Link
        $info.Metadata = $md
        if ($md.Ok) {
            if (-not $info.Name)       { $info.Name = $md.Name }
            if (-not $info.Id)         { $info.Id = $md.Id }
            if (-not $info.Difficulty) { $info.Difficulty = $md.Difficulty }
            $info.Topics = @(Merge-CPTopics @($info.Topics, $md.Topics))
        }
    }
    if (-not $info.DateSolved) { $info.DateSolved = (Get-Date).ToString('yyyy-MM-dd'); $info.DateAuto = $true }
    Update-CPSolutionPath $info
    return $info
}

function Update-CPSolutionPath {
    <# (Re)computes Key, FileBase and RelPath from Link/Name/Id/Platform/Ext. #>
    param([Parameter(Mandatory)][hashtable]$Info)
    $plat = Get-CPSafeFileName $(if ($Info.Platform) { $Info.Platform } else { 'Other' })
    if (-not $plat) { $plat = 'Other' }
    $safeName = Get-CPSafeFileName $Info.Name
    $safeId = Get-CPSafeFileName $Info.Id
    if ($safeId -and $safeName) { $base = "${safeId}_$safeName" }
    elseif ($safeName) { $base = $safeName }
    elseif ($safeId) { $base = $safeId }
    else { $base = '' }
    $ext = if ($Info.Ext) { $Info.Ext } else { '.cpp' }
    $Info.Key = Get-CPProblemKey $Info.Link
    $Info.FileBase = $base
    $Info.RelPath = if ($base) { "$plat/$base$ext" } else { '' }
}

function ConvertTo-CPSolutionText {
    <# Full text of the saved file: normalized header + original code. #>
    param([Parameter(Mandatory)][hashtable]$Info)
    $fields = [ordered]@{
        'Problem Name' = $Info.Name
        'Problem Link' = $Info.Link
        'Platform'     = $Info.Platform
        'Problem ID'   = $Info.Id
        'Difficulty'   = $Info.Difficulty
        'Level'        = (Get-CPLevel -Difficulty $Info.Difficulty -Level $Info.Level)
        'Topics'       = (@($Info.Topics) -join ', ')
        'Date Solved'  = $Info.DateSolved
    }
    if ($Info.Starred) { $fields['Starred'] = 'yes' }
    foreach ($k in $Info.Extra.Keys) { $fields[$k] = $Info.Extra[$k] }
    $fields['Notes'] = $Info.Notes
    $nl = $Info.Newline
    $style = if ($Info.Style) { $Info.Style } else { 'block' }
    $body = $Info.Body -replace '^(\s*\r?\n)+', ''
    return ([string]$Info.Prefix) + (ConvertTo-CPHeader -Fields $fields -Newline $nl -Style $style) + $nl + $nl + $body
}

# ----------------------------------------------------------------------------
#  Scanning the solutions repo
# ----------------------------------------------------------------------------

$script:SolutionCache = @{}

function Get-CPStats {
    <# Small numbers for the header: total solved, solved in the last 7 days. #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $all = @(Get-CPAllSolutions $RepoPath)
    $weekAgo = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
    $week = @($all | Where-Object { $_.DateSolved -ge $weekAgo } | ForEach-Object { if ($_.Key) { $_.Key } else { $_.RelPath } } | Select-Object -Unique).Count
    $problems = @($all | ForEach-Object { if ($_.Key) { $_.Key } else { $_.RelPath } } | Select-Object -Unique).Count
    return @{ Files = $all.Count; Problems = $problems; ThisWeek = $week }
}

function Get-CPAllSolutions {
    <# Reads the header of every solution file in the repo (skips .git, Index). #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $root = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
    $list = New-Object System.Collections.Generic.List[object]
    # (-Include is unreliable with -LiteralPath on Windows PowerShell 5.1, so filter by extension here)
    $exts = Get-CPSourceExtensions
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $exts -contains $_.Extension.ToLowerInvariant() -and $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]Index[\\/]' }
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        # cache: a file that has not changed since the last scan is not read again
        $ck = $file.FullName.ToLowerInvariant()
        $stamp = "$($file.LastWriteTimeUtc.Ticks)|$($file.Length)|$root"
        if ($script:SolutionCache.ContainsKey($ck) -and $script:SolutionCache[$ck].Stamp -eq $stamp) { $list.Add($script:SolutionCache[$ck].Item); continue }
        $text = ''
        try { $text = [IO.File]::ReadAllText($file.FullName) } catch { continue }
        $h = Read-CPHeader $text
        $f = $h.Fields
        $name = if ($f.Contains('Problem Name') -and $f['Problem Name']) { $f['Problem Name'] } else { $file.BaseName }
        $link = if ($f.Contains('Problem Link')) { $f['Problem Link'] } else { '' }
        $plat = if ($f.Contains('Platform') -and $f['Platform']) { $f['Platform'] } else { ($rel -split '/')[0] }
        if ($rel -notmatch '/') { $plat = (Get-CPPlatformInfo $link).Platform }
        $lang = Get-CPLanguage $file.Extension
        $diff = if ($f.Contains('Difficulty')) { [string]$f['Difficulty'] } else { '' }
        $lvlText = if ($f.Contains('Level')) { [string]$f['Level'] } else { '' }
        if (-not $diff -and (Get-CPRatingNumber $lvlText)) { $diff = $lvlText }
        $item = ([pscustomobject]@{
            RelPath    = $rel
            Name       = $name
            Link       = $link
            Key        = (Get-CPProblemKey $link)
            Platform   = $plat
            Id         = $(if ($f.Contains('Problem ID')) { $f['Problem ID'] } else { '' })
            Difficulty = $diff
            Level      = (Get-CPLevel -Difficulty $diff -Level $lvlText)
            Starred    = $(if ($f.Contains('Starred')) { Test-CPTruthy $f['Starred'] } else { $false })
            Number     = 0
            Topics     = @(Merge-CPTopics @(,$(if ($f.Contains('Topics')) { $f['Topics'] } else { '' })))
            DateSolved = $(if ($f.Contains('Date Solved')) { $f['Date Solved'] } else { $file.LastWriteTime.ToString('yyyy-MM-dd') })
            Notes      = $(if ($f.Contains('Notes')) { $f['Notes'] } else { '' })
            Language   = $lang.Name
            Ext        = $file.Extension.ToLowerInvariant()
            FullPath   = $file.FullName
        })
        $script:SolutionCache[$ck] = @{ Stamp = $stamp; Item = $item }
        $list.Add($item)
    }
    $arr = $list.ToArray()
    Set-CPSolutionNumbers $arr
    return $arr
}

function Set-CPSolutionNumbers {
    <# Numbers problems in the order they were first solved: #1 is the first. The same problem in
       two languages shares one number. Ties (same date) go by path. #>
    param([object[]]$Solutions)
    $first = @{}
    foreach ($s in $Solutions) {
        $k = if ($s.Key) { $s.Key } else { 'path:' + $s.RelPath.ToLowerInvariant() }
        $v = "$($s.DateSolved)|$($s.RelPath)"
        if (-not $first.ContainsKey($k) -or [string]::CompareOrdinal($v, $first[$k]) -lt 0) { $first[$k] = $v }
    }
    $order = @{}; $i = 0
    foreach ($k in ($first.Keys | Sort-Object { $first[$_] })) { $i++; $order[$k] = $i }
    foreach ($s in $Solutions) {
        $k = if ($s.Key) { $s.Key } else { 'path:' + $s.RelPath.ToLowerInvariant() }
        $s.Number = $order[$k]
    }
}

function Find-CPSolvedBefore {
    <# Every saved solution of the same problem (same problem link), in any language. #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][hashtable]$Info)
    $key = Get-CPProblemKey $Info.Link
    if (-not $key) { return @() }
    return @(Get-CPAllSolutions $RepoPath | Where-Object { $_.Key -eq $key })
}

function Find-CPExistingSolution {
    <#
      The saved file to update for this problem: same problem link and same
      language. (The link identifies the problem, so a renamed problem or a
      different spelling of the link still finds it.) Falls back to the same
      path. Returns the repo-relative path or $null.
    #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][hashtable]$Info)
    $lang = Get-CPLanguage $(if ($Info.Ext) { $Info.Ext } else { '.cpp' })
    $same = @(Find-CPSolvedBefore -RepoPath $RepoPath -Info $Info | Where-Object { $_.Language -eq $lang.Name } | Sort-Object RelPath)
    if ($same.Count) {
        $exact = $same | Where-Object { $_.RelPath -eq $Info.RelPath } | Select-Object -First 1
        if ($exact) { return $exact.RelPath }
        $notV = $same | Where-Object { $_.RelPath -notmatch '_v\d+\.\w+$' } | Select-Object -First 1
        if ($notV) { return $notV.RelPath }
        return $same[0].RelPath
    }
    if ($Info.RelPath -and (Test-Path -LiteralPath (Join-Path $RepoPath $Info.RelPath))) { return $Info.RelPath }
    return $null
}

# ----------------------------------------------------------------------------
#  Indexes: README stats + Index/BY_PLATFORM.md, BY_TOPIC.md, BY_DIFFICULTY.md
# ----------------------------------------------------------------------------

function Get-CPDifficultyGroup([string]$d) {
    <# Returns @{ Label; SortKey } for grouping. #>
    $x = ($d + '').Trim()
    if (-not $x) { return @{ Label = 'Unrated'; SortKey = 'z' } }
    $nm = [regex]::Match($x, '^(?:rating\s*:?\s*|r\s*)?(\d{2,4})$', 'IgnoreCase')
    if ($nm.Success) {
        $n = [int]$nm.Groups[1].Value
        return @{ Label = "Rating $n"; SortKey = ('a{0:D5}' -f $n) }
    }
    switch -Regex ($x) {
        '^(easy|beginner)$'  { return @{ Label = 'Easy';   SortKey = 'b1' } }
        '^(medium|mid)$'     { return @{ Label = 'Medium'; SortKey = 'b2' } }
        '^(hard)$'           { return @{ Label = 'Hard';   SortKey = 'b3' } }
    }
    return @{ Label = $x; SortKey = 'c' + $x.ToLowerInvariant() }
}

function Format-CPMd([string]$s) { ($s -replace '\|', '\|' -replace "\r?\n", ' ').Trim() }

function Format-CPRow {
    param($s, [string]$Prefix)
    $prob = if ($s.Link) { "[{0}]({1})" -f (Format-CPMd $s.Name), $s.Link } else { Format-CPMd $s.Name }
    if ($s.Starred) { $prob = [string][char]0x2605 + ' ' + $prob }
    $solPath = (($s.RelPath -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $sol = "[{0}]({1}{2})" -f ($s.RelPath -split '/')[-1], $Prefix, $solPath
    $topics = (@($s.Topics) | ForEach-Object { $_.ToLowerInvariant() }) -join ', '
    return "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f $s.Number, $prob, (Format-CPMd $s.Platform), (Format-CPMd $s.Difficulty), $s.Level, (Format-CPMd $topics), $sol, $s.DateSolved
}

$script:TableHead = "| # | Problem | Platform | Difficulty | Level | Topics | Solution | Solved |`n|---|---|---|---|---|---|---|---|"

function Update-CPIndexes {
    <# Regenerates the README stats section and the Index/*.md files. Returns the list of changed paths (relative). #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $all = @(Get-CPAllSolutions $RepoPath | Sort-Object DateSolved, RelPath -Descending)
    $stamp = (Get-Date).ToString('yyyy-MM-dd')
    $indexDir = Join-Path $RepoPath 'Index'
    $gen = "<!-- Generated by CP Solution Saver. Do not edit by hand: run 'Rebuild index' instead. -->"

    # --- by platform
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Solutions by platform`n`n$gen`n")
    $byPlat = $all | Group-Object Platform | Sort-Object Name
    foreach ($g in $byPlat) { [void]$sb.AppendLine("- [$($g.Name)](#$(($g.Name.ToLowerInvariant() -replace '[^a-z0-9 -]', '' -replace ' ', '-'))) ($($g.Count))") }
    foreach ($g in $byPlat) {
        [void]$sb.AppendLine("`n## $($g.Name)`n`n$script:TableHead")
        foreach ($s in ($g.Group | Sort-Object { Get-CPDifficultySortKey $_.Difficulty $_.Level }, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
    }
    Write-CPTextFile -Path (Join-Path $indexDir 'BY_PLATFORM.md') -Text $sb.ToString()

    # --- by topic
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Solutions by topic`n`n$gen`n")
    $topicMap = @{}
    foreach ($s in $all) {
        $ts = @($s.Topics)
        if ($ts.Count -eq 0) { $ts = @('untagged') }
        foreach ($t in $ts) {
            $k = $t.ToLowerInvariant()
            if (-not $topicMap.ContainsKey($k)) { $topicMap[$k] = New-Object System.Collections.Generic.List[object] }
            $topicMap[$k].Add($s)
        }
    }
    $topicNames = @($topicMap.Keys | Sort-Object { if ($_ -eq 'untagged') { 'zzzz' } else { $_ } })
    foreach ($t in $topicNames) { [void]$sb.AppendLine("- [$t](#$(($t -replace '[^a-z0-9 -]', '' -replace ' ', '-'))) ($($topicMap[$t].Count))") }
    foreach ($t in $topicNames) {
        [void]$sb.AppendLine("`n## $t`n`n$script:TableHead")
        foreach ($s in ($topicMap[$t] | Sort-Object { Get-CPDifficultySortKey $_.Difficulty $_.Level }, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
    }
    Write-CPTextFile -Path (Join-Path $indexDir 'BY_TOPIC.md') -Text $sb.ToString()

    # --- by difficulty
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Solutions by difficulty`n`n$gen`n")
    [void]$sb.AppendLine("Level: Easy / Medium / Hard from LeetCode, your header, or the rating (under $script:LevelMediumFrom Easy, under $script:LevelHardFrom Medium, else Hard). Within a level: by rating.`n")
    $byDiff = $all | Group-Object { if ($_.Level) { $_.Level } else { 'Unrated' } } | Sort-Object { Get-CPLevelRank $_.Name }
    foreach ($g in $byDiff) { [void]$sb.AppendLine("- [$($g.Name)](#$(($g.Name.ToLowerInvariant() -replace '[^a-z0-9 -]', '' -replace ' ', '-'))) ($($g.Count))") }
    foreach ($g in $byDiff) {
        [void]$sb.AppendLine("`n## $($g.Name)`n`n$script:TableHead")
        foreach ($s in ($g.Group | Sort-Object { Get-CPRatingNumber $_.Difficulty }, Platform, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
    }
    Write-CPTextFile -Path (Join-Path $indexDir 'BY_DIFFICULTY.md') -Text $sb.ToString()

    # --- README stats section
    $st = New-Object System.Text.StringBuilder
    [void]$st.AppendLine('<!-- CPSAVER:STATS:START -->')
    [void]$st.AppendLine("## Progress`n")
    [void]$st.AppendLine("**$($all.Count)** problems solved  (last updated $stamp)`n")
    [void]$st.AppendLine("Browse: [by platform](Index/BY_PLATFORM.md) | [by topic](Index/BY_TOPIC.md) | [by difficulty](Index/BY_DIFFICULTY.md)`n")
    if ($all.Count -gt 0) {
        [void]$st.AppendLine("| Platform | Solved |`n|---|---|")
        foreach ($g in ($byPlat | Sort-Object Count -Descending)) { [void]$st.AppendLine("| $($g.Name) | $($g.Count) |") }
        [void]$st.AppendLine('')
        $topTopics = @($topicNames | Where-Object { $_ -ne 'untagged' } | Sort-Object { -$topicMap[$_].Count }, { $_ } | Select-Object -First 12)
        if ($topTopics.Count) {
            [void]$st.AppendLine("**Top topics:** " + (($topTopics | ForEach-Object { "$_ ($($topicMap[$_].Count))" }) -join (' ' + [char]0x00B7 + ' ')) + "`n")
        }
        $lv = @{}; foreach ($s in $all) { $k = if ($s.Level) { $s.Level } else { 'Unrated' }; $lv[$k] = 1 + [int]$lv[$k] }
        [void]$st.AppendLine("**By level:** " + ((@('Easy', 'Medium', 'Hard', 'Unrated') | Where-Object { $lv[$_] } | ForEach-Object { "$_ $($lv[$_])" }) -join (' ' + [char]0x00B7 + ' ')) + "`n")
        $stars = @($all | Where-Object { $_.Starred } | Sort-Object Number)
        if ($stars.Count) {
            [void]$st.AppendLine("### Starred`n`n$script:TableHead")
            foreach ($s in $stars) { [void]$st.AppendLine((Format-CPRow $s '')) }
            [void]$st.AppendLine('')
        }
        [void]$st.AppendLine("### Recently solved`n`n$script:TableHead")
        foreach ($s in ($all | Select-Object -First 10)) { [void]$st.AppendLine((Format-CPRow $s '')) }
    }
    [void]$st.Append('<!-- CPSAVER:STATS:END -->')

    $readmePath = Join-Path $RepoPath 'README.md'
    $readme = if (Test-Path $readmePath) { Read-CPTextFile $readmePath } else { "# Problem Solving Solutions`n`nMy accepted competitive programming solutions.`n" }
    $pattern = '(?s)<!-- CPSAVER:STATS:START -->.*?<!-- CPSAVER:STATS:END -->'
    if ($readme -match $pattern) {
        $readme = [regex]::Replace($readme, $pattern, $st.ToString().Replace('$', '$$'))
    } else {
        $readme = $readme.TrimEnd() + "`n`n" + $st.ToString() + "`n"
    }
    $readme = $readme -replace "\r\n", "`n"
    Write-CPTextFile -Path $readmePath -Text $readme
    return @('README.md', 'Index/BY_PLATFORM.md', 'Index/BY_TOPIC.md', 'Index/BY_DIFFICULTY.md')
}

function Set-CPHeaderField {
    <# Sets one header field of a saved solution file (an empty value removes it). The code is not touched. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Field, [AllowEmptyString()][string]$Value = '')
    $text = Read-CPTextFile $Path
    $h = Read-CPHeader $text
    if (-not $h.HasHeader) { throw "No problem header in $Path" }
    $fields = [ordered]@{}
    foreach ($k in $h.Fields.Keys) { $fields[$k] = $h.Fields[$k] }
    if ($Value) { $fields[$Field] = $Value } elseif ($fields.Contains($Field)) { $fields.Remove($Field) }
    $body = $h.Body -replace '^(\s*\r?\n)+', ''
    $new = ([string]$h.Prefix) + (ConvertTo-CPHeader -Fields $fields -Newline $h.Newline -Style $h.Style) + $h.Newline + $h.Newline + $body
    Write-CPTextFile -Path $Path -Text $new
}

function Set-CPStarred {
    <# Stars / unstars a saved solution: edits its header, refreshes the indexes, commits, pushes if
       -Push and a remote exists. Returns @{ Success; Pushed; Message }. #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$RelPath, [bool]$Starred = $true, [switch]$Push, [switch]$UpdateIndexes)
    $full = Join-Path $RepoPath $RelPath
    if (-not (Test-Path -LiteralPath $full)) { return @{ Success = $false; Pushed = $false; Message = "File not found: $RelPath" } }
    Set-CPHeaderField -Path $full -Field 'Starred' -Value $(if ($Starred) { 'yes' } else { '' })
    $paths = @($RelPath)
    if ($UpdateIndexes) { $paths += @(Update-CPIndexes -RepoPath $RepoPath) }
    if ((Test-CPRepoFolder $RepoPath) -ne 'repo') { return @{ Success = $true; Pushed = $false; Message = 'Saved (the folder is not a git repo).' } }
    Invoke-CPGit $RepoPath add -- @($paths) | Out-Null
    if ((Invoke-CPGit $RepoPath diff --cached --quiet).Code -eq 0) { return @{ Success = $true; Pushed = $false; Message = 'No change.' } }
    $name = [IO.Path]::GetFileNameWithoutExtension($RelPath)
    $c = Invoke-CPGit $RepoPath commit -q -m $(if ($Starred) { "Star $name" } else { "Unstar $name" })
    if ($c.Code -ne 0) { return @{ Success = $false; Pushed = $false; Message = "git commit failed: $($c.Output)" } }
    $pushed = $false
    if ($Push -and (Invoke-CPGit $RepoPath remote).Output) { $pushed = ((Invoke-CPGit $RepoPath push -q).Code -eq 0) }
    return @{ Success = $true; Pushed = $pushed; Message = $(if ($pushed) { 'Committed and pushed.' } else { 'Committed.' }) }
}

# ----------------------------------------------------------------------------
#  Git
# ----------------------------------------------------------------------------

function Invoke-CPGit {
    <# Invoke-CPGit <folder> <git args...>. Returns @{ Code; Output (string) }. Never throws.
       (A simple function on purpose, so args like --rebase are passed through to git.) #>
    $Path = [string]$args[0]
    $GitArgs = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt $args.Count; $i++) { foreach ($a in @($args[$i])) { $GitArgs.Add([string]$a) } }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Path @GitArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } catch {
        $out = @("$($_.Exception.Message)"); $code = 1
    } finally { $ErrorActionPreference = $old }
    return @{ Code = $code; Output = (($out | Where-Object { $_ -ne $null }) -join "`n").Trim() }
}

function Test-CPGitAvailable {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Get-CPGitIdentity {
    <# The name + email git will record with a commit in this folder (repo, global or system level). #>
    param([string]$RepoPath)
    $dir = if ($RepoPath -and (Test-Path -LiteralPath $RepoPath)) { $RepoPath } else { $HOME }
    $n = "$((Invoke-CPGit $dir config user.name).Output)".Trim()
    $e = "$((Invoke-CPGit $dir config user.email).Output)".Trim()
    return @{ Name = $n; Email = $e; Ok = [bool]($n -and $e) }
}

function Set-CPGitIdentity {
    <# Saves the name + email for git on this PC (git config --global), once. #>
    param([string]$Name = '', [string]$Email = '')
    $Name = $Name.Trim(); $Email = $Email.Trim()
    if (-not $Name) { throw 'Enter your name.' }
    if ($Email -notmatch '^[^@\s]+@[^@\s]+$') { throw 'Enter a valid email address (like you@example.com).' }
    foreach ($kv in @(@('user.name', $Name), @('user.email', $Email))) {
        $r = Invoke-CPGit $HOME config --global $kv[0] $kv[1]
        if ($r.Code -ne 0) { throw "git config failed: $($r.Output)" }
    }
}

function Test-CPRepoFolder {
    <# 'repo' (a git repo), 'empty' (empty or missing folder - can become one), 'files' (a folder with files, not a repo), 'none' (no path). #>
    param([string]$Path)
    if (-not $Path) { return 'none' }
    if (Test-Path -LiteralPath (Join-Path $Path '.git')) { return 'repo' }
    if (-not (Test-Path -LiteralPath $Path)) { return 'empty' }
    if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count -eq 0) { return 'empty' }
    return 'files'
}

function Initialize-CPRepo {
    <# Makes a folder a new local git repo (branch "main"). Files already in it are kept. Returns the full path. #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-CPGitAvailable)) { throw 'Git is not installed. Install it from https://git-scm.com/download/win and try again.' }
    if (Test-Path -LiteralPath (Join-Path $Path '.git')) { return (Resolve-Path -LiteralPath $Path).ProviderPath }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $r = Invoke-CPGit $full init -q
    if ($r.Code -ne 0) { throw "git init failed: $($r.Output)" }
    Invoke-CPGit $full symbolic-ref HEAD refs/heads/main | Out-Null   # works on every git version, before the first commit
    return $full
}

# ----------------------------------------------------------------------------
#  Saving
# ----------------------------------------------------------------------------

function Save-CPSolution {
    <#
      Writes the solution into the repo, updates indexes, commits and pushes.
      Returns @{ Success; RelPath; IsUpdate; Commit; Pushed; Log (string[]) }.
      -Log: optional scriptblock called with each log line (for the GUI).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Info,
        [Parameter(Mandatory)][string]$RepoPath,
        [switch]$Push,
        [switch]$UpdateIndexes,
        [switch]$KeepBoth,
        [scriptblock]$Log
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $emit = { param($m) $lines.Add($m); if ($Log) { & $Log $m } }
    $result = @{ Success = $false; RelPath = ''; IsUpdate = $false; Commit = ''; Pushed = $false; NoRemote = $false; Log = $lines }

    if (-not $Info.Link) { & $emit 'ERROR: The problem link is required. It identifies the problem, so the same problem is never saved twice.'; return $result }
    if (-not $Info.Name) { & $emit 'ERROR: The problem name is empty.'; return $result }
    if (-not (Test-CPGitAvailable)) { & $emit 'ERROR: git is not installed or not on PATH.'; return $result }
    $kind = Test-CPRepoFolder $RepoPath
    if ($kind -eq 'empty') {
        try { $RepoPath = Initialize-CPRepo $RepoPath; & $emit "Created a new local git repo in $RepoPath" }
        catch { & $emit "ERROR: $($_.Exception.Message)"; return $result }
    } elseif ($kind -ne 'repo') { & $emit "ERROR: '$RepoPath' is not a git repository (and not empty). Choose an empty folder or your repo in Settings."; return $result }
    # git needs a name + email for every commit (even offline); say so clearly instead of a git error
    if (-not (Get-CPGitIdentity $RepoPath).Ok) {
        & $emit ('ERROR: Git does not know your name and email yet (it records them with every save, even without GitHub). ' +
            'Open Command Prompt and run:' + "`n" + '  git config --global user.name "Your Name"' + "`n" + '  git config --global user.email "you@example.com"' + "`n" + 'then save again.')
        return $result
    }

    if (-not $Info.Platform) { $Info.Platform = (Get-CPPlatformInfo $Info.Link).Platform }
    Update-CPSolutionPath $Info
    $hasUpstream = (Invoke-CPGit $RepoPath rev-parse --abbrev-ref --symbolic-full-name '@{u}').Code -eq 0

    # 1. get latest from GitHub first, so the push won't be rejected
    if ($Push -and $hasUpstream) {
        & $emit 'Pulling latest changes...'
        $r = Invoke-CPGit $RepoPath pull --rebase --autostash
        if ($r.Code -ne 0) { & $emit "ERROR: git pull failed:`n$($r.Output)"; return $result }
    }

    # 2. choose the path (update the existing file for the same problem)
    $existing = Find-CPExistingSolution -RepoPath $RepoPath -Info $Info
    $rel = $Info.RelPath
    if ($existing) {
        if ($KeepBoth) {
            $dir = Split-Path $existing -Parent; $base = [IO.Path]::GetFileNameWithoutExtension($existing); $ext = [IO.Path]::GetExtension($existing)
            $i = 2
            while (Test-Path -LiteralPath (Join-Path $RepoPath ("$dir/${base}_v$i$ext"))) { $i++ }
            $rel = ("$dir/${base}_v$i$ext") -replace '\\', '/'
            & $emit "Already saved before; keeping both -> $rel"
        } else {
            $rel = $existing
            $result.IsUpdate = $true
            & $emit "Already saved before; updating $rel"
            # Same problem saved before: keep the date it was first solved (unless you wrote a
            # date in the header yourself) and the link as it was first written, so re-saving
            # the same code - on another day, or with another spelling of the link - is not a change
            try {
                $old = Read-CPHeader (Read-CPTextFile (Join-Path $RepoPath $existing))
                if ($Info.DateAuto -and $old.Fields.Contains('Date Solved') -and $old.Fields['Date Solved']) { $Info.DateSolved = [string]$old.Fields['Date Solved'] }
                # keep the star, and a level chosen by hand, unless this save says otherwise
                if (-not $Info.StarredSet -and $old.Fields.Contains('Starred') -and (Test-CPTruthy $old.Fields['Starred'])) { $Info.Starred = $true }
                if (-not $Info.LevelSet -and -not (Get-CPLevel -Difficulty $Info.Difficulty) -and $old.Fields.Contains('Level')) { $Info.Level = ConvertTo-CPLevelName $old.Fields['Level'] }
                if ($old.Fields.Contains('Problem Link') -and $old.Fields['Problem Link'] -and (Get-CPProblemKey $old.Fields['Problem Link']) -eq (Get-CPProblemKey $Info.Link)) { $Info.Link = [string]$old.Fields['Problem Link'] }
            } catch { }
        }
    } else {
        $other = @(Find-CPSolvedBefore -RepoPath $RepoPath -Info $Info)
        if ($other.Count) { & $emit ("Solved before in another language: " + (($other | ForEach-Object { $_.RelPath }) -join ', ') + "; saving this $($Info.Language) solution next to it.") }
    }
    $result.RelPath = $rel

    # 3. write the file
    $full = Join-Path $RepoPath $rel
    Write-CPTextFile -Path $full -Text (ConvertTo-CPSolutionText $Info)
    & $emit "Saved -> $rel"

    # 4. indexes
    $paths = @($rel)
    if ($UpdateIndexes) {
        try { $paths += Update-CPIndexes $RepoPath; & $emit 'Updated README and Index/ (by platform, topic, difficulty).' }
        catch { & $emit "WARNING: could not update indexes: $($_.Exception.Message)" }
    }

    # 5. commit
    $r = Invoke-CPGit $RepoPath (@('add', '--') + $paths)
    if ($r.Code -ne 0) { & $emit "ERROR: git add failed:`n$($r.Output)"; return $result }
    $staged = Invoke-CPGit $RepoPath diff --cached --quiet
    if ($staged.Code -eq 0) {
        & $emit 'No changes to commit (identical solution already saved).'
        $result.Success = $true
        return $result
    }
    $label = if ($Info.Id) { "$($Info.Platform) $($Info.Id) - $($Info.Name)" } else { "$($Info.Platform) - $($Info.Name)" }
    $verb = if ($result.IsUpdate) { 'Update' } else { 'Add' }
    $subject = "$verb $label"
    $bodyLines = @()
    if ($Info.Difficulty) { $bodyLines += "Difficulty: $($Info.Difficulty)" }
    if (@($Info.Topics).Count) { $bodyLines += "Topics: $(@($Info.Topics) -join ', ')" }
    if ($Info.Link) { $bodyLines += "Link: $($Info.Link)" }
    $msgFile = [IO.Path]::GetTempFileName()
    Write-CPTextFile -Path $msgFile -Text ($subject + "`n`n" + ($bodyLines -join "`n") + "`n")
    $r = Invoke-CPGit $RepoPath commit -q -F $msgFile
    Remove-Item $msgFile -ErrorAction SilentlyContinue
    if ($r.Code -ne 0) { & $emit "ERROR: git commit failed:`n$($r.Output)"; return $result }
    $result.Commit = $subject
    & $emit "Committed: $subject"

    # 6. push
    if ($Push) {
        $hasRemote = (Invoke-CPGit $RepoPath remote).Output -match '\S'
        if (-not $hasRemote) {
            $result.NoRemote = $true
            & $emit 'Not connected to GitHub; commit kept locally.'
        } else {
            & $emit 'Pushing to GitHub...'
            $r = if ($hasUpstream) { Invoke-CPGit $RepoPath push } else { Invoke-CPGit $RepoPath push -u origin HEAD }
            if ($r.Code -ne 0) { & $emit "ERROR: git push failed (your commit is saved locally; push later):`n$($r.Output)"; return $result }
            $result.Pushed = $true
            & $emit 'Pushed to GitHub.'
        }
    }
    $result.Success = $true
    return $result
}

# ----------------------------------------------------------------------------
#  Templates (one folder, files named "<Language> - <name>.<ext>")
# ----------------------------------------------------------------------------

function Get-CPTemplateDir { Join-Path (Get-CPDataDir) 'templates' }

function Get-CPBuiltInTemplates {
    <# name (with extension) -> code without the header #>
    $cppIncludes = "#include <iostream>`n#include <vector>`n#include <string>`n#include <algorithm>`n`nusing namespace std;`n"
    [ordered]@{
        'C++ - Basic.cpp' = $cppIncludes + @'

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'@
        'C++ - Multiple test cases.cpp' = $cppIncludes + @'

void solve() {

}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);
    int t = 1;
    cin >> t;
    while (t--) solve();
    return 0;
}
'@
        'C++ - Competitive (aliases, macros).cpp' = @'
#define _CRT_SECURE_NO_WARNINGS
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <algorithm>
#include <numeric>
#include <map>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <queue>
#include <stack>
#include <deque>
#include <bitset>
#include <cmath>
#include <climits>
#include <cstring>
#include <functional>

using namespace std;

using ll = long long;
using ull = unsigned long long;
using ld = long double;
using pii = pair<int, int>;
using pll = pair<ll, ll>;
using vi = vector<int>;
using vll = vector<ll>;

#define all(x) (x).begin(), (x).end()
#define rall(x) (x).rbegin(), (x).rend()
#define sz(x) (int)(x).size()

const ll MOD = 1000000007LL;
const ll INF = (ll)4e18;

void solve() {

}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);
#ifdef LOCAL_INPUT   // add LOCAL_INPUT to your project's preprocessor definitions to read input.txt
    freopen("input.txt", "r", stdin);
#endif
    int t = 1;
    // cin >> t;   // uncomment for multiple test cases
    while (t--) solve();
    return 0;
}
'@
        'C++ - Graph (BFS, DFS).cpp' = "#include <iostream>`n#include <vector>`n#include <queue>`n`nusing namespace std;`n" + @'

int n, m;
vector<vector<int>> adj;
vector<bool> visited;

void dfs(int u) {
    visited[u] = true;
    for (int v : adj[u])
        if (!visited[v]) dfs(v);
}

// distance (number of edges) from src to every node, -1 = unreachable
vector<int> bfs(int src) {
    vector<int> dist(n + 1, -1);
    queue<int> q;
    dist[src] = 0;
    q.push(src);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int v : adj[u])
            if (dist[v] == -1) { dist[v] = dist[u] + 1; q.push(v); }
    }
    return dist;
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> m;
    adj.assign(n + 1, vector<int>());
    visited.assign(n + 1, false);
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        adj[u].push_back(v);
        adj[v].push_back(u);   // remove for a directed graph
    }

    return 0;
}
'@
        'C++ - Number theory (mod pow, sieve, nCr).cpp' = "#include <iostream>`n#include <vector>`n`nusing namespace std;`n" + @'

using ll = long long;
const ll MOD = 1000000007LL;

ll gcd_(ll a, ll b) { return b == 0 ? a : gcd_(b, a % b); }
ll lcm_(ll a, ll b) { return a / gcd_(a, b) * b; }

// (base ^ exp) % mod in O(log exp)
ll power(ll base, ll exp, ll mod = MOD) {
    ll result = 1;
    base %= mod;
    while (exp > 0) {
        if (exp & 1) result = result * base % mod;
        base = base * base % mod;
        exp >>= 1;
    }
    return result;
}

// modular inverse; mod must be prime
ll inverse(ll a, ll mod = MOD) { return power(a, mod - 2, mod); }

// all primes <= n
vector<int> sieve(int n) {
    vector<bool> composite(n + 1, false);
    vector<int> primes;
    for (int i = 2; i <= n; i++) {
        if (composite[i]) continue;
        primes.push_back(i);
        for (ll j = (ll)i * i; j <= n; j += i) composite[(size_t)j] = true;
    }
    return primes;
}

// nCr % MOD for n <= MAXN (call initFactorials() once)
const int MAXN = 200000;
vector<ll> fact, invFact;
void initFactorials() {
    fact.assign(MAXN + 1, 1);
    invFact.assign(MAXN + 1, 1);
    for (int i = 1; i <= MAXN; i++) fact[i] = fact[i - 1] * i % MOD;
    invFact[MAXN] = inverse(fact[MAXN]);
    for (int i = MAXN; i > 0; i--) invFact[i - 1] = invFact[i] * i % MOD;
}
ll nCr(int n, int r) {
    if (r < 0 || r > n) return 0;
    return fact[n] * invFact[r] % MOD * invFact[n - r] % MOD;
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'@
        'C++ - DSU and Fenwick tree.cpp' = "#include <iostream>`n#include <vector>`n#include <algorithm>`n`nusing namespace std;`n" + @'

// Disjoint set union (union-find) with path compression + union by size
struct DSU {
    vector<int> parent, sz;
    DSU(int n) : parent(n + 1), sz(n + 1, 1) { for (int i = 0; i <= n; i++) parent[i] = i; }
    int find(int x) {
        while (parent[x] != x) x = parent[x] = parent[parent[x]];
        return x;
    }
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        parent[b] = a;
        sz[a] += sz[b];
        return true;
    }
};

// Fenwick tree (BIT), 1-indexed: add(i, v); sum(i) = a[1] + ... + a[i]
struct Fenwick {
    int n;
    vector<long long> t;
    Fenwick(int n) : n(n), t(n + 1, 0) {}
    void add(int i, long long v) { for (; i <= n; i += i & -i) t[i] += v; }
    long long sum(int i) { long long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    long long sum(int l, int r) { return sum(r) - sum(l - 1); }
};

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'@
        'C - Basic.c' = @'
#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {

    return 0;
}
'@
        'C - Multiple test cases.c' = @'
#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void solve(void) {

}

int main(void) {
    int t = 1;
    if (scanf("%d", &t) != 1) return 0;
    while (t--) solve();
    return 0;
}
'@
        'Python - Basic.py' = @'
def main():
    n = int(input())


if __name__ == "__main__":
    main()
'@
        'Python - Fast input.py' = @'
import sys
input = sys.stdin.readline


def main():
    n = int(input())
    a = list(map(int, input().split()))


main()
'@
        'Python - Multiple test cases.py' = @'
import sys
input = sys.stdin.readline


def solve():
    n = int(input())


def main():
    t = int(input())
    for _ in range(t):
        solve()


main()
'@
    }
}

function Initialize-CPTemplates {
    <# Writes the built-in templates that are missing (your edits are never overwritten). Returns the folder. #>
    $dir = Get-CPTemplateDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $builtIn = Get-CPBuiltInTemplates
    foreach ($name in $builtIn.Keys) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath $path) { continue }
        $lang = Get-CPLanguage $name
        $hdr = ConvertTo-CPHeader -Fields ([ordered]@{ 'Problem Name' = ''; 'Problem Link' = ''; 'Difficulty' = ''; 'Topics' = ''; 'Notes' = '' }) -Newline "`n" -Style $lang.Style
        $text = ($hdr + "`n`n" + ($builtIn[$name] -replace "\r?\n", "`n").TrimEnd() + "`n") -replace "`n", "`r`n"
        Write-CPTextFile -Path $path -Text $text
    }
    # a template you customized in v2.0/2.1 (template.cpp) is kept as "C++ - My template.cpp"
    $legacy = Join-Path (Get-CPDataDir) 'template.cpp'
    $mine = Join-Path $dir 'C++ - My template.cpp'
    if ((Test-Path -LiteralPath $legacy) -and -not (Test-Path -LiteralPath $mine)) {
        $old = (Read-CPTextFile $legacy) -replace '\s+', ''
        $orig = (Get-CPLegacyTemplate) -replace '\s+', ''
        if ($old -and $old -ne $orig) { Copy-Item -LiteralPath $legacy -Destination $mine }
    }
    return $dir
}

function Get-CPLegacyTemplate {
    @'
/*
 * Problem Name:
 * Problem Link:
 * Difficulty:
 * Topics:
 * Notes:
 */

#include <iostream>
#include <vector>
#include <string>
#include <algorithm>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'@
}

function Get-CPTemplates {
    <# Templates for a language (by extension); all templates when no extension. Objects: Name, Path, Language, Ext. #>
    param([string]$Extension)
    $dir = Initialize-CPTemplates
    $want = if ($Extension) { (Get-CPLanguage $Extension).Name } else { $null }
    $out = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | ForEach-Object {
        $lang = Get-CPLanguage $_.Extension
        [pscustomobject]@{ Name = $_.BaseName; Path = $_.FullName; Language = $lang.Name; Ext = $_.Extension.ToLowerInvariant() }
    } | Where-Object { -not $want -or $_.Language -eq $want })
    # "Basic" first, then by name
    return @($out | Sort-Object @{ Expression = { if ($_.Name -match ' - Basic$') { 0 } else { 1 } } }, Name)
}

function Get-CPDefaultTemplatePath {
    <# The template "Reset after saving" uses for this language: your choice in Settings, else "<Language> - Basic". #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Extension)
    $lang = Get-CPLanguage $Extension
    $all = @(Get-CPTemplates -Extension $Extension)
    $chosen = $null
    if ($Config.DefaultTemplates -and $Config.DefaultTemplates.Contains($lang.Name)) { $chosen = [string]$Config.DefaultTemplates[$lang.Name] }
    $t = $all | Where-Object { $_.Name -eq $chosen } | Select-Object -First 1
    if (-not $t) { $t = $all | Select-Object -First 1 }
    if ($t) { return $t.Path }
    return $null
}

function Reset-CPPracticeFile {
    <# Writes a template into the practice file. With -Config, picks the default template for the file's language. #>
    param([Parameter(Mandatory)][string]$MainCppPath, [string]$TemplatePath, $Config)
    if (-not $TemplatePath -and $Config) { $TemplatePath = Get-CPDefaultTemplatePath -Config $Config -Extension ([IO.Path]::GetExtension($MainCppPath)) }
    if (-not $TemplatePath) { throw "No template found for $([IO.Path]::GetExtension($MainCppPath)) files." }
    if (-not (Test-Path -LiteralPath $TemplatePath)) { Write-CPTextFile -Path $TemplatePath -Text ((Get-CPLegacyTemplate) -replace "\r?\n", "`r`n") }
    Write-CPTextFile -Path $MainCppPath -Text (Read-CPTextFile $TemplatePath)
}

function Initialize-CPTemplate {
    <# v2.0 compatibility: makes sure the built-in templates exist. #>
    param([string]$TemplatePath)
    Initialize-CPTemplates | Out-Null
}

function Add-CPHeaderFields {
    <# Adds any missing header fields (Difficulty, Topics, ...) to an existing file's header without touching the code. #>
    param([Parameter(Mandatory)][string]$Path)
    $code = Read-CPTextFile $Path
    $h = Read-CPHeader $code
    $f = $h.Fields
    $style = (Get-CPLanguage $Path).Style
    if ($h.HasHeader) {
        foreach ($k in @('Problem Name', 'Problem Link', 'Difficulty', 'Topics', 'Notes')) { if (-not $f.Contains($k)) { $f[$k] = '' } }
        $new = $h.Prefix + (ConvertTo-CPHeader -Fields $f -Newline $h.Newline -Style $style) + $h.Newline + $h.Body
    } else {
        $f = [ordered]@{ 'Problem Name' = ''; 'Problem Link' = ''; 'Difficulty' = ''; 'Topics' = ''; 'Notes' = '' }
        $new = (ConvertTo-CPHeader -Fields $f -Newline $h.Newline -Style $style) + $h.Newline + $h.Newline + $code
    }
    if ($new -ne $code) { Write-CPTextFile -Path $Path -Text $new; return $true }
    return $false
}

# ----------------------------------------------------------------------------
#  Quick save (no window)
# ----------------------------------------------------------------------------

function Invoke-CPQuickSave {
    <#
      Saves main.cpp with the data from its header (+ online lookup) using the
      settings' defaults: no questions. Returns
      @{ Success; Title; Summary (string[]); Log (string[]); RelPath; LogFile }.
      The full log is also written to %APPDATA%\CPSolutionSaver\last-quick-save.log.
    #>
    param([Parameter(Mandatory)]$Config, [scriptblock]$Log)
    $out = @{ Success = $false; Title = 'Quick save failed'; Summary = @(); Log = @(); RelPath = ''; LogFile = (Join-Path (Get-CPDataDir) 'last-quick-save.log') }
    Set-CPLevelCutoffs $Config
    $lines = New-Object System.Collections.Generic.List[string]
    $qsLog = $Log
    # GetNewClosure: Save-CPSolution has its own $Log parameter, so the callback must not look $Log up dynamically
    $emit = { param($m) $lines.Add($m); if ($qsLog) { & $qsLog $m } }.GetNewClosure()
    & $emit ("Quick save " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    try {
        $problems = @(Test-CPConfig $Config)
        if ($problems.Count) { $out.Summary = $problems + @('Fix it in Settings (Start Menu > CP Solution Saver - Settings).'); return $out }
        $practice = Get-CPActivePracticeFile $Config
        $Config.MainCppPath = $practice
        $fileName = [IO.Path]::GetFileName($practice)
        & $emit "File: $practice (most recently saved practice file)"
        $code = Read-CPTextFile $practice
        $info = New-CPSolutionInfo -Code $code -Fetch:([bool]$Config.AutoFetch) -Extension ([IO.Path]::GetExtension($practice))
        if ($info.Metadata) { & $emit $info.Metadata.Message }
        if (-not $info.Link) {
            $out.Summary = @("No problem link in the header of $fileName.", "The link is required: it identifies the problem, so the same problem is never saved twice.", "Add 'Problem Link: https://...' and try again, or open the full window with Ctrl+Alt+Shift+S.")
            return $out
        }
        if (-not $info.Name) {
            $out.Summary = @('No problem name found.')
            if ($info.Metadata -and -not $info.Metadata.Ok) { $out.Summary += $info.Metadata.Message }
            $out.Summary += @("Fill 'Problem Name:' in the header of $fileName (Codeforces/LeetCode/AtCoder/CSES names are looked up from the link),", 'or open the full window with Ctrl+Alt+Shift+S.')
            return $out
        }
        $res = Save-CPSolution -Info $info -RepoPath $Config.RepoPath -Push:([bool]$Config.PushAfterSave) -UpdateIndexes:([bool]$Config.UpdateIndexes) -Log $emit
        $out.RelPath = $res.RelPath
        $details = @()
        if ($info.Difficulty) { $details += "Difficulty $($info.Difficulty)" }
        if (@($info.Topics).Count) { $details += (@($info.Topics) -join ', ') }
        if ($res.Success) {
            $out.Success = $true
            if (-not $res.Commit) {
                $out.Title = "Already saved: $($info.Name)"
                $out.Summary = @("$($res.RelPath) is already up to date (same code) - nothing new to push.")
            } else {
                $state = if ($res.IsUpdate) { 'updated' } else { 'new' }
                $out.Title = "Saved: $($info.Name)"
                $out.Summary = @("$($res.RelPath) ($state)")
                if ($details) { $out.Summary += ($details -join ' | ') }
                $out.Summary += $(if ($res.Pushed) { 'Pushed to GitHub.' } elseif ($res.NoRemote) { 'Saved on this PC (not connected to GitHub).' } elseif ($Config.PushAfterSave) { 'Committed locally (push skipped).' } else { 'Committed locally (push is off in Settings).' })
            }
            if ($Config.ResetAfterSave) {
                Reset-CPPracticeFile -MainCppPath $practice -Config $Config
                $out.Summary += "$fileName reset to the template."
                & $emit "$fileName reset to the template."
            }
        } else {
            $err = @($lines | Where-Object { $_ -like 'ERROR*' }) | Select-Object -Last 1
            $out.Summary = @($(if ($err) { ($err -split "`n")[0] } else { 'See the log for details.' }))
            if ($res.Commit) { $out.Summary += 'Your commit is saved locally; it will go up with the next push.' }
        }
    } catch {
        $out.Summary = @("Error: $($_.Exception.Message)")
        & $emit "ERROR: $($_.Exception.Message)"
    } finally {
        & $emit ("Result: " + $out.Title + ' - ' + ($out.Summary -join ' / '))
        $out.Log = $lines.ToArray()
        try { Write-CPTextFile -Path $out.LogFile -Text (($lines -join "`r`n") + "`r`n") } catch { }
    }
    return $out
}

# ----------------------------------------------------------------------------
#  Loading a saved solution back into main.cpp
# ----------------------------------------------------------------------------

function Backup-CPPracticeFile {
    <# Copies main.cpp to %APPDATA%\CPSolutionSaver\backups\ and keeps the newest $Keep copies. Returns the backup path. #>
    param([Parameter(Mandatory)][string]$Path, [int]$Keep = 30)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $dir = Join-Path (Get-CPDataDir) 'backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path) + '_' + (Get-Date).ToString('yyyyMMdd_HHmmss_fff') + [IO.Path]::GetExtension($Path)
    $dest = Join-Path $dir $name
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    if ($Keep -gt 0) {
        Get-ChildItem -LiteralPath $dir -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    return $dest
}

function Get-CPBackupDir { Join-Path (Get-CPDataDir) 'backups' }

function Get-CPImportTarget {
    <# The practice file a saved solution would be loaded into (same language), or $null. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$RelPath)
    return (Get-CPPracticeFileFor -Config $Config -Extension ([IO.Path]::GetExtension($RelPath)))
}

function Import-CPSolution {
    <#
      Loads a saved solution (repo-relative path) into the practice file of
      the same language (main.cpp for .cpp, main.py for .py ...), after backing
      that file up. Returns the backup path.
    #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$RelPath)
    $src = Join-Path $Config.RepoPath $RelPath
    if (-not (Test-Path -LiteralPath $src)) { throw "Solution file not found: $src" }
    $target = Get-CPImportTarget -Config $Config -RelPath $RelPath
    if (-not $target) {
        $lang = Get-CPLanguage $RelPath
        throw "No $($lang.Name) practice file is set up ($($lang.Ext)). Add one in Settings > Practice files, then try again."
    }
    $keep = 30
    if ($Config.Contains('BackupsToKeep') -and $Config.BackupsToKeep) { $keep = [int]$Config.BackupsToKeep }
    $backup = Backup-CPPracticeFile -Path $target -Keep $keep
    Write-CPTextFile -Path $target -Text (Read-CPTextFile $src)
    return $backup
}

# ----------------------------------------------------------------------------
#  GitHub helpers (uses the sign-in Git Credential Manager already has)
# ----------------------------------------------------------------------------

function Get-CPGitHubToken {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = "protocol=https`nhost=github.com`n`n" | & git credential fill 2>&1 | ForEach-Object { "$_" }
    } finally { $ErrorActionPreference = $old }
    $pw = $out | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if ($pw) { return ($pw -replace '^password=', '') }
    return $null
}

function New-CPGitHubRepo {
    <# Creates a GitHub repo for the signed-in user and returns its clone URL. #>
    param([Parameter(Mandatory)][string]$Name, [string]$Description = '', [switch]$Private, [switch]$Empty)
    Initialize-CPWeb
    $token = Get-CPGitHubToken
    if (-not $token) { throw 'Could not get your GitHub sign-in from Git. Run any git push once to sign in, then try again.' }
    $headers = @{ Authorization = "token $token"; 'User-Agent' = 'CPSolutionSaver'; Accept = 'application/vnd.github+json' }
    $user = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
    try {
        $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$($user.login)/$Name" -Headers $headers
        return $existing.clone_url
    } catch { }
    $body = @{ name = $Name; description = $Description; private = [bool]$Private; auto_init = (-not $Empty) } | ConvertTo-Json
    $r = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -Body $body -ContentType 'application/json'
    return $r.clone_url
}

function Connect-CPGitHub {
    <# Links a local solutions repo to a GitHub repo (remote "origin") and uploads what is saved so far.
       Returns $true if something was uploaded. The GitHub repo should be empty. #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Url)
    if ((Test-CPRepoFolder $RepoPath) -ne 'repo') { throw "'$RepoPath' is not a git repo." }
    $Url = $Url.Trim()
    if ($Url -notmatch '^(https://|http://|git@|ssh://|file://|[A-Za-z]:[\\/]|\\\\|/)') { throw 'Paste the repo link, like https://github.com/you/Problem-Solving-Solutions' }
    $has = (Invoke-CPGit $RepoPath remote get-url origin).Code -eq 0
    $r = if ($has) { Invoke-CPGit $RepoPath remote set-url origin $Url } else { Invoke-CPGit $RepoPath remote add origin $Url }
    if ($r.Code -ne 0) { throw "Could not set the GitHub link: $($r.Output)" }
    if ((Invoke-CPGit $RepoPath rev-parse --verify -q HEAD).Code -ne 0) { return $false }   # nothing saved yet
    $p = Invoke-CPGit $RepoPath push -u origin HEAD
    if ($p.Code -ne 0) {
        throw ("Linked, but the upload failed. If the GitHub repo is not empty (for example it has a README), " +
               "create a new empty one instead.`n`n$($p.Output)")
    }
    return $true
}

function Get-CPFileWebUrl {
    <# GitHub page of a file in the solutions repo (current branch). #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$RelPath)
    $base = Get-CPRepoWebUrl $RepoPath
    if (-not $base) { return $null }
    $branch = (Invoke-CPGit $RepoPath rev-parse --abbrev-ref HEAD).Output
    if (-not $branch -or $branch -eq 'HEAD') { $branch = 'main' }
    $path = (($RelPath -replace '\\', '/') -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "$base/blob/$branch/$path"
}

function Get-CPRepoWebUrl {
    param([Parameter(Mandatory)][string]$RepoPath)
    $r = Invoke-CPGit $RepoPath remote get-url origin
    if ($r.Code -ne 0 -or -not $r.Output) { return $null }   # not connected to GitHub (or any remote)
    $u = $r.Output.Trim() -replace '\.git$', ''
    if ($u -match '^git@([^:]+):(.+)$') { $u = "https://$($Matches[1])/$($Matches[2])" }
    if ($u -notmatch '^https?://') { return $null }          # a local folder remote has no web page
    $u = $u -replace '^(https?://)[^/@]+@', '$1'             # drop a user name in the URL
    return $u
}

# ----------------------------------------------------------------------------
#  Analytics report (an HTML page with SVG charts, built from the solutions folder)
# ----------------------------------------------------------------------------
#  Everything comes from the solution headers, so all problems saved so far (by any version) count.
#  Colors follow a validated palette: one blue ramp for magnitude, fixed categorical order for levels.

function Get-CPExtreme {
    <# Largest (or -Min smallest) .Value of a list of hashtables (Measure-Object can't read hashtable keys in PS 5.1). #>
    param([object[]]$Items, [switch]$Max, [switch]$Min)
    $best = $null
    foreach ($i in @($Items)) { $v = [double]$i.Value; if ($null -eq $best -or ($Min -and $v -lt $best) -or (-not $Min -and $v -gt $best)) { $best = $v } }
    if ($null -eq $best) { return 0 }
    return $best
}

function ConvertTo-CPHtml([string]$Text) { return [System.Net.WebUtility]::HtmlEncode([string]$Text) }

function Format-CPNum([double]$n) { return $n.ToString('0.#', [Globalization.CultureInfo]::InvariantCulture) }

function Get-CPReportData {
    <# Everything the report shows, as a hashtable (also handy for tests). One entry per problem:
       the same problem saved in two languages counts once. #>
    param([Parameter(Mandatory)][string]$RepoPath, [datetime]$Today = (Get-Date).Date)
    $all = @(Get-CPAllSolutions $RepoPath)
    $byNum = @{}
    foreach ($s in $all) {
        $n = [int]$s.Number
        if (-not $byNum.ContainsKey($n)) { $byNum[$n] = New-Object System.Collections.Generic.List[object] }
        $byNum[$n].Add($s)
    }
    $problems = New-Object System.Collections.Generic.List[object]
    foreach ($n in ($byNum.Keys | Sort-Object)) {
        $g = @($byNum[$n] | Sort-Object DateSolved, RelPath)
        $p = $g[0]
        $d = [datetime]::MinValue
        $ok = [datetime]::TryParseExact([string]$p.DateSolved, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)
        $lvl = ($g | Where-Object { $_.Level } | Select-Object -First 1).Level
        $problems.Add([pscustomobject]@{
            Number = $n; Name = $p.Name; Link = $p.Link; Platform = $p.Platform; Difficulty = $p.Difficulty
            Rating = (Get-CPRatingNumber $p.Difficulty); Level = $(if ($lvl) { $lvl } else { '' })
            Topics = @($g | ForEach-Object { $_.Topics } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
            Date = $(if ($ok) { $d.Date } else { $null }); DateText = $p.DateSolved
            Starred = [bool](@($g | Where-Object { $_.Starred }).Count); Languages = @($g | ForEach-Object { $_.Language } | Select-Object -Unique)
            RelPath = $p.RelPath
        })
    }
    $dated = @($problems | Where-Object { $_.Date })
    $perDay = @{}
    foreach ($p in $dated) { $k = $p.Date.ToString('yyyy-MM-dd'); $perDay[$k] = 1 + [int]$perDay[$k] }
    # streaks (days in a row with at least one problem)
    $cur = 0; $d = $Today
    if (-not $perDay.ContainsKey($d.ToString('yyyy-MM-dd'))) { $d = $d.AddDays(-1) }
    while ($perDay.ContainsKey($d.ToString('yyyy-MM-dd'))) { $cur++; $d = $d.AddDays(-1) }
    $best = 0; $run = 0; $prev = $null
    foreach ($k in ($perDay.Keys | Sort-Object)) {
        $dd = [datetime]::ParseExact($k, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($prev -and ($dd - $prev).TotalDays -eq 1) { $run++ } else { $run = 1 }
        if ($run -gt $best) { $best = $run }
        $prev = $dd
    }
    $monthStart = New-Object datetime($Today.Year, $Today.Month, 1)
    return @{
        Today = $Today; Files = $all.Count; Problems = $problems.ToArray(); PerDay = $perDay
        Total = $problems.Count
        Week = @($dated | Where-Object { $_.Date -gt $Today.AddDays(-7) }).Count
        Month = @($dated | Where-Object { $_.Date -ge $monthStart }).Count
        ActiveDays = $perDay.Count; CurrentStreak = $cur; LongestStreak = $best
        Languages = @($all | Group-Object Language | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } })
    }
}

# --- small SVG chart helpers (each returns an <svg> string) ----------------------------------

function New-CPSvgHBars {
    <# Horizontal bars: rows of @{ Label; Value; Color; Tip }. Value labels at the bar ends. #>
    param([object[]]$Rows, [int]$Width = 520, [int]$LabelWidth = 150, [string]$Unit = '')
    $rows = @($Rows)
    if ($rows.Count -eq 0) { return '<p class="empty">Nothing yet.</p>' }
    $max = [double]((Get-CPExtreme $rows -Max)); if ($max -le 0) { $max = 1 }
    $rowH = 24; $barH = 14; $plotW = $Width - $LabelWidth - 50
    $h = $rows.Count * $rowH + 4
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $Width $h"" width=""100%"" role=""img"">")
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]; $y = $i * $rowH + 4
        $w = [Math]::Max(2.0, [Math]::Round($plotW * [double]$r.Value / $max, 1))
        $col = if ($r.Color) { $r.Color } else { 'var(--series-1)' }
        $tip = if ($r.Tip) { $r.Tip } else { "$($r.Label): $($r.Value)$Unit" }
        [void]$sb.Append("<g><title>$(ConvertTo-CPHtml $tip)</title>")
        [void]$sb.Append("<rect x=""0"" y=""$($y - 2)"" width=""$Width"" height=""$rowH"" fill=""transparent""/>")
        [void]$sb.Append("<text x=""$($LabelWidth - 8)"" y=""$($y + 11)"" class=""lbl"" text-anchor=""end"">$(ConvertTo-CPHtml $r.Label)</text>")
        [void]$sb.Append("<rect x=""$LabelWidth"" y=""$y"" width=""$w"" height=""$barH"" rx=""4"" fill=""$col""/>")
        [void]$sb.Append("<text x=""$($LabelWidth + $w + 6)"" y=""$($y + 11)"" class=""val"">$($r.Value)$Unit</text></g>")
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

function New-CPSvgColumns {
    <# Vertical columns: @{ Label; Value; Tip }. -LabelEvery thins the x labels. #>
    param([object[]]$Cols, [int]$Width = 560, [int]$Height = 190, [int]$LabelEvery = 1, [string]$Color = 'var(--series-1)')
    $cols = @($Cols)
    if ($cols.Count -eq 0) { return '<p class="empty">Nothing yet.</p>' }
    $max = [double]((Get-CPExtreme $cols -Max)); if ($max -le 0) { $max = 1 }
    $left = 30; $bottom = 24; $top = 14; $plotW = $Width - $left - 6; $plotH = $Height - $bottom - $top
    $step = $plotW / $cols.Count; $bw = [Math]::Max(3.0, [Math]::Min(28.0, $step - 2))
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $Width $Height"" width=""100%"" role=""img"">")
    $tick = [Math]::Max(1, [Math]::Ceiling($max / 4))
    for ($t = 0; $t -le $max; $t += $tick) {
        $y = [Math]::Round($top + $plotH - $plotH * $t / $max, 1)
        [void]$sb.Append("<line x1=""$left"" x2=""$Width"" y1=""$y"" y2=""$y"" class=""grid""/><text x=""$($left - 6)"" y=""$($y + 4)"" class=""tick"" text-anchor=""end"">$t</text>")
    }
    $maxI = 0; for ($i = 1; $i -lt $cols.Count; $i++) { if ($cols[$i].Value -gt $cols[$maxI].Value) { $maxI = $i } }
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $c = $cols[$i]
        $x = [Math]::Round($left + $i * $step + ($step - $bw) / 2, 1)
        $bh = [Math]::Round($plotH * [double]$c.Value / $max, 1)
        $y = $top + $plotH - $bh
        $tip = if ($c.Tip) { $c.Tip } else { "$($c.Label): $($c.Value)" }
        [void]$sb.Append("<g><title>$(ConvertTo-CPHtml $tip)</title><rect x=""$([Math]::Round($left + $i * $step, 1))"" y=""$top"" width=""$([Math]::Round($step, 1))"" height=""$plotH"" fill=""transparent""/>")
        if ($c.Value -gt 0) {
            # rounded top, square at the baseline
            $r = [Math]::Min(4.0, [Math]::Min($bw / 2, $bh))
            [void]$sb.Append("<path d=""M$x,$($top + $plotH) V$($y + $r) Q$x,$y $($x + $r),$y H$($x + $bw - $r) Q$($x + $bw),$y $($x + $bw),$($y + $r) V$($top + $plotH) Z"" fill=""$Color""/>")
        }
        if ($i -eq $maxI -and $c.Value -gt 0) { [void]$sb.Append("<text x=""$($x + $bw / 2)"" y=""$($y - 4)"" class=""val"" text-anchor=""middle"">$($c.Value)</text>") }
        [void]$sb.Append('</g>')
        if ($i % $LabelEvery -eq 0) { [void]$sb.Append("<text x=""$($x + $bw / 2)"" y=""$($Height - 6)"" class=""tick"" text-anchor=""middle"">$(ConvertTo-CPHtml $c.Label)</text>") }
    }
    [void]$sb.Append("<line x1=""$left"" x2=""$Width"" y1=""$($top + $plotH)"" y2=""$($top + $plotH)"" class=""axis""/></svg>")
    return $sb.ToString()
}

function New-CPSvgLine {
    <# One line (2px) with dots on hover: @{ Label; Value; Tip }. #>
    param([object[]]$Points, [int]$Width = 560, [int]$Height = 190, [int]$LabelEvery = 1, [double]$MinY = 0)
    $pts = @($Points)
    if ($pts.Count -lt 2) { return '<p class="empty">Needs at least two points - keep solving!</p>' }
    $max = [double]((Get-CPExtreme $pts -Max))
    if ($MinY -lt 0) { $MinY = [double]((Get-CPExtreme $pts -Min)) * 0.9 }
    if ($max -le $MinY) { $max = $MinY + 1 }
    $left = 40; $bottom = 24; $top = 14; $plotW = $Width - $left - 10; $plotH = $Height - $bottom - $top
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $Width $Height"" width=""100%"" role=""img"">")
    for ($k = 0; $k -le 4; $k++) {
        $v = $MinY + ($max - $MinY) * $k / 4; $y = [Math]::Round($top + $plotH - $plotH * $k / 4, 1)
        [void]$sb.Append("<line x1=""$left"" x2=""$Width"" y1=""$y"" y2=""$y"" class=""grid""/><text x=""$($left - 6)"" y=""$($y + 4)"" class=""tick"" text-anchor=""end"">$([Math]::Round($v))</text>")
    }
    $xy = @()
    for ($i = 0; $i -lt $pts.Count; $i++) {
        $x = [Math]::Round($left + $plotW * $i / ($pts.Count - 1), 1)
        $y = [Math]::Round($top + $plotH - $plotH * ([double]$pts[$i].Value - $MinY) / ($max - $MinY), 1)
        $xy += ,@($x, $y)
    }
    [void]$sb.Append("<polyline fill=""none"" stroke=""var(--series-1)"" stroke-width=""2"" stroke-linejoin=""round"" points=""$(($xy | ForEach-Object { "$($_[0]),$($_[1])" }) -join ' ')""/>")
    for ($i = 0; $i -lt $pts.Count; $i++) {
        $p = $pts[$i]; $tip = if ($p.Tip) { $p.Tip } else { "$($p.Label): $($p.Value)" }
        [void]$sb.Append("<g class=""pt""><title>$(ConvertTo-CPHtml $tip)</title><rect x=""$($xy[$i][0] - 6)"" y=""$top"" width=""12"" height=""$plotH"" fill=""transparent""/><circle cx=""$($xy[$i][0])"" cy=""$($xy[$i][1])"" r=""4.5"" fill=""var(--series-1)"" stroke=""var(--surface-1)"" stroke-width=""2""/></g>")
        if ($i % $LabelEvery -eq 0 -or $i -eq $pts.Count - 1) { [void]$sb.Append("<text x=""$($xy[$i][0])"" y=""$($Height - 6)"" class=""tick"" text-anchor=""middle"">$(ConvertTo-CPHtml $p.Label)</text>") }
    }
    $last = $pts[$pts.Count - 1]
    [void]$sb.Append("<text x=""$([Math]::Min($Width - 4, $xy[$pts.Count - 1][0]))"" y=""$($xy[$pts.Count - 1][1] - 10)"" class=""val"" text-anchor=""end"">$($last.Value)</text>")
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

function New-CPSvgCalendar {
    <# The last 53 weeks, one square per day (Monday on top), darker = more problems. #>
    param([hashtable]$PerDay, [datetime]$Today)
    $ramp = @('var(--empty-cell)', 'var(--heat-1)', 'var(--heat-2)', 'var(--heat-3)', 'var(--heat-4)')
    $cell = 11; $gap = 3; $left = 28; $top = 18
    $dow = ([int]$Today.DayOfWeek + 6) % 7                      # 0 = Monday
    $start = $Today.AddDays(-$dow).AddDays(-52 * 7)
    $w = $left + 53 * ($cell + $gap); $h = $top + 7 * ($cell + $gap) + 4
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $w $h"" width=""100%"" role=""img"">")
    foreach ($r in @(@(0, 'Mon'), @(2, 'Wed'), @(4, 'Fri'))) { [void]$sb.Append("<text x=""0"" y=""$($top + $r[0] * ($cell + $gap) + 9)"" class=""tick"">$($r[1])</text>") }
    $lastMonth = -1; $lastLabelWk = -10
    for ($wk = 0; $wk -lt 53; $wk++) {
        $colDate = $start.AddDays($wk * 7)
        if ($colDate.Month -ne $lastMonth) {
            if ($wk -lt 51 -and ($wk - $lastLabelWk) -ge 3) { $lastLabelWk = $wk; [void]$sb.Append("<text x=""$($left + $wk * ($cell + $gap))"" y=""11"" class=""tick"">$($colDate.ToString('MMM', [Globalization.CultureInfo]::InvariantCulture))</text>") }
            $lastMonth = $colDate.Month
        }
        for ($dd = 0; $dd -lt 7; $dd++) {
            $day = $colDate.AddDays($dd)
            if ($day -gt $Today) { continue }
            $k = $day.ToString('yyyy-MM-dd'); $n = [int]$PerDay[$k]
            $lvl = if ($n -le 0) { 0 } elseif ($n -eq 1) { 1 } elseif ($n -eq 2) { 2 } elseif ($n -le 4) { 3 } else { 4 }
            $label = $day.ToString('ddd d MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
            [void]$sb.Append("<rect x=""$($left + $wk * ($cell + $gap))"" y=""$($top + $dd * ($cell + $gap))"" width=""$cell"" height=""$cell"" rx=""2"" fill=""$($ramp[$lvl])""><title>$label - $n problem$(if ($n -ne 1) { 's' })</title></rect>")
        }
    }
    [void]$sb.Append('</svg>')
    $legend = '<div class="legend">Less ' + (($ramp | ForEach-Object { "<span class=""sq"" style=""background:$_""></span>" }) -join '') + ' More</div>'
    return $sb.ToString() + $legend
}

function ConvertTo-CPReportTable {
    param([object[]]$Problems, [switch]$ShowStar)
    $rows = @($Problems)
    if ($rows.Count -eq 0) { return '<p class="empty">Nothing yet.</p>' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table><thead><tr><th>#</th><th>Problem</th><th>Platform</th><th>Difficulty</th><th>Level</th><th>Solved</th></tr></thead><tbody>')
    foreach ($p in $rows) {
        $nm = ConvertTo-CPHtml $p.Name
        if ($p.Link) { $nm = "<a href=""$(ConvertTo-CPHtml $p.Link)"">$nm</a>" }
        if ($ShowStar -and $p.Starred) { $nm = '&#9733; ' + $nm }
        [void]$sb.Append("<tr><td class=""num"">$($p.Number)</td><td>$nm</td><td>$(ConvertTo-CPHtml $p.Platform)</td><td>$(ConvertTo-CPHtml $p.Difficulty)</td><td>$(ConvertTo-CPHtml $p.Level)</td><td>$(ConvertTo-CPHtml $p.DateText)</td></tr>")
    }
    [void]$sb.Append('</tbody></table>')
    return $sb.ToString()
}

$script:CommonTopics = @('implementation', 'math', 'greedy', 'brute force', 'strings', 'sortings', 'constructive algorithms',
    'binary search', 'dp', 'data structures', 'number theory', 'two pointers', 'graphs', 'trees', 'dfs and similar',
    'bitmasks', 'combinatorics', 'prefix sums', 'shortest paths', 'dsu', 'hashing', 'geometry', 'games', 'probabilities')

function New-CPReportHtml {
    <# The whole report page as HTML text. #>
    param([Parameter(Mandatory)][string]$RepoPath, [datetime]$Today = (Get-Date).Date)
    $d = Get-CPReportData -RepoPath $RepoPath -Today $Today
    $probs = @($d.Problems)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $levelColor = @{ Easy = 'var(--series-1)'; Medium = 'var(--series-2)'; Hard = 'var(--series-3)'; Unrated = 'var(--unrated)' }

    # cards
    $cards = @(
        @('Problems solved', $d.Total, $(if ($d.Files -ne $d.Total) { "$($d.Files) solution files" } else { 'all time' })),
        @('This week', $d.Week, 'last 7 days'),
        @('This month', $d.Month, $Today.ToString('MMMM yyyy', $inv)),
        @('Current streak', $d.CurrentStreak, $(if ($d.CurrentStreak -eq 1) { 'day' } else { 'days in a row' })),
        @('Longest streak', $d.LongestStreak, 'days'),
        @('Active days', $d.ActiveDays, 'days with a solve')
    )
    $cardHtml = ($cards | ForEach-Object { "<div class=""card stat""><div class=""k"">$($_[0])</div><div class=""v"">$($_[1])</div><div class=""s"">$(ConvertTo-CPHtml $_[2])</div></div>" }) -join ''

    # progress over time: total by week (all history, at most ~60 points) and per week (last 26)
    $dated = @($probs | Where-Object { $_.Date } | Sort-Object Date)
    $weekStart = { param($x) $x.AddDays(-(([int]$x.DayOfWeek + 6) % 7)) }
    $cumPts = @(); $weekCols = @()
    if ($dated.Count) {
        $w0 = & $weekStart $dated[0].Date; $wEnd = & $weekStart $Today
        $weeks = [int](($wEnd - $w0).TotalDays / 7) + 1
        $stride = [Math]::Max(1, [Math]::Ceiling($weeks / 60))
        $perWeek = @{}
        foreach ($p in $dated) { $k = (& $weekStart $p.Date).ToString('yyyy-MM-dd'); $perWeek[$k] = 1 + [int]$perWeek[$k] }
        $run = 0
        for ($i = 0; $i -lt $weeks; $i++) {
            $wd = $w0.AddDays(7 * $i); $run += [int]$perWeek[$wd.ToString('yyyy-MM-dd')]
            if ($i % $stride -eq 0 -or $i -eq $weeks - 1) { $cumPts += @{ Label = $wd.ToString('d MMM', $inv); Value = $run; Tip = "Week of $($wd.ToString('d MMM yyyy', $inv)): $run solved in total" } }
        }
        for ($i = 25; $i -ge 0; $i--) {
            $wd = $wEnd.AddDays(-7 * $i); $n = [int]$perWeek[$wd.ToString('yyyy-MM-dd')]
            $weekCols += @{ Label = $wd.ToString('d MMM', $inv); Value = $n; Tip = "Week of $($wd.ToString('d MMM yyyy', $inv)): $n problem$(if ($n -ne 1) { 's' })" }
        }
    }

    # levels
    $levelRows = @()
    foreach ($l in @('Easy', 'Medium', 'Hard', 'Unrated')) {
        $n = @($probs | Where-Object { $(if ($_.Level) { $_.Level } else { 'Unrated' }) -eq $l }).Count
        if ($n -gt 0 -or $l -ne 'Unrated') {
            $pct = if ($d.Total) { [Math]::Round(100.0 * $n / $d.Total) } else { 0 }
            $levelRows += @{ Label = $l; Value = $n; Color = $levelColor[$l]; Tip = "${l}: $n problems ($pct%)" }
        }
    }
    # ratings (Codeforces-style numbers) in bands of 100
    $rated = @($probs | Where-Object { $_.Rating -gt 0 })
    $bandCols = @()
    if ($rated.Count) {
        $lo = [Math]::Floor((($rated | Measure-Object Rating -Minimum).Minimum) / 100) * 100
        $hi = [Math]::Floor((($rated | Measure-Object Rating -Maximum).Maximum) / 100) * 100
        for ($b = $lo; $b -le $hi; $b += 100) { $n = @($rated | Where-Object { $_.Rating -ge $b -and $_.Rating -lt $b + 100 }).Count; $bandCols += @{ Label = [string]$b; Value = $n; Tip = "Rating ${b}: $n problems" } }
    }
    # average rating by month
    $avgPts = @()
    foreach ($g in ($rated | Where-Object { $_.Date } | Group-Object { $_.Date.ToString('yyyy-MM') } | Sort-Object Name)) {
        $avg = [Math]::Round(($g.Group | Measure-Object Rating -Average).Average)
        $md = [datetime]::ParseExact($g.Name + '-01', 'yyyy-MM-dd', $inv)
        $avgPts += @{ Label = $md.ToString('MMM yy', $inv); Value = $avg; Tip = "$($md.ToString('MMMM yyyy', $inv)): average rating $avg over $($g.Count) problem$(if ($g.Count -ne 1) { 's' })" }
    }
    # topics
    $topicCount = @{}
    foreach ($p in $probs) { foreach ($t in $p.Topics) { if ($t) { $topicCount[$t] = 1 + [int]$topicCount[$t] } } }
    $topTopics = @($topicCount.Keys | Sort-Object { -$topicCount[$_] }, { $_ } | Select-Object -First 15)
    $topicRows = @($topTopics | ForEach-Object { @{ Label = $_; Value = $topicCount[$_] } })
    $few = @($topicCount.Keys | Where-Object { $topicCount[$_] -le 2 } | Sort-Object)
    $missing = @($script:CommonTopics | Where-Object { -not $topicCount.ContainsKey($_) })
    # topic x level
    $matrixTopics = @($topTopics | Select-Object -First 12)
    $mx = New-Object System.Text.StringBuilder
    if ($matrixTopics.Count) {
        $cellMax = 1
        $cellsData = @{}
        foreach ($t in $matrixTopics) { foreach ($l in @('Easy', 'Medium', 'Hard', 'Unrated')) {
            $n = @($probs | Where-Object { $_.Topics -contains $t -and $(if ($_.Level) { $_.Level } else { 'Unrated' }) -eq $l }).Count
            $cellsData["$t|$l"] = $n; if ($n -gt $cellMax) { $cellMax = $n } } }

        [void]$mx.Append('<table class="matrix"><thead><tr><th>Topic</th><th>Easy</th><th>Medium</th><th>Hard</th><th>Unrated</th></tr></thead><tbody>')
        foreach ($t in $matrixTopics) {
            [void]$mx.Append("<tr><td>$(ConvertTo-CPHtml $t)</td>")
            foreach ($l in @('Easy', 'Medium', 'Hard', 'Unrated')) {
                $n = $cellsData["$t|$l"]
                $si = if ($n -le 0) { 0 } else { [Math]::Min(5, 1 + [Math]::Floor(4.999 * ($n - 1) / [Math]::Max(1, $cellMax - 1))) }
                [void]$mx.Append("<td class=""cell m$si"" title=""$(ConvertTo-CPHtml $t), ${l}: $n"">$(if ($n) { $n } else { '' })</td>")
            }
            [void]$mx.Append('</tr>')
        }
        [void]$mx.Append('</tbody></table>')
    }
    $platRows = @($probs | Group-Object Platform | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } })
    $langRows = @($d.Languages | ForEach-Object { @{ Label = $_.Label; Value = $_.Value; Tip = "$($_.Label): $($_.Value) solution files" } })

    $hardest = @($probs | Sort-Object @{ Expression = { $_.Rating }; Descending = $true }, @{ Expression = { Get-CPLevelRank $_.Level }; Descending = $true }, Number | Where-Object { $_.Rating -gt 0 -or $_.Level -eq 'Hard' } | Select-Object -First 10)
    $stars = @($probs | Where-Object { $_.Starred } | Sort-Object Number)
    $recent = @($probs | Sort-Object @{ Expression = { $_.DateText }; Descending = $true }, @{ Expression = { $_.Number }; Descending = $true } | Select-Object -First 10)

    $repoName = Split-Path ((Resolve-Path -LiteralPath $RepoPath).ProviderPath) -Leaf
    $practice = ''
    if ($few.Count -or $missing.Count) {
        $practice = '<div class="hint"><b>Practice next.</b> '
        if ($few.Count) { $practice += 'Only 1-2 problems so far: ' + (($few | Select-Object -First 14 | ForEach-Object { ConvertTo-CPHtml $_ }) -join ', ') + '. ' }
        if ($missing.Count) { $practice += 'Common topics not tried yet: ' + (($missing | Select-Object -First 14 | ForEach-Object { ConvertTo-CPHtml $_ }) -join ', ') + '.' }
        $practice += '</div>'
    }
    $avgHtml = if ($avgPts.Count -ge 2) { New-CPSvgLine -Points $avgPts -Width 1120 -Height 210 -LabelEvery ([Math]::Max(1, [Math]::Ceiling($avgPts.Count / 12))) -MinY -1 } elseif ($avgPts.Count -eq 1) { "<p class=""empty"">One month so far: average rating $($avgPts[0].Value).</p>" } else { '<p class="empty">No numeric ratings yet (they come from Codeforces, or write one in the header).</p>' }

    $css = @'
.viz-root{color-scheme:light;--surface-1:#ffffff;--page:#f9f9f9;--text-primary:#191919;--text-secondary:#666666;--grid:#e7e7e7;--axis:#c2c2c2;--border:rgba(11,11,11,0.10);
--series-1:#257de0;--series-2:#f47230;--series-3:#00b894;--unrated:#a3a3a3;--empty-cell:#eeeeee;--link:#1b64be;
--heat-1:#b6d5f8;--heat-2:#6aabf1;--heat-3:#257de0;--heat-4:#1757ac;
--m1:#cce3fd;--m2:#9dc8f7;--m3:#6aabf1;--m4:#338ced;--m5:#1b64be;--m-ink:#191919;--m-ink-strong:#ffffff}
@media (prefers-color-scheme: dark){.viz-root{color-scheme:dark;--surface-1:#191919;--page:#0b0b0b;--text-primary:#efefef;--text-secondary:#9c9c9c;--grid:#303030;--axis:#474747;--border:rgba(255,255,255,0.10);
--series-1:#338ced;--series-2:#e76624;--series-3:#00a888;--unrated:#6b6b6b;--empty-cell:#262626;--link:#84b9f3;
--heat-1:#0f4a96;--heat-2:#1b64be;--heat-3:#338ced;--heat-4:#84b9f3;
--m1:#0e3d7e;--m2:#0f4a96;--m3:#1b64be;--m4:#519ced;--m5:#9dc8f7;--m-ink:#efefef;--m-ink-strong:#0b0b0b}}
*{box-sizing:border-box}body{margin:0;font-family:"Segoe UI",system-ui,sans-serif;background:var(--page);color:var(--text-primary)}
.wrap{max-width:1180px;margin:0 auto;padding:28px 24px 40px}
header{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-bottom:18px}
h1{font-size:26px;margin:0}h2{font-size:15px;margin:0 0 4px}.sub{color:var(--text-secondary);font-size:13px}
.grid6{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;margin-bottom:12px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px}
.card{background:var(--surface-1);border:1px solid var(--border);border-radius:10px;padding:16px 18px}
.stat .k{font-size:12px;color:var(--text-secondary)}.stat .v{font-size:30px;font-weight:600;margin:2px 0}.stat .s{font-size:12px;color:var(--text-secondary)}
.full{margin-bottom:12px}.desc{color:var(--text-secondary);font-size:12px;margin:0 0 10px}
svg.chart{display:block;overflow:visible}svg text{font-family:inherit}
.lbl{font-size:12px;fill:var(--text-primary)}.val{font-size:11px;fill:var(--text-secondary)}.tick{font-size:10px;fill:var(--text-secondary)}
.grid{stroke:var(--grid);stroke-width:1}.axis{stroke:var(--axis);stroke-width:1}
g:hover > rect[fill^="var(--series"], g:hover > path{opacity:.8}.pt:hover circle{r:6}
.legend{font-size:11px;color:var(--text-secondary);display:flex;align-items:center;gap:3px;justify-content:flex-end;margin-top:6px}
.sq{display:inline-block;width:11px;height:11px;border-radius:2px}
table{width:100%;border-collapse:collapse;font-size:13px}th{text-align:left;color:var(--text-secondary);font-weight:600;border-bottom:1px solid var(--grid);padding:6px 8px}
td{border-bottom:1px solid var(--grid);padding:6px 8px}td.num{color:var(--text-secondary);width:40px}a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
.matrix td.cell{text-align:center;width:72px;font-weight:600;border:2px solid var(--surface-1);border-radius:4px}
.m0{background:var(--empty-cell)}.m1{background:var(--m1);color:var(--m-ink)}.m2{background:var(--m2);color:var(--m-ink)}.m3{background:var(--m3);color:var(--m-ink)}.m4{background:var(--m4);color:var(--m-ink-strong)}.m5{background:var(--m5);color:var(--m-ink-strong)}
.hint{font-size:13px;background:var(--page);border-radius:8px;padding:10px 12px;margin-top:12px;color:var(--text-primary)}
.empty{color:var(--text-secondary);font-size:13px}footer{color:var(--text-secondary);font-size:12px;margin-top:18px;text-align:center}
@media (max-width:900px){.grid6{grid-template-columns:repeat(3,1fr)}.grid2{grid-template-columns:1fr}}
'@
    $html = New-Object System.Text.StringBuilder
    [void]$html.Append("<!DOCTYPE html><html lang=""en""><head><meta charset=""utf-8""><meta name=""viewport"" content=""width=device-width,initial-scale=1""><title>Problem solving report</title><style>$css</style></head><body class=""viz-root""><div class=""wrap"">")
    [void]$html.Append("<header><div><h1>Problem solving report</h1><div class=""sub"">$(ConvertTo-CPHtml $repoName) &middot; $($d.Total) problems &middot; made $($Today.ToString('d MMMM yyyy', $inv)) by CP Solution Saver</div></div><div class=""sub"">Hover a bar, dot or square for details</div></header>")
    [void]$html.Append("<div class=""grid6"">$cardHtml</div>")
    [void]$html.Append("<div class=""card full""><h2>Activity in the last year</h2><p class=""desc"">One square per day; a stronger blue means more problems solved that day.</p>$(New-CPSvgCalendar -PerDay $d.PerDay -Today $Today)</div>")
    [void]$html.Append("<div class=""grid2""><div class=""card""><h2>Total solved over time</h2><p class=""desc"">Running total, week by week.</p>$(New-CPSvgLine -Points $cumPts -LabelEvery ([Math]::Max(1, [Math]::Ceiling($cumPts.Count / 7))))</div>")
    [void]$html.Append("<div class=""card""><h2>Problems per week</h2><p class=""desc"">The last 26 weeks.</p>$(New-CPSvgColumns -Cols $weekCols -LabelEvery 4)</div></div>")
    [void]$html.Append("<div class=""grid2""><div class=""card""><h2>By level</h2><p class=""desc"">Easy / Medium / Hard from LeetCode, your header, or the rating (under $script:LevelMediumFrom Easy, under $script:LevelHardFrom Medium).</p>$(New-CPSvgHBars -Rows $levelRows -LabelWidth 90)</div>")
    [void]$html.Append("<div class=""card""><h2>By rating</h2><p class=""desc"">Problems with a numeric rating (mostly Codeforces), in bands of 100.</p>$(New-CPSvgColumns -Cols $bandCols -LabelEvery ([Math]::Max(1, [Math]::Ceiling($bandCols.Count / 10))))</div></div>")
    [void]$html.Append("<div class=""card full""><h2>Average rating by month</h2><p class=""desc"">Are you taking on harder problems? (Only problems with a numeric rating.)</p>$avgHtml</div>")
    [void]$html.Append("<div class=""grid2""><div class=""card""><h2>Top topics</h2><p class=""desc"">The 15 topics you solved most.</p>$(New-CPSvgHBars -Rows $topicRows)$practice</div>")
    [void]$html.Append("<div class=""card""><h2>Topics by level</h2><p class=""desc"">Your top topics split by level - empty cells are gaps worth practicing.</p>$(if ($mx.Length) { $mx.ToString() } else { '<p class=empty>No topics yet.</p>' })</div></div>")
    [void]$html.Append("<div class=""grid2""><div class=""card""><h2>Platforms</h2>$(New-CPSvgHBars -Rows $platRows -LabelWidth 110)</div><div class=""card""><h2>Languages</h2><p class=""desc"">Solution files per language.</p>$(New-CPSvgHBars -Rows $langRows -LabelWidth 110)</div></div>")
    [void]$html.Append("<div class=""grid2""><div class=""card""><h2>Hardest solved</h2>$(ConvertTo-CPReportTable -Problems $hardest -ShowStar)</div><div class=""card""><h2>Recently solved</h2>$(ConvertTo-CPReportTable -Problems $recent -ShowStar)</div></div>")
    [void]$html.Append("<div class=""card full""><h2>&#9733; Starred</h2>$(if ($stars.Count) { ConvertTo-CPReportTable -Problems $stars } else { '<p class=empty>No starred problems yet - star one in Solved problems.</p>' })</div>")
    [void]$html.Append("<footer>Built from the headers of the solution files in $(ConvertTo-CPHtml $repoName). Nothing is sent anywhere.</footer></div></body></html>")
    return $html.ToString()
}

function Save-CPReport {
    <# Writes the report page and returns its path (default: %APPDATA%\CPSolutionSaver\report.html). #>
    param([Parameter(Mandatory)][string]$RepoPath, [string]$Path)
    if (-not $Path) { $Path = Join-Path (Get-CPDataDir) 'report.html' }
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, (New-CPReportHtml -RepoPath $RepoPath), (New-Object System.Text.UTF8Encoding($false)))
    return $Path
}

# ----------------------------------------------------------------------------
#  Updates (GitHub releases of the app itself)
# ----------------------------------------------------------------------------
#  The tray app calls Test-CPUpdateCheckDue now and then, Get-CPLatestRelease in the background,
#  and asks the user (Show-CPUpdateDialog) when Test-CPUpdateAvailable is true. "Update now" runs
#  Save-CPUpdatePackage (download + extract) and starts the new installer with -Gui -Update.

$script:UpdateRepo = 'MostafaSamyFayez/CP-Solution-Saver'
$script:UpdateAsset = 'CP-Solution-Saver.zip'

function Get-CPCurrentVersion {
    <# The installed version. CPSAVER_CURRENT_VERSION pretends an older one (to test updates). #>
    if ($env:CPSAVER_CURRENT_VERSION) { return $env:CPSAVER_CURRENT_VERSION }
    return (Get-CPAppVersion)
}

function Compare-CPVersion {
    <# -1 / 0 / 1 like a comparer: 2.10.0 > 2.9.1; a leading "v" is ignored; missing parts count as 0. #>
    param([string]$A, [string]$B)
    $pa = @(([string]$A).Trim().TrimStart('v', 'V') -split '[.\-+]' | Select-Object -First 4 | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
    $pb = @(([string]$B).Trim().TrimStart('v', 'V') -split '[.\-+]' | Select-Object -First 4 | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
    for ($i = 0; $i -lt 4; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

function ConvertTo-CPReleaseInfo {
    <# A GitHub "release" object -> @{ Version; Notes; Page; ZipUrl; Published } #>
    param([Parameter(Mandatory)]$Release)
    $asset = @($Release.assets) | Where-Object { $_ -and $_.name -eq $script:UpdateAsset } | Select-Object -First 1
    return @{
        Version   = ([string]$Release.tag_name).Trim().TrimStart('v', 'V')
        Notes     = [string]$Release.body
        Page      = [string]$Release.html_url
        ZipUrl    = $(if ($asset) { [string]$asset.browser_download_url } else { '' })
        Published = [string]$Release.published_at
    }
}

function Get-CPLatestRelease {
    <# The newest published release of the app on GitHub (no sign-in needed). Throws on network errors. #>
    param([int]$TimeoutSec = 15)
    Initialize-CPWeb
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$($script:UpdateRepo)/releases/latest" -TimeoutSec $TimeoutSec `
        -Headers @{ 'User-Agent' = 'CPSolutionSaver'; Accept = 'application/vnd.github+json' }
    return (ConvertTo-CPReleaseInfo $r)
}

function Test-CPUpdateAvailable {
    <# $true when the release is newer than this version, has the zip, and was not skipped by the user. #>
    param([Parameter(Mandatory)][hashtable]$Release, [string]$SkippedVersion = '', [switch]$IgnoreSkipped)
    if (-not $Release.ZipUrl) { return $false }
    if ((Compare-CPVersion $Release.Version (Get-CPCurrentVersion)) -le 0) { return $false }
    if (-not $IgnoreSkipped -and $SkippedVersion -and (Compare-CPVersion $Release.Version $SkippedVersion) -eq 0) { return $false }
    return $true
}

function Test-CPUpdateCheckDue {
    <# Automatic checks: on, and the last one was at least -Hours ago. #>
    param([Parameter(Mandatory)]$Config, [int]$Hours = 12, [datetime]$Now = (Get-Date))
    if (-not $Config.AutoUpdateCheck) { return $false }
    $last = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$Config.LastUpdateCheck, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$last)) { return $true }
    return (($Now - $last).TotalHours -ge $Hours)
}

function Save-CPUpdatePackage {
    <# Downloads the release zip to %TEMP% and extracts it. Returns the new installer (app\install.ps1). #>
    param([Parameter(Mandatory)][hashtable]$Release)
    if (-not $Release.ZipUrl) { throw 'This release has no download.' }
    Initialize-CPWeb
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("cpsaver-update-" + $Release.Version)
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $zip = Join-Path $dir $script:UpdateAsset
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow in PS 5.1
    try { Invoke-WebRequest -Uri $Release.ZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = 'CPSolutionSaver' } }
    finally { $ProgressPreference = $old }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dir)
    $installer = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'install.ps1' | Where-Object { $_.Directory.Name -eq 'app' } | Select-Object -First 1
    if (-not $installer) { throw 'The downloaded update does not contain the installer.' }
    Get-ChildItem -LiteralPath $dir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    return $installer.FullName
}

# ============================================================================
#  Code viewer: syntax colouring (tokens -> RTF for a RichTextBox)
# ============================================================================
$script:CodeWords = @{
    'C++' = @{
        Keyword = 'alignas alignof and asm auto break case catch class const constexpr const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern false final for friend goto if inline mutable namespace new noexcept not nullptr operator or override private protected public register reinterpret_cast return sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union using virtual volatile while xor'
        Type    = 'bool char char16_t char32_t double float int long short signed unsigned void wchar_t size_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t string vector map set unordered_map unordered_set multiset multimap pair tuple queue deque stack priority_queue array bitset list ll ull ld pii pll vi vll vvi std'
        Builtin = 'cin cout cerr endl printf scanf puts getline min max swap sort reverse lower_bound upper_bound binary_search accumulate fill memset memcpy abs gcd lcm make_pair push_back pop_back emplace_back begin end size empty insert erase find count clear front back top push pop ios_base sync_with_stdio tie'
    }
    'C' = @{
        Keyword = 'auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while true false NULL'
        Type    = 'bool char double float int long short signed unsigned void size_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE'
        Builtin = 'printf scanf puts gets getchar putchar malloc calloc realloc free memset memcpy strlen strcmp strcpy strcat qsort abs fabs sqrt pow fopen fclose fprintf fscanf'
    }
    'Python' = @{
        Keyword = 'and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case False None True'
        Type    = 'int float str bool list dict set tuple bytes object complex frozenset range'
        Builtin = 'print input len map filter zip enumerate sorted reversed sum min max abs open isinstance super self cls pow divmod ord chr round any all iter next hex bin oct id hash type exit sys stdin readline'
    }
    'Java' = @{
        Keyword = 'abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record yield true false null'
        Type    = 'boolean byte char double float int long short void String Integer Long Double Boolean Character Object List ArrayList Map HashMap Set HashSet TreeMap TreeSet Deque ArrayDeque Queue PriorityQueue Scanner StringBuilder BufferedReader InputStreamReader PrintWriter Arrays Collections Math System'
        Builtin = 'println print printf out in nextInt nextLong next nextLine readLine parseInt parseLong add get put size isEmpty contains sort'
    }
    'C#' = @{
        Keyword = 'abstract as base break case catch checked class const continue default delegate do else enum event explicit extern false finally fixed for foreach goto if implicit in interface internal is lock namespace new null operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw true try typeof unchecked unsafe using var virtual volatile while async await yield get set'
        Type    = 'bool byte char decimal double float int long object sbyte short string uint ulong ushort void List Dictionary HashSet Queue Stack Console Math String'
        Builtin = 'WriteLine Write ReadLine Parse Split Add Count Length'
    }
    'JavaScript' = @{
        Keyword = 'async await break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield true false null undefined'
        Type    = 'Array Object String Number Boolean Map Set Math JSON BigInt Promise'
        Builtin = 'console log require process push pop length parseInt parseFloat split map filter reduce join'
    }
    'Go' = @{
        Keyword = 'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil'
        Type    = 'bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr'
        Builtin = 'append cap close copy delete len make new panic print println recover fmt Println Printf Scan bufio os'
    }
    'Rust' = @{
        Keyword = 'as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while'
        Type    = 'bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize String Vec Option Some None Result Ok Err Box HashMap HashSet'
        Builtin = 'println print format vec read_line unwrap expect push len iter collect'
    }
    'Kotlin' = @{
        Keyword = 'as break class continue do else false for fun if in interface is null object package return super this throw true try typealias val var when while import private public internal protected override open data companion lateinit'
        Type    = 'Int Long Double Float Boolean Char String Unit Any List MutableList Map MutableMap Set Array IntArray LongArray'
        Builtin = 'println print readLine readln toInt toLong split map listOf mutableListOf'
    }
}

function Get-CPCodeTokenizer {
    <# The regex and word lists for one language (cached). #>
    param([string]$Language = 'C++')
    if (-not $script:CodeWords.ContainsKey($Language)) { $Language = 'C++' }
    if (-not $script:CodeTokenizers) { $script:CodeTokenizers = @{} }
    if ($script:CodeTokenizers.ContainsKey($Language)) { return $script:CodeTokenizers[$Language] }
    $words = $script:CodeWords[$Language]
    # word lookups must be case-sensitive ('String' is a type in Java, 'string' is not)
    $kind = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($w in ($words.Builtin -split ' ')) { if ($w) { $kind[$w] = 'builtin' } }
    foreach ($w in ($words.Type -split ' ')) { if ($w) { $kind[$w] = 'type' } }
    foreach ($w in ($words.Keyword -split ' ')) { if ($w) { $kind[$w] = 'keyword' } }
    $q = "'"
    $num = '(?<number>\b(?:0[xX][0-9a-fA-F_' + $q + ']+|0[bB][01_' + $q + ']+|\d[\d_' + $q + ']*(?:\.\d*)?(?:[eE][+-]?\d+)?)[uUlLfFjJ]*\b)'
    $word = '(?<word>[A-Za-z_]\w*)(?<call>[ \t]*\()?'
    if ($Language -eq 'Python') {
        $tq = $q * 3
        $pat = '(?<comment>#[^\n]*)' +
               '|(?<string>(?:[rRbBuUfF]{1,2})?(?:"""[\s\S]*?(?:"""|\z)|' + $tq + '[\s\S]*?(?:' + $tq + '|\z)|"(?:\\.|[^"\\\n])*"?|' + $q + '(?:\\.|[^' + $q + '\\\n])*' + $q + '?))' +
               '|(?<preproc>@[A-Za-z_][\w.]*)|' + $num + '|' + $word
    } else {
        $cmt = '(?<comment>//[^\n]*|/\*[\s\S]*?(?:\*/|\z))'
        $pre = ''
        if ($Language -in @('C++', 'C', 'C#')) { $pre = '|(?<preproc>(?m:^[ \t]*#[ \t]*\w+))|(?<string>(?<=#[ \t]*include[ \t]*)<[^>\n]*>)' }
        $str = '(?<string>R"([^(\s]{0,16})\([\s\S]*?\)\1"|"(?:\\.|[^"\\\n])*"?|`[^`]*`?|' + $q + '(?:\\.|[^' + $q + '\\\n]){0,8}' + $q + ')'
        $pat = $cmt + $pre + '|' + $str + '|' + $num + '|' + $word
    }
    $tk = @{ Regex = (New-Object System.Text.RegularExpressions.Regex($pat)); Kind = $kind }
    $script:CodeTokenizers[$Language] = $tk
    return $tk
}

function Get-CPCodeTokens {
    <# Splits source code into coloured pieces: a list of @{ Text; Kind } where Kind is one of
       plain, comment, string, number, keyword, type, builtin, function, preproc.
       -Language is the name from Get-CPLanguage (C++, C, Python, Java, ...). Joining the Text
       values gives back the code exactly. #>
    param([AllowEmptyString()][string]$Code = '', [string]$Language = 'C++')
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Code) { return ,$out }
    $tk = Get-CPCodeTokenizer $Language
    $pos = 0
    foreach ($m in $tk.Regex.Matches($Code)) {
        if ($m.Index -gt $pos) { $out.Add(@{ Text = $Code.Substring($pos, $m.Index - $pos); Kind = 'plain' }) }
        $g = $m.Groups
        if ($g['word'].Success) {
            $t = $g['word'].Value; $k = $null
            if (-not $tk.Kind.TryGetValue($t, [ref]$k)) { $k = $(if ($g['call'].Success) { 'function' } else { 'plain' }) }
            $out.Add(@{ Text = $t; Kind = $k })
            $rest = $m.Value.Substring($t.Length)
            if ($rest) { $out.Add(@{ Text = $rest; Kind = 'plain' }) }
        } else {
            $k = 'plain'
            foreach ($n in @('comment', 'preproc', 'string', 'number')) { if ($g[$n].Success) { $k = $n; break } }
            $out.Add(@{ Text = $m.Value; Kind = $k })
        }
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Code.Length) { $out.Add(@{ Text = $Code.Substring($pos); Kind = 'plain' }) }
    return ,$out
}

function Get-CPCodeColors {
    <# Colours per token kind (like VS Code Light+ / Dark+). Ordered hashtable kind -> '#rrggbb'. #>
    param([switch]$Dark)
    if ($Dark) {
        return [ordered]@{ background = '#1e1e1e'; plain = '#d4d4d4'; comment = '#6a9955'; string = '#ce9178'; number = '#b5cea8'
                           keyword = '#569cd6'; type = '#4ec9b0'; builtin = '#dcdcaa'; function = '#dcdcaa'; preproc = '#c586c0'; linenumber = '#858585' }
    }
    return [ordered]@{ background = '#ffffff'; plain = '#1f1f1f'; comment = '#008000'; string = '#a31515'; number = '#098658'
                       keyword = '#0000ff'; type = '#267f99'; builtin = '#795e26'; function = '#795e26'; preproc = '#af00db'; linenumber = '#999999' }
}

function ConvertTo-CPRtfText {
    <# Escapes text for RTF (\ { } tabs and non-ASCII characters). #>
    param([AllowEmptyString()][string]$Text = '')
    $t = ($Text -replace '([\\{}])', '\$1') -replace "`t", '\tab '
    if ($t -match '[^\x00-\x7e]') {
        $t = [regex]::Replace($t, '[^\x00-\x7e]', { param($m) $n = [int][char]$m.Value; '\u' + $(if ($n -gt 32767) { $n - 65536 } else { $n }) + '?' })
    }
    return $t
}

function ConvertTo-CPCodeRtf {
    <# Coloured RTF of the code for a RichTextBox. -LineNumbers adds a grey number in front of each
       line (right-aligned number + two spaces; Remove-CPLineNumbers takes them off copied text). #>
    param([AllowEmptyString()][string]$Code = '', [string]$Language = 'C++', [switch]$Dark, [switch]$LineNumbers, [int]$FontSize = 10)
    $colors = Get-CPCodeColors -Dark:$Dark
    $kinds = @($colors.Keys)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{\rtf1\ansi\deff0{\fonttbl{\f0\fmodern Consolas;}}{\colortbl ;')
    foreach ($k in $kinds) {
        $c = $colors[$k]
        [void]$sb.Append(('\red{0}\green{1}\blue{2};' -f [Convert]::ToInt32($c.Substring(1, 2), 16), [Convert]::ToInt32($c.Substring(3, 2), 16), [Convert]::ToInt32($c.Substring(5, 2), 16)))
    }
    [void]$sb.Append('}\f0\fs' + ($FontSize * 2) + ' ')
    $idx = @{}; for ($i = 0; $i -lt $kinds.Count; $i++) { $idx[$kinds[$i]] = $i + 1 }
    $text = ($Code -replace "`r`n", "`n") -replace "`r", "`n"
    $width = ([string]($text.Split("`n")).Count).Length
    $line = 1
    $lnCf = $idx['linenumber']
    if ($LineNumbers) { [void]$sb.Append('\cf' + $lnCf + ' ' + ([string]$line).PadLeft($width) + '  ') }
    $special = [char[]]@('\', '{', '}', "`t")
    $lastCf = -1
    foreach ($tok in (Get-CPCodeTokens -Code $text -Language $Language)) {
        $cf = $idx[$tok.Kind]; if (-not $cf) { $cf = $idx['plain'] }
        $piece = $tok.Text
        if ($piece.IndexOf("`n") -ge 0) { [string[]]$parts = $piece.Split("`n") } else { [string[]]$parts = @($piece) }
        for ($p = 0; $p -lt $parts.Count; $p++) {
            if ($p -gt 0) {
                [void]$sb.Append("\par`r`n")
                $line++
                if ($LineNumbers) { [void]$sb.Append('\cf' + $lnCf + ' ' + ([string]$line).PadLeft($width) + '  '); $lastCf = $lnCf }
            }
            $part = $parts[$p]
            if (-not $part.Length) { continue }
            if ($part.IndexOfAny($special) -ge 0 -or $part -match '[^\x00-\x7e]') { $part = ConvertTo-CPRtfText $part }
            if ($cf -ne $lastCf) { [void]$sb.Append('\cf' + $cf + ' '); $lastCf = $cf }
            if ($tok.Kind -eq 'keyword') { [void]$sb.Append('\b ' + $part + '\b0 ') } else { [void]$sb.Append($part) }
        }
    }
    [void]$sb.Append('}')
    return $sb.ToString()
}

function Remove-CPLineNumbers {
    <# Takes the line numbers added by ConvertTo-CPCodeRtf -LineNumbers off copied text. #>
    param([AllowEmptyString()][string]$Text = '')
    return ($Text -replace '(?m)^ *\d+  ', '')
}

Export-ModuleMember -Function *-CP*, Get-CPAppVersion
