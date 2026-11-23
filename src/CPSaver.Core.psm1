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
$script:AppVersion = '2.0.0'

function Get-CPAppVersion { $script:AppVersion }

function Get-CPDataDir {
    $base = [Environment]::GetFolderPath('ApplicationData')
    if (-not $base) { $base = Join-Path $HOME '.config' }
    $dir = Join-Path $base $script:AppName
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-CPDefaultConfigPath { Join-Path (Get-CPDataDir) 'config.json' }

function Get-CPDefaultConfig {
    [ordered]@{
        MainCppPath      = ''
        RepoPath         = ''
        TemplatePath     = (Join-Path (Get-CPDataDir) 'template.cpp')
        AutoFetch        = $true
        PushAfterSave    = $true
        ResetAfterSave   = $false
        UpdateIndexes    = $true
        ConfigVersion    = 2
    }
}

function Get-CPConfig {
    param([string]$Path = (Get-CPDefaultConfigPath))
    $cfg = Get-CPDefaultConfig
    if (Test-Path $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            foreach ($p in $raw.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
        } catch {
            Write-Warning "Could not read config $Path : $($_.Exception.Message). Using defaults."
        }
    }
    return $cfg
}

function Save-CPConfig {
    param([Parameter(Mandatory)]$Config, [string]$Path = (Get-CPDefaultConfigPath))
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = ([pscustomobject]$Config) | ConvertTo-Json -Depth 5
    Write-CPTextFile -Path $Path -Text $json
}

function Test-CPConfig {
    <# Returns a list of problems with the config (empty list = OK). #>
    param([Parameter(Mandatory)]$Config)
    $problems = New-Object System.Collections.Generic.List[string]
    if (-not $Config.MainCppPath -or -not (Test-Path -LiteralPath $Config.MainCppPath)) {
        $problems.Add("Practice file (main.cpp) not found: '$($Config.MainCppPath)'")
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

function Read-CPHeader {
    <#
      Parses the first /* ... */ comment at the top of a C++ file.
      Returns @{ Fields = [ordered] key->value ; HasHeader ; Body = code after header ; Newline }
      Unknown "Key: value" lines are kept as extra fields; lines without a key
      continue the previous field (multi-line notes).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Code)

    $nl = Get-CPNewline $Code
    $fields = [ordered]@{}
    $m = [regex]::Match($Code, '^\uFEFF?\s*/\*(.*?)\*/[ \t]*\r?\n?', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) {
        return @{ Fields = $fields; HasHeader = $false; Body = $Code; Newline = $nl }
    }

    $lastKey = $null
    $sawKnown = $false
    foreach ($rawLine in ($m.Groups[1].Value -split "\r?\n")) {
        $line = $rawLine -replace '^\s*\*?[ \t]?', ''
        if ($line.Trim() -eq '') { continue }
        $km = [regex]::Match($line, '^\s*([A-Za-z][A-Za-z ]{0,29}?)\s*:\s?(.*)$')
        if ($km.Success) {
            $canon = Get-CPCanonicalKey $km.Groups[1].Value
            $key = if ($canon) { $canon } else { $km.Groups[1].Value.Trim() }
            if ($canon) { $sawKnown = $true }
            # a "Key:" that is really a continuation (e.g. "Idea: ...") after Notes stays in Notes
            if (-not $canon -and $lastKey -eq 'Notes') {
                $fields['Notes'] = ($fields['Notes'] + $nl + $line.TrimEnd()).Trim()
                continue
            }
            $fields[$key] = $km.Groups[2].Value.Trim()
            $lastKey = $key
        } elseif ($lastKey) {
            $fields[$lastKey] = ($fields[$lastKey] + $nl + $line.TrimEnd()).Trim()
        }
    }

    if (-not $sawKnown) {
        # A normal comment, not our header.
        return @{ Fields = [ordered]@{}; HasHeader = $false; Body = $Code; Newline = $nl }
    }
    $body = $Code.Substring($m.Index + $m.Length)
    return @{ Fields = $fields; HasHeader = $true; Body = $body; Newline = $nl }
}

function ConvertTo-CPHeader {
    param([Parameter(Mandatory)]$Fields, [string]$Newline = "`r`n")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('/*')
    $keys = @($script:HeaderOrder | Where-Object { $Fields.Contains($_) })
    $keys += @($Fields.Keys | Where-Object { $script:HeaderOrder -notcontains $_ })
    foreach ($k in $keys) {
        $v = [string]$Fields[$k]
        if ($v -eq '' -and $k -notin @('Problem Name', 'Problem Link', 'Topics', 'Difficulty', 'Notes')) { continue }
        $parts = $v -split "\r?\n"
        $lines.Add((" * {0}: {1}" -f $k, $parts[0]).TrimEnd())
        for ($i = 1; $i -lt $parts.Count; $i++) { $lines.Add((" *   " + $parts[$i]).TrimEnd()) }
    }
    $lines.Add(' */')
    return ($lines -join $Newline)
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
      Looks the problem up online. Never throws: returns @{ Ok; Name; Id;
      Difficulty; Topics (string[]); Message }.
    #>
    param([string]$Link, [int]$TimeoutSec = 8)
    $res = @{ Ok = $false; Name = ''; Id = ''; Difficulty = ''; Topics = @(); Message = '' }
    if (-not $Link) { $res.Message = 'No link.'; return $res }
    $info = Get-CPPlatformInfo $Link
    Initialize-CPWeb
    try {
        switch ($info.Platform) {
            'Codeforces' {
                if (-not $info.ContestId) { throw 'Could not read contest/problem from the link.' }
                $api = "https://codeforces.com/api/contest.standings?contestId=$($info.ContestId)&from=1&count=1"
                $j = Invoke-RestMethod -Uri $api -TimeoutSec $TimeoutSec -Headers @{ 'User-Agent' = 'CPSolutionSaver' }
                if ($j.status -ne 'OK') { throw "Codeforces API: $($j.comment)" }
                $p = $j.result.problems | Where-Object { $_.index -eq $info.Index } | Select-Object -First 1
                if (-not $p) { throw "Problem $($info.Index) not found in contest $($info.ContestId)." }
                $res.Name = $p.name
                $res.Id = $info.Id
                if ($p.PSObject.Properties['rating'] -and $p.rating) { $res.Difficulty = [string]$p.rating }
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
                $t = Get-CPPageTitle -Url $Link -TimeoutSec $TimeoutSec
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
        $res.Message = "Online lookup failed: $($_.Exception.Message)"
    }
    return $res
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
        DateSolved, Extra (other header fields), Body, Newline, FileBase,
        RelPath, Metadata (fetch result or $null)
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Code,
        [switch]$Fetch,
        [hashtable]$Overrides = @{}
    )
    $h = Read-CPHeader $Code
    $f = $h.Fields
    function _get($k) { if ($f.Contains($k)) { return [string]$f[$k] } else { return '' } }

    $info = @{
        Name       = _get 'Problem Name'
        Link       = _get 'Problem Link'
        Platform   = _get 'Platform'
        Id         = _get 'Problem ID'
        Difficulty = _get 'Difficulty'
        Topics     = @(Merge-CPTopics @(,(_get 'Topics')))
        Notes      = _get 'Notes'
        DateSolved = _get 'Date Solved'
        Extra      = [ordered]@{}
        Body       = $h.Body
        Newline    = $h.Newline
        HasHeader  = $h.HasHeader
        Metadata   = $null
    }
    foreach ($k in $f.Keys) { if ($script:HeaderOrder -notcontains $k) { $info.Extra[$k] = $f[$k] } }
    foreach ($k in $Overrides.Keys) { $info[$k] = $Overrides[$k] }

    $pi = Get-CPPlatformInfo $info.Link
    if (-not $info.Platform) { $info.Platform = $pi.Platform }
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
    if (-not $info.DateSolved) { $info.DateSolved = (Get-Date).ToString('yyyy-MM-dd') }
    Update-CPSolutionPath $info
    return $info
}

function Update-CPSolutionPath {
    <# (Re)computes FileBase and RelPath from Name/Id/Platform. #>
    param([Parameter(Mandatory)][hashtable]$Info)
    $plat = Get-CPSafeFileName $(if ($Info.Platform) { $Info.Platform } else { 'Other' })
    if (-not $plat) { $plat = 'Other' }
    $safeName = Get-CPSafeFileName $Info.Name
    $safeId = Get-CPSafeFileName $Info.Id
    if ($safeId -and $safeName) { $base = "${safeId}_$safeName" }
    elseif ($safeName) { $base = $safeName }
    elseif ($safeId) { $base = $safeId }
    else { $base = '' }
    $Info.FileBase = $base
    $Info.RelPath = if ($base) { "$plat/$base.cpp" } else { '' }
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
    $body = $Info.Body -replace '^(\s*\r?\n)+', ''
    return (ConvertTo-CPHeader -Fields $fields -Newline $nl) + $nl + $nl + $body
}

# ----------------------------------------------------------------------------
#  Scanning the solutions repo
# ----------------------------------------------------------------------------

function Get-CPAllSolutions {
    <# Reads the header of every .cpp file in the repo (skips .git, Index). #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $root = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
    $list = New-Object System.Collections.Generic.List[object]
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -Include *.cpp, *.cc, *.cxx, *.c, *.py, *.java -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]Index[\\/]' }
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        $text = ''
        try { $text = [IO.File]::ReadAllText($file.FullName) } catch { continue }
        $h = Read-CPHeader $text
        $f = $h.Fields
        $name = if ($f.Contains('Problem Name') -and $f['Problem Name']) { $f['Problem Name'] } else { $file.BaseName }
        $link = if ($f.Contains('Problem Link')) { $f['Problem Link'] } else { '' }
        $plat = if ($f.Contains('Platform') -and $f['Platform']) { $f['Platform'] } else { ($rel -split '/')[0] }
        if ($rel -notmatch '/') { $plat = (Get-CPPlatformInfo $link).Platform }
        $list.Add([pscustomobject]@{
            RelPath    = $rel
            Name       = $name
            Link       = $link
            Platform   = $plat
            Id         = $(if ($f.Contains('Problem ID')) { $f['Problem ID'] } else { '' })
            Difficulty = $(if ($f.Contains('Difficulty')) { $f['Difficulty'] } else { '' })
            Topics     = @(Merge-CPTopics @(,$(if ($f.Contains('Topics')) { $f['Topics'] } else { '' })))
            DateSolved = $(if ($f.Contains('Date Solved')) { $f['Date Solved'] } else { $file.LastWriteTime.ToString('yyyy-MM-dd') })
        })
    }
    return $list.ToArray()
}

function Find-CPExistingSolution {
    <# Finds an already-saved solution for the same problem (same link, or same path). #>
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][hashtable]$Info)
    if ($Info.RelPath -and (Test-Path -LiteralPath (Join-Path $RepoPath $Info.RelPath))) { return $Info.RelPath }
    if (-not $Info.Link) { return $null }
    $norm = { param($u) ($u.Trim().TrimEnd('/') -replace '^https?://(www\.)?', '').ToLowerInvariant() }
    $target = & $norm $Info.Link
    foreach ($s in (Get-CPAllSolutions $RepoPath)) {
        if ($s.Link -and (& $norm $s.Link) -eq $target) { return $s.RelPath }
    }
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

    if (-not $Info.Name) { & $emit 'ERROR: The problem name is empty.'; return $result }
    if (-not (Test-CPGitAvailable)) { & $emit 'ERROR: git is not installed or not on PATH.'; return $result }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { & $emit "ERROR: '$RepoPath' is not a git repository."; return $result }

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
            $dir = Split-Path $existing -Parent; $base = [IO.Path]::GetFileNameWithoutExtension($existing)
            $i = 2
            while (Test-Path -LiteralPath (Join-Path $RepoPath ("$dir/${base}_v$i.cpp"))) { $i++ }
            $rel = ("$dir/${base}_v$i.cpp") -replace '\\', '/'
            & $emit "Already saved before; keeping both -> $rel"
        } else {
            $rel = $existing
            $result.IsUpdate = $true
            & $emit "Already saved before; updating $rel"
        }
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

function Get-CPDefaultTemplate {
    @'
/*
 * Problem Name:
 * Problem Link:
 * Difficulty:
 * Topics:
 * Notes:
 */

#include <bits/stdc++.h>
using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'@
}

function Initialize-CPTemplate {
    param([Parameter(Mandatory)][string]$TemplatePath)
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        Write-CPTextFile -Path $TemplatePath -Text ((Get-CPDefaultTemplate) -replace "\r?\n", "`r`n")
    }
}

function Reset-CPPracticeFile {
    param([Parameter(Mandatory)][string]$MainCppPath, [Parameter(Mandatory)][string]$TemplatePath)
    Initialize-CPTemplate $TemplatePath
    $t = Read-CPTextFile $TemplatePath
    Write-CPTextFile -Path $MainCppPath -Text $t
}

function Add-CPHeaderFields {
    <# Adds any missing header fields (Difficulty, Topics, ...) to an existing file's header without touching the code. #>
    param([Parameter(Mandatory)][string]$Path)
    $code = Read-CPTextFile $Path
    $h = Read-CPHeader $code
    $f = $h.Fields
    if ($h.HasHeader) {
        foreach ($k in @('Problem Name', 'Problem Link', 'Difficulty', 'Topics', 'Notes')) { if (-not $f.Contains($k)) { $f[$k] = '' } }
        $new = (ConvertTo-CPHeader -Fields $f -Newline $h.Newline) + $h.Newline + $h.Body
    } else {
        $f = [ordered]@{ 'Problem Name' = ''; 'Problem Link' = ''; 'Difficulty' = ''; 'Topics' = ''; 'Notes' = '' }
        $new = (ConvertTo-CPHeader -Fields $f -Newline $h.Newline) + $h.Newline + $h.Newline + $code
    }
    if ($new -ne $code) { Write-CPTextFile -Path $Path -Text $new; return $true }
    return $false
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

function Get-CPRepoWebUrl {
    param([Parameter(Mandatory)][string]$RepoPath)
    $u = (Invoke-CPGit $RepoPath remote get-url origin).Output
    if (-not $u) { return $null }
    $u = $u.Trim() -replace '\.git$', ''
    if ($u -match '^git@([^:]+):(.+)$') { $u = "https://$($Matches[1])/$($Matches[2])" }
    return $u
}

Export-ModuleMember -Function *-CP*, Get-CPAppVersion
