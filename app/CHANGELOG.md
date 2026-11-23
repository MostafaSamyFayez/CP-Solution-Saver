# Changelog

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
