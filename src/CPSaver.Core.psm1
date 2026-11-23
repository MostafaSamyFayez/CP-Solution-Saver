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
$script:AppVersion = '2.3.1'

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

function Test-CPConfig {
    <# Returns a list of problems with the config (empty list = OK). #>
    param([Parameter(Mandatory)]$Config)
    $problems = New-Object System.Collections.Generic.List[string]
    $existing = @(@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($existing.Count -eq 0) {
        $problems.Add("No practice file found (main.cpp / main.c / main.py): '$((@($Config.PracticeFiles) + @($Config.MainCppPath) | Where-Object { $_ }) -join "', '")'")
    }
    if (-not $Config.RepoPath -or -not (Test-Path -LiteralPath (Join-Path $Config.RepoPath '.git'))) {
        $problems.Add("Solutions repo folder is not a git repository: '$($Config.RepoPath)'")
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
    'difficulty'   = 'Difficulty';   'rating' = 'Difficulty'; 'level' = 'Difficulty'
    'topics'       = 'Topics';       'topic' = 'Topics';      'tags' = 'Topics'; 'tag' = 'Topics'
    'date solved'  = 'Date Solved';  'date' = 'Date Solved';  'solved' = 'Date Solved'
    'notes'        = 'Notes';        'note' = 'Notes';        'comments' = 'Notes'
}
$script:HeaderOrder = @('Problem Name', 'Problem Link', 'Platform', 'Problem ID', 'Difficulty', 'Topics', 'Date Solved', 'Notes')

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
        if ($v -eq '' -and $k -notin @('Problem Name', 'Problem Link', 'Topics', 'Difficulty', 'Notes')) { continue }
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
        Name, Link, Platform, Id, Difficulty, Topics (string[]), Notes,
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
        'Topics'       = (@($Info.Topics) -join ', ')
        'Date Solved'  = $Info.DateSolved
    }
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
        $item = ([pscustomobject]@{
            RelPath    = $rel
            Name       = $name
            Link       = $link
            Key        = (Get-CPProblemKey $link)
            Platform   = $plat
            Id         = $(if ($f.Contains('Problem ID')) { $f['Problem ID'] } else { '' })
            Difficulty = $(if ($f.Contains('Difficulty')) { $f['Difficulty'] } else { '' })
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
    return $list.ToArray()
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
    $solPath = (($s.RelPath -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $sol = "[{0}]({1}{2})" -f ($s.RelPath -split '/')[-1], $Prefix, $solPath
    $topics = (@($s.Topics) | ForEach-Object { $_.ToLowerInvariant() }) -join ', '
    return "| {0} | {1} | {2} | {3} | {4} | {5} |" -f $prob, (Format-CPMd $s.Platform), (Format-CPMd $s.Difficulty), (Format-CPMd $topics), $sol, $s.DateSolved
}

$script:TableHead = "| Problem | Platform | Difficulty | Topics | Solution | Solved |`n|---|---|---|---|---|---|"

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
        foreach ($s in ($g.Group | Sort-Object { (Get-CPDifficultyGroup $_.Difficulty).SortKey }, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
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
        foreach ($s in ($topicMap[$t] | Sort-Object { (Get-CPDifficultyGroup $_.Difficulty).SortKey }, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
    }
    Write-CPTextFile -Path (Join-Path $indexDir 'BY_TOPIC.md') -Text $sb.ToString()

    # --- by difficulty
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Solutions by difficulty`n`n$gen`n")
    [void]$sb.AppendLine("Numbers are Codeforces-style ratings; Easy/Medium/Hard come from LeetCode or your own header.`n")
    $byDiff = $all | Group-Object { (Get-CPDifficultyGroup $_.Difficulty).Label } |
        Sort-Object { (Get-CPDifficultyGroup ($_.Group[0].Difficulty)).SortKey }
    foreach ($g in $byDiff) { [void]$sb.AppendLine("- [$($g.Name)](#$(($g.Name.ToLowerInvariant() -replace '[^a-z0-9 -]', '' -replace ' ', '-'))) ($($g.Count))") }
    foreach ($g in $byDiff) {
        [void]$sb.AppendLine("`n## $($g.Name)`n`n$script:TableHead")
        foreach ($s in ($g.Group | Sort-Object Platform, Name)) { [void]$sb.AppendLine((Format-CPRow $s '../')) }
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
    $result = @{ Success = $false; RelPath = ''; IsUpdate = $false; Commit = ''; Pushed = $false; Log = $lines }

    if (-not $Info.Link) { & $emit 'ERROR: The problem link is required. It identifies the problem, so the same problem is never saved twice.'; return $result }
    if (-not $Info.Name) { & $emit 'ERROR: The problem name is empty.'; return $result }
    if (-not (Test-CPGitAvailable)) { & $emit 'ERROR: git is not installed or not on PATH.'; return $result }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { & $emit "ERROR: '$RepoPath' is not a git repository."; return $result }

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
            & $emit 'No remote configured; commit kept locally.'
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
                $out.Summary += $(if ($res.Pushed) { 'Pushed to GitHub.' } elseif ($Config.PushAfterSave) { 'Committed locally (push skipped).' } else { 'Committed locally (push is off in Settings).' })
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
    param([Parameter(Mandatory)][string]$Name, [string]$Description = '', [switch]$Private)
    Initialize-CPWeb
    $token = Get-CPGitHubToken
    if (-not $token) { throw 'Could not get your GitHub sign-in from Git. Run any git push once to sign in, then try again.' }
    $headers = @{ Authorization = "token $token"; 'User-Agent' = 'CPSolutionSaver'; Accept = 'application/vnd.github+json' }
    $user = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
    try {
        $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$($user.login)/$Name" -Headers $headers
        return $existing.clone_url
    } catch { }
    $body = @{ name = $Name; description = $Description; private = [bool]$Private; auto_init = $true } | ConvertTo-Json
    $r = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -Body $body -ContentType 'application/json'
    return $r.clone_url
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
    $u = (Invoke-CPGit $RepoPath remote get-url origin).Output
    if (-not $u) { return $null }
    $u = $u.Trim() -replace '\.git$', ''
    if ($u -match '^git@([^:]+):(.+)$') { $u = "https://$($Matches[1])/$($Matches[2])" }
    return $u
}

Export-ModuleMember -Function *-CP*, Get-CPAppVersion
