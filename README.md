# CP Solution Saver

Save an accepted competitive-programming solution from your practice `main.cpp`
to your GitHub solutions repo **with one click**: it gets a clean file name, the
right folder, a complete header (name, link, difficulty, topics, date), and it
is listed in auto-generated indexes **by platform, by topic and by difficulty**.

Made for a Visual Studio C++ practice project on Windows. No admin rights, no
extra software besides Git.

![Main window](docs/screenshot-main.png)

---

## Contents

1. [What it does](#what-it-does)
2. [Install](#install)
3. [Daily use](#daily-use)
4. [The problem header](#the-problem-header)
5. [How the solutions repo is organized](#how-the-solutions-repo-is-organized)
6. [Settings](#settings)
7. [Visual Studio button (optional)](#visual-studio-button-optional)
8. [Console mode](#console-mode)
9. [Testing](#testing)
10. [Uninstall](#uninstall)
11. [Troubleshooting](#troubleshooting)
12. [Project layout](#project-layout)

---

## What it does

- **Reads the header** at the top of your `main.cpp` (problem name, link, difficulty, topics, notes).
- **Looks the problem up online** from the link, filling in what you left empty:
  - Codeforces: name, rating, tags
  - LeetCode: name, number, Easy/Medium/Hard, topic tags
  - AtCoder, CSES and others: name
- **Saves** the code into your solutions repo, e.g. `Codeforces/4A_Watermelon.cpp`,
  with a normalized header including the date solved.
- **Never duplicates**: saving the same problem again (same link) updates the existing
  file. You can also choose to keep both (`_v2`).
- **Updates the indexes**: README progress section, `Index/BY_PLATFORM.md`,
  `Index/BY_TOPIC.md`, `Index/BY_DIFFICULTY.md`.
- **Commits and pushes** (`git pull --rebase` first, so pushes don't get rejected),
  with messages like `Add Codeforces 4A - Watermelon` and the topics/difficulty in the body.
- Optionally **resets `main.cpp`** to your template for the next problem.

## Install

Requirements: Windows 10/11 and [Git for Windows](https://git-scm.com/download/win)
(already signed in to GitHub, i.e. `git push` works). PowerShell 5.1 is built into Windows.

1. Get this repo: `git clone https://github.com/MostafaSamyFayez/CP-Solution-Saver.git`
   (or *Code → Download ZIP* and unzip).
2. Double-click **`install.bat`**.
3. If it can't find your settings yet, the **Settings** window opens. Choose:
   - **Practice file**: the `main.cpp` you solve problems in.
   - **Solutions repo folder**: your local clone of the solutions repo.
     No repo yet? Click **Create a new GitHub repo...** (uses Git's existing GitHub sign-in)
     or **Clone a GitHub repo...**.

The installer:

| What | Where |
|---|---|
| App files | `%LOCALAPPDATA%\Programs\CPSolutionSaver` |
| Settings + template | `%APPDATA%\CPSolutionSaver\config.json`, `template.cpp` |
| Start Menu | *CP Solution Saver* folder (app, Settings, Read me, Uninstall) |
| Desktop | *CP Solution Saver* shortcut |
| Hotkey | **Ctrl+Alt+Shift+S** opens the app from anywhere |
| Practice project | `save_solution.bat` next to your `.sln` (opens the app) |

You can also install non-interactively:

```powershell
.\install.ps1 -MainCpp "C:\path\to\main.cpp" -RepoPath "C:\Users\me\Desktop\Problem-Solving-Solutions"
```

Updating = `git pull` in this repo and run `install.bat` again (your settings are kept).

## Daily use

1. Solve the problem in `main.cpp`. Fill at least the **link** in the header
   (the name, difficulty and topics are fetched for Codeforces/LeetCode).
2. Submit. When it's **Accepted**, press **Ctrl+S** in Visual Studio to save the file.
3. Press **Ctrl+Alt+Shift+S** (or double-click `save_solution.bat`, or the Desktop shortcut).
4. Check the fields, add topics with **Pick...** if you like, then **Save & Push** (or Ctrl+S in the app).
5. Done: the status line says *"... is on GitHub"*.

Window shortcuts: **Ctrl+S** save & push, **F5** reload `main.cpp`, **Esc** close.

If `main.cpp` changed after the window opened, it tells you; the newest code on disk is always what gets saved.

## The problem header

Put this comment at the very top of `main.cpp` (the template already has it):

```cpp
/*
 * Problem Name: Watermelon
 * Problem Link: https://codeforces.com/problemset/problem/4/A
 * Difficulty: 800
 * Topics: math, brute force
 * Notes: w must be even and > 2
 */
```

| Field | Required | Notes |
|---|---|---|
| `Problem Name` | yes* | *fetched from the link for Codeforces/LeetCode/AtCoder/CSES |
| `Problem Link` | recommended | decides the platform folder and the problem ID |
| `Platform` | no | detected from the link; set it for judges that aren't recognized |
| `Problem ID` | no | detected (e.g. `4A`, `abc300_a`, `1068`) |
| `Difficulty` | no | a rating (`800`, `1400`) or `Easy` / `Medium` / `Hard` |
| `Topics` | no | comma separated; merged with the online tags |
| `Notes` | no | can span several lines |

Aliases work too: `Name`, `Link`/`URL`, `Tags`, `Rating`/`Level`, `Date`.
Any other `Key: value` line (e.g. `Time Complexity: O(n)`) is kept in the saved file.

Saved files get a complete header:

```cpp
/*
 * Problem Name: Watermelon
 * Problem Link: https://codeforces.com/problemset/problem/4/A
 * Platform: Codeforces
 * Problem ID: 4A
 * Difficulty: 800
 * Topics: math, brute force
 * Date Solved: 2026-11-23
 * Notes: w must be even and > 2
 */
```

Recognized platforms: Codeforces (contest, problemset, gym), LeetCode, AtCoder, CSES,
CodeChef, SPOJ, Kattis, HackerRank, VJudge, UVa, Eolymp. Anything else goes to `Other/`.

## How the solutions repo is organized

```
Problem-Solving-Solutions/
├── README.md               <- your intro + auto "Progress" section (counts, top topics, recent)
├── Index/
│   ├── BY_PLATFORM.md      <- every problem, grouped by platform
│   ├── BY_TOPIC.md         <- grouped by topic (dp, greedy, graphs, ...)
│   └── BY_DIFFICULTY.md    <- grouped by rating / Easy-Medium-Hard
├── Codeforces/
│   └── 4A_Watermelon.cpp
├── LeetCode/
│   └── 0001_Two_Sum.cpp
├── AtCoder/  CSES/  Other/ ...
```

**Why folders by platform, and indexes for topic/difficulty?** A problem usually has
several topics, so topic folders would mean copies of the same file. The platform is
unique, so it's the folder; topics and difficulty are browsable through the generated
index pages (with links to both the problem and your solution). The indexes are rebuilt
from the file headers, so if you edit a header by hand, click **Rebuild index**.

Only the part of README.md between `<!-- CPSAVER:STATS:START -->` and
`<!-- CPSAVER:STATS:END -->` is generated; write anything you want around it.

## Settings

Open **Settings** in the window or *CP Solution Saver - Settings* in the Start Menu.

- Practice file and solutions repo folder (plus *Clone* / *Create new GitHub repo*)
- **Edit** the new-problem template (used by "Reset main.cpp after saving")
- Look up problems online (on by default)
- Push after saving (on), update indexes (on), reset `main.cpp` after saving (off)
- **Add Difficulty/Topics fields to my main.cpp header**: upgrades an old header without touching your code

Settings live in `%APPDATA%\CPSolutionSaver\config.json`.

## Visual Studio button (optional)

The global hotkey already works inside Visual Studio. If you also want a menu item:

1. **Tools → External Tools... → Add**
2. Title: `Save Solution`
3. Command: `C:\Windows\System32\wscript.exe`
4. Arguments: `"C:\Users\<you>\AppData\Local\Programs\CPSolutionSaver\CPSaver.vbs"`
5. OK. It appears in the **Tools** menu. To give it a shortcut: **Tools → Options →
   Environment → Keyboard**, search `Tools.ExternalCommand1` (the number = its position in the list).

Remember to save (`Ctrl+S`) before using it.

## Console mode

```bat
cpsaver.cmd -Cli                 :: shows what will be saved, asks, saves and pushes
cpsaver.cmd -Cli -Yes            :: no questions
cpsaver.cmd -Cli -NoFetch        :: don't look the problem up online
cpsaver.cmd -Cli -NoPush         :: commit only
cpsaver.cmd -Cli -KeepBoth       :: keep the older solution too (_v2)
cpsaver.cmd -RebuildIndex        :: regenerate README progress + Index/*.md, commit, push
cpsaver.cmd -Settings            :: open the settings window
cpsaver.cmd -Version
```

`cpsaver.cmd` is in the install folder (`%LOCALAPPDATA%\Programs\CPSolutionSaver`).

## Testing

Double-click **`run-tests.bat`** (or `powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Online`).
The tests create a temporary repo with a local remote, so your real repo and GitHub are never touched.
They cover header parsing, platform detection, saving/updating/keep-both, indexes, template reset,
console mode end to end and (with `-Online`) the Codeforces/LeetCode/CSES/AtCoder lookups.

## Uninstall

Start Menu → *CP Solution Saver* → **Uninstall CP Solution Saver**
(or run `uninstall.bat` in the install folder). App files and shortcuts are removed;
your solutions repo is never touched. Settings are kept unless you run
`uninstall.ps1 -RemoveSettings`.

## Troubleshooting

| Problem | Fix |
|---|---|
| *git push failed* | Your commit is saved locally. Run `git push` in the repo folder once to sign in, then use the app again. |
| *Online lookup failed* | No internet or the site is slow; fill the fields by hand. Codeforces data is cached for a day. |
| Wrong folder / name | Edit the fields in the window before saving, or set `Platform:` / `Problem ID:` in the header. |
| Hotkey does nothing | Another app uses Ctrl+Alt+Shift+S. Change it: right-click the Start Menu shortcut → Properties → Shortcut key. |
| Visual Studio asks to reload main.cpp | Expected after "Reset main.cpp"; choose **Yes**. |
| "running scripts is disabled" | Use the shortcuts / `.bat` files: they pass `-ExecutionPolicy Bypass` for this app only. |

## Project layout

```
src/CPSaver.ps1        entry point (window, console mode, rebuild index)
src/CPSaver.Core.psm1  all logic: header, platforms, online lookup, saving, git, indexes
src/CPSaver.Gui.ps1    Windows Forms window, settings, topic picker
install.ps1 / .bat     per-user installer
uninstall.ps1          uninstaller
tests/Run-Tests.ps1    self-tests
docs/                  screenshots
```

## License

MIT, see [LICENSE](LICENSE).
