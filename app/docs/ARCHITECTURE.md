# CP Solution Saver - architecture and developer guide

This document explains how the app is built, so you can change it without reading every line
first. Read sections 1-4 for the big picture, then jump to the part you need. Section 15 has
step-by-step recipes for common changes.

Contents

1. [What the app does, in one paragraph](#1-what-the-app-does-in-one-paragraph)
2. [Technology and why](#2-technology-and-why)
3. [Repository layout](#3-repository-layout)
4. [Runtime picture: processes and how a command travels](#4-runtime-picture-processes-and-how-a-command-travels)
5. [Files on the user's PC](#5-files-on-the-users-pc)
6. [The solutions repo format](#6-the-solutions-repo-format)
7. [Core module (CPSaver.Core.psm1)](#7-core-module-cpsavercorepsm1)
8. [The save pipeline step by step](#8-the-save-pipeline-step-by-step)
9. [GUI layer (CPSaver.Gui.ps1)](#9-gui-layer-cpsaverguips1)
10. [Tray host (CPSaver.Tray.ps1) and the native helpers](#10-tray-host-cpsavertrayps1-and-the-native-helpers)
11. [Entry point (CPSaver.ps1)](#11-entry-point-cpsaverps1)
12. [Installer, uninstaller, release](#12-installer-uninstaller-release)
13. [Tests](#13-tests)
14. [Coding rules and gotchas](#14-coding-rules-and-gotchas)
15. [Recipes: common changes](#15-recipes-common-changes)
16. [Debugging](#16-debugging)

---

## 1. What the app does, in one paragraph

The user solves a problem in one *practice file* (`main.cpp`, `main.c` or `main.py`) whose first
comment is a small *header* (problem name, link, difficulty, topics...). When it is accepted, a
global shortcut saves a copy into a *solutions folder* (a git repo) as
`<Platform>/<ID>_<Name>.<ext>`, with a normalized header, regenerates index pages (README stats,
by platform / topic / difficulty), commits, and pushes if the repo is connected to GitHub. Then
it resets the practice file to a code template. The problem **link** identifies a problem, so
saving it again updates the same file. Solved problems can be searched and loaded back.

## 2. Technology and why

| Choice | Why |
|---|---|
| **Windows PowerShell 5.1** (not PowerShell 7) | Built into every Windows 10/11: nothing to install. |
| **Windows Forms** for the UI | Ships with .NET Framework 4.x, which every Windows has. |
| **Two tiny C# files** compiled at install time | Global hotkeys (`RegisterHotKey`) and an instant launcher `.exe`. Compiled by `Add-Type -OutputAssembly` with the C# compiler that ships with .NET Framework, so there is no build step and no binaries in the repo. |
| **git** (the user's own) | History, GitHub sync, and the sign-in that Git Credential Manager already has. |
| **No other dependencies** | Easy to install on any Windows PC. |

The price: PowerShell 5.1 quirks (section 14) and starting PowerShell is slow (~0.5 s), which is
why a tray process stays running (section 4).

## 3. Repository layout

```
Install.bat                  what users run: opens the setup window (app\install.ps1 -Gui)
README.md                    user guide
LICENSE
app/
  install.ps1                installer (window, console or -Quiet)          -> section 12
  uninstall.ps1              uninstaller (asks first)                       -> section 12
  run-tests.bat              runs tests\Run-Tests.ps1 -Online
  CHANGELOG.md               what changed in each version
  src/                       everything that gets installed (copied to %LOCALAPPDATA%\Programs\CPSolutionSaver)
    CPSaver.ps1              entry point: parses switches, picks a mode      -> section 11
    CPSaver.Core.psm1        all logic, no UI (module)                       -> section 7
    CPSaver.Gui.ps1          all windows (dot-sourced)                       -> section 9
    CPSaver.Tray.ps1         the tray host (dot-sourced)                     -> section 10
    native/CPSaverNative.cs  -> CPSaver.Native.dll: hotkey window, named events, DPI
    native/CPSaverLauncher.cs-> CPSaverLauncher.exe: signals or starts the tray host
    app.ico, app.png         icon (ICO for windows/shortcuts, PNG for headers)
  tests/Run-Tests.ps1        self-tests                                      -> section 13
  tools/New-Release.ps1      builds CP-Solution-Saver.zip, publishes a GitHub release
  docs/                      screenshots + this file
```

Size guide: Core ~1700 lines, Gui ~1600, Tray ~200, entry ~190, installer ~400, tests ~330.

## 4. Runtime picture: processes and how a command travels

```
 hotkey Ctrl+Alt+Shift+S/F/B ----------------------------------+
 Start Menu / Desktop shortcut                                 |
   -> CPSaverLauncher.exe <command>                            |
        | host running?  yes: set named event  ----------------+--> tray host (one hidden powershell.exe)
        |                no:  start  powershell -STA -WindowStyle Hidden      CPSaver.ps1 -Tray -Command <command>
        |                          -File CPSaver.ps1 -Tray -Command <command>   - owns the hotkeys (HostWindow)
                                                                               - NotifyIcon + tray menu
                                                                               - keeps Core + Gui loaded, so
                                                                                 windows open instantly
                                                                               - runspace pool for background work
```

* **Commands**: `open` (save window), `quick` (quick save), `browse` (solved problems),
  `templates`, `settings`, `welcome` (tour), `tray` (just start), `exit`. Hotkeys map to
  open / quick / browse.
* **Named objects** (per Windows session; the prefix gets `_<CPSAVER_INSTANCE>` when that
  environment variable is set, so a test copy can run next to the real one):
  * mutex `Local\CPSolutionSaver_Host`: held by the running host (only one host).
  * events `Local\CPSolutionSaver_cmd_<command>`: the launcher sets one, the host's
    `HostWindow` waits on all of them on background threads and raises `Command` on the UI thread.
* **Speed** (measured): signal to a running host ~0.01 s; cold start of the host ~0.5 s.
* **No native helpers** (compile failed, or PowerShell 7): shortcuts run `CPSaver.vbs`, which
  starts `CPSaver.ps1` once per command without a tray (slower, same features).

Inside the host, `$dispatch` -> `$run` (in `Start-CPTray`) handles a command: modal windows run
inside it (`Show-CPMainWindow`, `Show-CPBrowser`...), `quick` runs `Invoke-CPQuickSave` as a
background job and shows `Show-CPResultDialog` when done. A busy flag stops a second window
opening on top; a second press brings the open window to the front.

## 5. Files on the user's PC

**Install folder** `%LOCALAPPDATA%\Programs\CPSolutionSaver` (replaced on every install):
the contents of `app\src`, plus `CPSaverLauncher.exe`, `CPSaver.Native.dll` (built there),
`CPSaver.vbs` (fallback launcher), `cpsaver.cmd` (console mode), `uninstall.ps1/.bat`,
`README.md`, `LICENSE`, `CHANGELOG.md`, `tests\`.

**Data folder** `%APPDATA%\CPSolutionSaver` (kept across installs; `Get-CPDataDir`, or
`$env:CPSAVER_DATA_DIR` in tests):

| File | What |
|---|---|
| `config.json` | settings (schema below) |
| `templates\<Language> - <name>.<ext>` | code templates; built-ins are written only if missing |
| `backups\` | practice file copies made before loading a solution / template (newest 30 kept) |
| `codeforces-problems.tsv` | cached Codeforces problem list (refreshed daily) |
| `last-quick-save.log` | full log of the last quick save |
| `host.log` | tray host trace (`Write-CPTrace`), trimmed at 200 KB |
| `launcher.log` | what CPSaverLauncher.exe did |

**Shortcuts**: Start Menu folder *CP Solution Saver* (app, quick save, solved problems,
templates, how to use, settings, read me, uninstall), Desktop shortcut (optional), Startup
shortcut `CPSaverLauncher.exe tray` (optional; "Start with Windows").

**`config.json` schema** (`Get-CPDefaultConfig`; `Get-CPConfig` merges the file over the
defaults, so new keys get their default automatically):

| Key | Default | Meaning |
|---|---|---|
| `PracticeFiles` | `[]` | one practice file per language |
| `MainCppPath` | `''` | the active practice file (= the most recently saved one; kept for old versions) |
| `RepoPath` | `''` | the solutions folder (git repo, or an empty folder that becomes one) |
| `DefaultTemplates` | `{}` | extension -> template file name used by "reset after saving" |
| `AutoFetch` | `true` | look the problem up online |
| `PushAfterSave` | `true` | push after committing (only if a remote exists) |
| `ResetAfterSave` | `true` | write the template into the practice file after a successful save |
| `CloseAfterSave` | `true` | close the save window after success |
| `UpdateIndexes` | `true` | regenerate README stats + Index/*.md |
| `QuickSaveNotify` | `'dialog'` | `'dialog'` (centered result window) or `'notification'` (balloon) |
| `BackupsToKeep` | `30` | |
| `TutorialShown` | `false` | the welcome tour was seen; the installer resets it on every interactive install |
| `TemplatePath` | | legacy (v2.0) |
| `ConfigVersion` | `4` | bump + migrate in `Get-CPConfig` when a default must change for old users |

## 6. The solutions repo format

**Header** (first comment of the file). Keys are case-insensitive and have aliases
(`$script:CanonicalKeys`: name/title, link/url, tags/topic, rating/level, date...). Saved files
always use this order (`$script:HeaderOrder`); unknown keys are kept (as `Extra`):

```
/*
 * Problem Name: Watermelon
 * Problem Link: https://codeforces.com/problemset/problem/4/A
 * Platform: Codeforces
 * Problem ID: 4A
 * Difficulty: 800
 * Topics: brute force, math
 * Date Solved: 2026-11-23
 * Notes: even and > 2
 */
```

Styles (`Get-CPLanguage`): `block` `/* */` for C-like languages, `python` (a `"""` docstring;
`#` comment lines are read too). `//` line headers are read as well. Lines starting with `#include`
or other preprocessor directives are never taken as a header.

**File path**: `<Platform>/<ID>_<Name><ext>` (`Update-CPSolutionPath`; unsafe characters
replaced by `Get-CPSafeFileName`; `Other/` when the platform is unknown; `_v2`, `_v3` with
"keep both").

**Problem identity** (`Get-CPProblemKey`): a normalized key from the link, e.g.
`codeforces:4A` for both `/contest/4/problem/A` and `/problemset/problem/4/A`,
`leetcode:two-sum`, else `url:<normalized url>`. `Find-CPExistingSolution` looks for a saved file
with the same key **and the same language**; `Find-CPSolvedBefore` finds the problem in any language.

**Re-saving rules** (in `Save-CPSolution`): same key -> update that file; the original
`Date Solved` is kept when the new date was automatic (`DateAuto`); the first spelling of the link
is kept; identical content -> "no changes", nothing committed.

**Indexes** (`Update-CPIndexes`): `Index/BY_PLATFORM.md`, `BY_TOPIC.md`, `BY_DIFFICULTY.md`
are fully regenerated; in `README.md` only the block between `<!-- CPSAVER:STATS:START -->` and
`<!-- CPSAVER:STATS:END -->` is replaced (the rest of the README is the user's).
Difficulty groups (`Get-CPDifficultyGroup`): one group per numeric rating (`Rating 800`,
`Rating 1200`...), then Easy / Medium / Hard, then any other text, then `Unrated`.

**Commits**: `Add <Platform> <ID> - <Name>` / `Update ...`, body with difficulty, topics, link.

## 7. Core module (CPSaver.Core.psm1)

No UI here: everything is testable from the console. Functions return hashtables
(`@{ Success; ... }`) rather than throwing for expected failures; `Invoke-CPGit` never throws.
Exported: every `*-CP*` function. Sections in file order:

| Section | Main functions |
|---|---|
| Paths and configuration | `Get-CPDataDir`, `Get-CPDefaultConfig`, `Get-CPConfig` (merge + migration), `Save-CPConfig`, `Get-CPActivePracticeFile` (newest LastWriteTime), `Get-CPPracticeFileFor`, `Test-CPConfig` (list of problems; empty = OK), `Remove-CPPracticeLaunchers` |
| File helpers | `Read-CPTextFile`, `Write-CPTextFile` (UTF-8 without BOM), `Get-CPNewline` (keeps the file's CRLF/LF) |
| Problem header | `Read-CPHeader` -> `@{ Fields; HasHeader; Body; Newline; Prefix; Style }`, `ConvertTo-CPHeader`, `Get-CPLanguage`, `Get-CPSourceExtensions`, `Get-CPProblemKey` |
| Platform detection | `Get-CPPlatformInfo` (URL -> `@{ Platform; Id; Slug; ContestId; Index }`), `Get-CPKnownPlatforms` |
| Online metadata | `Get-CPProblemMetadata` (one retry) -> `Get-CPProblemMetadataOnce`: Codeforces (problemset API, cached TSV), LeetCode (GraphQL), others (page title). Returns `@{ Ok; Name; Id; Difficulty; Topics; Message }` |
| Solution info | `New-CPSolutionInfo` (header + metadata -> one hashtable, see its comment for the fields), `Update-CPSolutionPath`, `ConvertTo-CPSolutionText` |
| Scanning the repo | `Get-CPAllSolutions` (reads every solution header; cached per file by mtime+size), `Get-CPStats`, `Find-CPSolvedBefore`, `Find-CPExistingSolution` |
| Indexes | `Update-CPIndexes` (returns changed paths) |
| Git | `Invoke-CPGit <dir> <args...>` -> `@{ Code; Output }`, `Test-CPGitAvailable`, `Get-CPGitIdentity`, `Set-CPGitIdentity`, `Test-CPRepoFolder` ('repo' / 'empty' / 'files' / 'none'), `Initialize-CPRepo` |
| Saving | `Save-CPSolution` (section 8) |
| Templates | `Get-CPBuiltInTemplates` (11 built-ins as text), `Initialize-CPTemplates`, `Get-CPTemplates`, `Get-CPDefaultTemplatePath`, `Reset-CPPracticeFile`, `Add-CPHeaderFields` |
| Quick save | `Invoke-CPQuickSave` (active practice file, settings' defaults, no questions; writes `last-quick-save.log`) |
| Loading back | `Backup-CPPracticeFile`, `Get-CPImportTarget` (practice file of the same language), `Import-CPSolution` |
| GitHub | `Get-CPGitHubToken` (`git credential fill`; never logged), `New-CPGitHubRepo`, `Connect-CPGitHub`, `Get-CPRepoWebUrl`, `Get-CPFileWebUrl` |

## 8. The save pipeline step by step

`Save-CPSolution -Info <hashtable> -RepoPath <dir> [-Push] [-UpdateIndexes] [-KeepBoth] [-Log {..}]`
returns `@{ Success; RelPath; IsUpdate; Commit; Pushed; NoRemote; Log }`:

1. Checks: link and name present, git installed.
2. Folder: `Test-CPRepoFolder`; an empty folder -> `Initialize-CPRepo`; a non-empty non-repo -> error.
3. Git identity (`Get-CPGitIdentity`): missing -> clear error (the GUI asks before getting here).
4. `git pull --rebase --autostash` if pushing and the branch has an upstream.
5. Path: existing file for the same problem+language -> update it (keep first date and link
   spelling), or `_vN` with KeepBoth; otherwise the new `RelPath`.
6. Write the file (`ConvertTo-CPSolutionText`).
7. `Update-CPIndexes` (if enabled).
8. `git add` the changed paths; nothing staged -> "No changes" (success, nothing committed).
9. `git commit` with the message from section 6.
10. Push if requested and a remote exists; no remote -> `NoRemote = $true` ("kept locally").

Callers: the save window (as a background job, log lines streamed through a
`ConcurrentQueue`), `Invoke-CPQuickSave`, console mode in `CPSaver.ps1`. After a successful save
the caller resets the practice file (`Reset-CPPracticeFile -Config`) if `ResetAfterSave`.

## 9. GUI layer (CPSaver.Gui.ps1)

Dot-sourced into the process (needs the Core module imported first). Contains:

* **Theme**: fonts and colors as `$script:CP*` variables; helpers `New-CPForm`, `New-CPHeader`
  (dark strip; returns `@{ Panel; Right; Subtitle }`), `New-CPButton`, `Set-CPPrimary`,
  `New-CPLabel`, `New-CPTextBox`, `Show-CPForeground`, `Invoke-CPSafe` (try/catch -> message box).
  Use these so new windows look the same.
* **Background jobs**: `Open-CPPool` / `Start-CPJob -Script {..} -Arguments @() -OnDone {param($result,$error)} [-Owner $form]`
  / `Update-CPJobs`. A runspace pool (1-2 runspaces) with the Core module imported runs the
  script; a WinForms `Timer` in the open window (or the tray) calls `Update-CPJobs`, which runs
  `-OnDone` **on the UI thread**. Jobs whose `-Owner` form was closed are dropped. `-Script` runs in
  another runspace: it sees only its arguments and Core functions, not your variables.
* **Windows** (each a function that builds the form and calls `ShowDialog()`):

| Function | Window |
|---|---|
| `Show-CPMainWindow` | the save window (fields, *Will be saved as*, options, buttons, log) |
| `Show-CPBrowser` | Solved problems: search, filters, preview, load back |
| `Show-CPTemplatePicker` | code templates: preview, load, set default per language |
| `Show-CPSettingsDialog` | settings, repo helpers (clone / create / connect to GitHub) |
| `Show-CPTopicPicker` | topic checklist |
| `Show-CPWelcome` / `Start-CPFirstRun` | the welcome tour; first-run flow (tour once, then Settings if needed) |
| `Show-CPGitIdentityDialog` / `Confirm-CPGitIdentity` | asks for git name + email before the first save |
| `Use-CPRepoFolder` | turns an empty folder into a repo (asks for a non-empty one) |
| `Show-CPResultDialog`, `Show-CPBusy`, `Show-CPNotification` | quick save result, "working..." box, balloon |

* **State inside a window**: a `$ui` hashtable (controls) and a `$st` hashtable (state) captured
  by the event handlers. Event handlers are scriptblocks that run while `ShowDialog()` is active,
  so they see the function's variables through PowerShell's dynamic scoping.

## 10. Tray host (CPSaver.Tray.ps1) and the native helpers

`Start-CPTray -Command <cmd> -ConfigPath <path>`:

1. Creates `CPSaverNative.HostWindow`, registers the three hotkeys (`AddHotkey`), listens for
   the named command events (`ListenFor`), reports hotkeys already taken by another app.
2. Builds the `NotifyIcon` and its menu (`$addItem 'text' 'command'`).
3. `$run` executes a command (see section 4); `$dispatch` wraps it with error handling.
4. Timers: `$jobTimer` (150 ms) runs `Update-CPJobs`; `$startTimer` runs once after startup:
   first run (tour + settings) if `TutorialShown` is false, then the start command.
5. `Application.Run()` until `exit`.

`CPSaverNative.cs`: `Dpi.Enable()` (sharp text on scaled screens), `HostWindow` (a hidden
`NativeWindow` receiving `WM_HOTKEY`; `EventName(cmd)`, `MutexName`; `Command` event).
`CPSaverLauncher.cs`: `Main(args)` -> signal the event, or start the host; `exit` with no
host does nothing; logs to `launcher.log`. Both are C# 5 (the .NET Framework compiler).

## 11. Entry point (CPSaver.ps1)

Imports Core, reads the config (`-ConfigPath`, else `$env:CPSAVER_CONFIG`, else default), then:

| Switches | Mode |
|---|---|
| `-Tray [-Command x]` | the tray host (or pass the command to a running one and exit) |
| `-Quick` | quick save with busy box + result window (no tray) |
| `-Browse`, `-Settings`, none | that window (first-run flow if needed) |
| `-Cli [-Yes] [-NoFetch] [-NoPush] [-NoReset] [-KeepBoth] [-MainCpp f]` | console mode |
| `-RebuildIndex` | regenerate indexes, commit, push |
| `-Version` | print the version |

## 12. Installer, uninstaller, release

**`Install.bat`** checks that `app\install.ps1` exists (else: "extract the zip first"), then
starts `install.ps1 -Gui` hidden. `Install.bat -Console` / `-Quiet` run in the console.

**`install.ps1`**: the steps are in one scriptblock (`$installSteps`) that is dot-sourced
inside try/catch; `Step` / `Ok` / `Warn` report either to the console or to the progress window
(`$script:Ui`) and always to `%TEMP%\CPSolutionSaver-install.log`. With `-Gui`:
`Show-InstallWelcome` (options) -> `Show-InstallProgress` (not modal, updated by the steps) ->
`Show-InstallDone` (or the error) -> start the app. Steps: requirements; stop a running host
(event + kill leftover `CPSaver.ps1 -Tray` processes; locked DLLs are renamed); copy; compile the
native helpers; shortcuts; settings (merge, templates, `TutorialShown = false` unless `-Quiet`);
remove old .bat launchers; start the app (`CPSaverLauncher.exe open` -> tour -> Settings if
needed -> save window; `-Quiet` -> `tray`).

**`uninstall.ps1`**: window with *Also delete my settings, code templates and backups*
(default off) -> stop the host -> remove shortcuts and the install folder (and the data folder
if chosen) -> result message. `-Yes [-RemoveSettings]` for no questions.

**Release** (`app\tools\New-Release.ps1`): reads the version from `Get-CPAppVersion`, builds
`CP-Solution-Saver.zip` (Install.bat, README, LICENSE, app\ without tools), creates or updates
the GitHub release `v<version>` with the changelog section as notes, uploads the zip. The README
links to `releases/latest/download/CP-Solution-Saver.zip`, so it always gets the newest.

**Version**: `$script:AppVersion` at the top of `CPSaver.Core.psm1`. Bump it and add a
`CHANGELOG.md` section for every release.

## 13. Tests

`app\tests\Run-Tests.ps1` (or `app\run-tests.bat`; add `-Online` for the web lookups). It uses a
temporary folder for everything (`$env:CPSAVER_DATA_DIR`, a local bare repo as "GitHub", a test
git identity if the PC has none), so the real repo and settings are never touched. `Check 'name' <bool> 'detail'`
records a result. Sections:

1 header parsing, 2 platform detection, 3 saving into a repo with a remote, 4 same problem again,
5 LeetCode without id, 6 template + header upgrade, 7 console mode end to end, 8 quick save,
9 browse + load back, 10 languages / link identity / dates / templates / settings,
13 local-only repo (`git init`, no remote), 14 first-time setup helpers (empty folder, connect
to GitHub later, git identity, old launchers, tour flag), 11 online lookups (`-Online`),
12 static checks (every window button has a click handler; every script parses).

GUI windows are not driven by the tests; check them by hand (section 16 has a safe way).

## 14. Coding rules and gotchas

* **ASCII only in .ps1/.psm1 files.** Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI, so
  any non-ASCII character (smart quotes, dashes, emoji) can break parsing. Write `-` not a dash.
* **CRLF line endings** for .ps1/.psm1/.bat/.cs (see `.gitattributes`).
* **Target PowerShell 5.1 and C# 5**: no `??`, no ternary `? :`, no `using namespace`
  after code, no `$x?.y`; C#: no `$""` interpolation, no `out var`.
* **`$ErrorActionPreference = 'Stop'` + native commands**: git writes progress to stderr, which
  PS 5.1 turns into errors. Always call git through `Invoke-CPGit` (it switches to `Continue`).
* **`-LiteralPath` everywhere** (paths can contain `[ ]`); note `-Include` is ignored with
  `-LiteralPath` in PS 5.1, so filter by extension yourself.
* **Closures**: a callback that is called from a function which has a parameter of the same name
  will see that parameter (dynamic scoping). Example: `Save-CPSolution` has `-Log`; the quick-save
  callback uses `$qsLog` and `.GetNewClosure()` to avoid calling itself forever.
* **Background job results**: `-Script` runs in another runspace; pass everything through
  `-Arguments`. Hashtables come back wrapped in `PSObject` (`Update-CPJobs` unwraps them).
* **`ConvertFrom-Json` has a 2 MB limit in PS 5.1**: use `ConvertFrom-CPJson`.
* **Labels and `&`**: WinForms treats `&` as a mnemonic; set `UseMnemonic = $false` on labels
  that show user text, or write `&&` in button text.
* **One quick-save log per run**, no secrets in logs: the GitHub token must never be printed.
* **Every button needs an `Add_Click`** (a test checks `$ui.<Name> = New-CPButton` buttons).

## 15. Recipes: common changes

**Add a platform** (for detection, identity, online data):
1. `Get-CPPlatformInfo`: a regex for its URLs -> `Platform`, `Id` (and `Slug` if useful).
2. `Get-CPProblemKey`: a stable key (`'<platform>:' + id`).
3. `Get-CPKnownPlatforms`: add the name (Platform dropdown).
4. Optional: `Get-CPProblemMetadataOnce`: a `switch` branch that fills name/difficulty/topics.
5. Tests: add the URL to the table in section 2, an identity case in section 10.

**Add a language**: `Get-CPLanguage` (name, extension, header style) and
`Get-CPSourceExtensions`; built-in templates in `Get-CPBuiltInTemplates`
(`"<Language> - Basic.<ext>"` is the default); the file filter in the Settings "Add..." dialog.

**Add a setting**: default in `Get-CPDefaultConfig`; a checkbox in `Show-CPSettingsDialog`
(read it back in the Save button's handler); use it where needed. If an existing default must
change for current users, bump `ConfigVersion` and migrate in `Get-CPConfig`.

**Add a button to the save window**: `$ui.MyButton = New-CPButton 'Text'`, add it to `$btns`
or `$btns2`, then `$ui.MyButton.Add_Click({ Invoke-CPSafe -What 'My action' { ... } })` near the
other handlers. Slow work goes through `Start-CPJob`.

**Add a tray command**: `ListenFor('name')` in `Start-CPTray`, a menu item
`& $addItem 'Text' 'name'`, a branch in `$run`. The launcher passes any word through, so
`CPSaverLauncher.exe name` works; add a Start Menu shortcut in `install.ps1` if wanted.

**Add a test**: in `Run-Tests.ps1`, inside the `try` block, `Check 'what' (<condition>) 'detail'`.
Use `$tmp` for files; `RunGit <dir> <args>` for git.

**Make a release**: bump `$script:AppVersion`, add a `CHANGELOG.md` section, run the tests,
commit and push, then `powershell -ExecutionPolicy Bypass -File app\tools\New-Release.ps1`.

## 16. Debugging

* **Logs**: `%APPDATA%\CPSolutionSaver\host.log` (tray commands, errors), `launcher.log`,
  `last-quick-save.log`, and `%TEMP%\CPSolutionSaver-install.log` for the installer.
* **Run a window from source** without installing:
  `powershell -STA -ExecutionPolicy Bypass -File app\src\CPSaver.ps1` (or `-Browse`, `-Settings`,
  `-Quick`, `-Cli`).
* **A separate test copy** next to the real app (own settings, own tray, own hotkey events):
  ```bat
  set CPSAVER_DATA_DIR=%TEMP%\cpsaver-dev
  set CPSAVER_INSTANCE=dev
  "%LOCALAPPDATA%\Programs\CPSolutionSaver\CPSaverLauncher.exe" tray
  ```
  Commands then go to it with the same variables set (`CPSaverLauncher.exe browse`, `... exit`).
  Add `set GIT_CONFIG_GLOBAL=%TEMP%\cpsaver-dev\empty.gitconfig` to see the app as a user whose
  git has no name/email yet.
* **Restart the tray** after changing installed files: `CPSaverLauncher.exe exit`, then `tray`
  (the installer does this for you).
* **Try Core functions in a console**:
  `Import-Module .\app\src\CPSaver.Core.psm1 -Force; Read-CPHeader (Get-Content main.cpp -Raw)`.
