# Changelog

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
