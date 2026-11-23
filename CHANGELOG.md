# Changelog

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
