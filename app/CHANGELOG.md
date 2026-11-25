# Changelog

## 2.8.0 - 2026-11-25

### Code viewer
- **Double-click** a problem in Solved problems (or press Enter, or the new **View code** button) to
  open its solution in a window with **syntax colouring** for C++, C, Python, Java, C#, JavaScript,
  Go, Rust and Kotlin: comments, strings, numbers, keywords, types, library names, function calls and
  `#include` lines each have their colour (like VS Code).
- Line numbers, light / dark theme (remembered), zoom (A- / A+ or Ctrl+wheel), **Copy code** (the
  selection or the whole file, never with the line numbers), Open problem page, Open file. Esc closes.
- The preview in Solved problems is coloured too.

### Solved problems: safer clicks
- Clicking a row (also on its star) only selects it: starring / unstarring is done **only with the
  Star button**.
- A double-click or Enter no longer loads a solution into your practice file: loading is done
  **only with the green Load button** (it still asks first and backs up your file).

## 2.7.1 - 2026-11-25

- **Check for updates** button in the save window (bottom row) and in Settings (next to the
  installed version number). It asks GitHub right away and shows *Version X is available*
  (*Update now* / *Later* / *Skip this version*) or *You have the latest version*. *Update now*
  downloads the new version, closes the window and runs the setup in update mode (settings,
  templates and solutions are kept). The tray menu item and the automatic check twice a day stay.

## 2.7.0 - 2026-11-25

### Analytics report
- **Report** button (save window, Solved problems), tray menu > *Analytics report*, Start Menu shortcut:
  opens a page with your progress - totals, this week / month, streaks, a calendar of the last year,
  total over time, problems per week, by level, by rating, average rating by month, top topics, a
  topic-by-level table, practice-next hints, platforms, languages, hardest / recent / starred problems.
- Built from the headers of the files in your solutions folder, so everything saved so far counts.
  Works offline, light and dark mode, hover for details.

### Levels, stars, numbers, sorting
- **Level** (Easy / Medium / Hard) for every problem: from LeetCode, your header, or the rating (under
  1200 Easy, 1200-1799 Medium, 1800+ Hard - cut-offs in Settings). Pick it by hand in the save window
  for unrated problems. Saved in the header; filters across platforms; index pages grouped by level.
- **Star** problems (save window checkbox, or *Star* / the star cell in Solved problems) and filter
  *Starred* only. Saved in the header, committed and pushed; kept when you save the problem again;
  the README gets a *Starred* list.
- **Numbers**: #1 is the first problem you solved (same problem in two languages = one number), shown
  in Solved problems, the index pages and the report.
- **Sorting** in Solved problems by #, star, difficulty (level, then rating), date, name, platform...;
  the last sort is remembered.

## 2.6.1 - 2026-11-23

- Update window: the release notes are shown as clean text (no markdown marks).
- The "updated" page no longer suggests deleting a downloaded folder.

## 2.6.0 - 2026-11-23

### Updates itself
- The app checks GitHub for a newer version (45 seconds after it starts, then every 12 hours) and
  **asks** before updating: *Update now* / *Later* / *Skip this version*, with the release notes.
- *Update now* downloads the new version and runs the setup in update mode: no questions, your
  shortcut choices, settings, templates and solutions are kept, no tour, the app restarts in the tray.
- Tray menu > **Check for updates...** checks right away; Settings has *Check for new versions
  automatically* (on by default).

### Quieter
- No Windows notifications when the app starts or after installing. (Quick save still uses one only
  if you chose notifications instead of the result window in Settings.)

## 2.5.0 - 2026-11-23

### Setup window
- `Install.bat` opens a small setup window instead of console text: what will happen, options
  (Desktop shortcut, start with Windows), a progress bar, and a final page with the shortcuts.
  If Git is missing it says so, with a link to download it. Errors are shown with the install log.
- After **Finish** the app opens right away: the welcome tour (shown again after every install,
  whatever happened before), Settings if needed, then the save window.
- `Install.bat -Console` and `-Quiet` still work in the console.

### Look
- Save window: the buttons sit in two tidy rows (main actions, then the rest); "Platform:" label.
- New screenshots in the README.

### For developers
- `app/docs/ARCHITECTURE.md`: a full guide to how the app works and how to change it.

## 2.4.2 - 2026-11-23

### Uninstall asks first
- *Uninstall CP Solution Saver* now opens a small window: **Uninstall** / **Cancel**, and a checkbox
  *Also delete my settings, code templates and backups* (off by default, so a reinstall remembers
  your setup). When it's done, a message says what was removed and what was kept.
- No console window. `uninstall.bat -Yes [-RemoveSettings]` still runs without questions.
- README: download button at the top.

## 2.4.1 - 2026-11-23

### Simpler download
- One file to download: **CP-Solution-Saver.zip** from the Releases page (link at the top of the README).
  Inside: `Install.bat`, the README, the license, and an `app` folder - nothing else to look at.
- The repo is tidied the same way: only `Install.bat`, `README.md`, `LICENSE` and `app/` at the top.
- `Install.bat` explains what to do if it is run from inside the zip without extracting it.
- After installing, the installer says the downloaded folder can be deleted.
- `app/tools/New-Release.ps1` builds the zip and publishes the GitHub release (for maintainers).

## 2.4.0 - 2026-11-23

### Easier for new users
- **Welcome tour** on first run: what the app does, the header, the three shortcuts, finding solutions
  again, and what to set up. See it again from the tray menu (*How to use...*), the *How to use*
  button in the window, or the Start Menu.
- **Git name and email**: if Git doesn't know them yet, a small window asks for them before the first
  save (and saves them with `git config --global`), instead of the save failing.
- **Any empty folder works as the solutions folder**: it becomes a new local repo automatically (in
  Settings and on the first save). A folder that already has files is only turned into a repo if you agree.
- **Connect this folder to GitHub...** (Settings): links a local-only solutions folder to a new (or your
  own empty) GitHub repo and uploads everything saved so far.
- If you use a shortcut before setting up, you get the tour / Settings instead of an error.

### Fewer files
- No more `save_solution.bat`, `quick_save.bat`, `solved_problems.bat` next to your project: the
  shortcuts, the tray icon and the Start Menu do the same. The installer removes the ones older
  versions made (only those; a `.bat` you wrote yourself is never touched).

### Tests
- 20+ new checks: empty-folder repos, connecting to a remote later, the name/email setup, cleaning up
  the old launchers, the tour flag, and a syntax check of every script.

## 2.3.2 - 2026-11-23

### Works without GitHub
- Tested and supported: a solutions folder made with just `git init` (no GitHub, no first
  commit). Saves are committed locally; connect GitHub later and push them all at once.
- If Git doesn't know your name/email yet, the save stops with a clear message telling you the
  two commands to run (before, it was a raw git error after the file was already written).

## 2.3.1 - 2026-11-23

### Fixed
- The **Solved problems...** button in the save window did nothing (its click handler was lost
  in the 2.3.0 rewrite). The self-tests now check that every window button is wired up.

## 2.3.0 - 2026-11-23

### Faster
- **Tray app**: a small background helper keeps the app loaded and owns the shortcuts, so the
  save window, quick save and solved problems open instantly. Measured on Windows: a shortcut
  reaches the app in about 0.01 s (was 2-4 s); a cold start is about 0.5 s; quick save from key
  press to result about 1 s plus the GitHub upload.
- `CPSaverLauncher.exe` / `CPSaver.Native.dll`: built at install time from `src/native/*.cs`
  with the C# compiler that ships with Windows (no extra downloads). Falls back to the previous
  launcher if they can't be built.
- Online lookups, saving/pushing and index rebuilds run in the background: windows never freeze.
- The list of saved solutions is cached; files are re-read only when they change.

### Looks and ease of use
- New style: dark header with the app icon and your progress ("N problems solved | M this week"),
  flat buttons, green main actions, cleaner Solved problems grid, sharp text on scaled screens.
- New app icon (tray, windows, shortcuts).
- Quick save: "Saving ..." box, then a result window with **Open on GitHub**.
- New shortcut **Ctrl+Alt+Shift+B** for Solved problems; tray menu with every action.
- Options: close the save window after saving (on), start with Windows (on).
- The installer restarts a running tray app when updating; the uninstaller stops it.


## 2.2.0 - 2026-11-23

### Added
- **Several languages**: one practice file per language (`main.cpp`, `main.c`, `main.py` ...);
  the most recently saved one is used, or pick it in the window. Python docstring headers and
  `//` / `#` comment headers are understood; saved files keep their extension.
- **Code templates**: 11 built-in templates (C++: Basic, Multiple test cases, Competitive,
  Graph, Number theory, DSU + Fenwick; C: 2; Python: 3) plus your own files in
  `%APPDATA%\CPSolutionSaver\templates`. Templates window: preview, load into the practice
  file (with backup), choose the template "reset after saving" uses per language.
- Window shows whether the problem is new, solved before (and when) or solved before in
  another language. Solved problems browser: Language column and filter.

### Changed
- **The problem link is required** and identifies the problem; different spellings of the same
  link (Codeforces contest vs problemset, LeetCode `/description`, query strings, `www`,
  trailing `/`) are recognized as the same problem.
- **Reset the practice file after a successful save is on by default** (can be turned off);
  quick save also resets after "already saved".
- **Quick save shows a message box in the middle of the screen** by default (Windows
  notification is an option). Existing settings are migrated to both new defaults.

### Fixed
- Saving the same problem again no longer counts as a new submission because of the date:
  the original *Date Solved* and link spelling are kept, so identical code gives
  "Already saved - nothing new to push".


## 2.1.0 - 2026-11-23

### Added
- **Quick save**: hotkey Ctrl+Alt+Shift+F (also `quick_save.bat`, Start Menu shortcut,
  `-Quick`) saves and pushes with no window and shows a notification with the result;
  errors show a message box that offers to open the full window. Option to always use a
  message box. Log of the last run in `%APPDATA%\CPSolutionSaver\last-quick-save.log`.
- **Solved problems browser** (`Solved problems...` button, `solved_problems.bat`, Start Menu,
  `-Browse`): search, filters by platform / topic / difficulty, sortable columns, code
  preview, and *Load into main.cpp* with an automatic backup of the current file.
- Online lookups retry once when a site times out.


## 2.0.0 - 2026-11-23

A full app instead of a single script.

### Added
- Window (GUI) with fields filled from the `main.cpp` header, live preview of the
  target file, topic picker, Save & Push (Ctrl+S), Rebuild index, open repo / GitHub.
- Settings window: practice file, solutions repo, clone or create a GitHub repo,
  template editing, default options, header upgrade.
- Richer header: Difficulty, Topics, Platform, Problem ID, Date Solved, multi-line
  Notes, aliases (Tags, Rating, URL...), custom fields preserved.
- Online lookup: Codeforces (name, rating, tags), LeetCode (name, number,
  difficulty, tags), AtCoder / CSES / other sites (name).
- Indexes generated from the file headers: README "Progress" section and
  `Index/BY_PLATFORM.md`, `Index/BY_TOPIC.md`, `Index/BY_DIFFICULTY.md`.
- Duplicate handling: same problem link updates the existing file, or keep both (`_v2`).
- `git pull --rebase` before committing; descriptive commit messages.
- Installer (per-user, no admin), Start Menu + Desktop shortcuts, global hotkey
  Ctrl+Alt+Shift+S, `save_solution.bat` launcher next to the practice project,
  uninstaller.
- Console mode (`cpsaver.cmd -Cli`, `-RebuildIndex`, ...).
- Self-tests (`run-tests.bat`), tested on Windows PowerShell 5.1 and PowerShell 7.

### Changed
- Default template uses MSVC-friendly includes.
- v1 `save_solution.ps1` replaced by `src/` (kept in git history).

## 1.0.0 - 2026-11-17

- `save_solution.ps1`: reads Problem Name/Link from `main.cpp`, copies it to
  `<Platform>/<ID>_<Name>.cpp` in the solutions repo, commits and pushes.
