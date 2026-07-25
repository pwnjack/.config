# Dotfiles Doctor & Lint Gate — Design

**Date:** 2026-07-25
**Repo:** `~/.config` (Hyprland dotfiles, Arch/CachyOS)
**Goal chosen by user:** a health-check that validates the *live* system, plus a lint gate that keeps script and panel quality from drifting. Report-only, derived from tracked files, no new sources of truth.

## Problem

This repo is unusually cross-referential. `keybinds.conf` hard-codes eight binaries. `hyprland.conf` sources eleven files. `wall.sh` fans out to four per-app color scripts. `options/` holds values a dozen scripts `cat` at runtime. Every one of these links can break silently — the session keeps running, one keybind just does nothing.

Today nothing detects that:

1. **`install.sh` validates only at install time.** It checks packages once, on a fresh machine. It never runs again, and it says nothing about symlinks, sourced files, or whether a daemon actually came up.
2. **No lint enforcement.** The shellcheck sweep in `0b340bc` was a one-time commit, not a gate. `ags/` has a `tsconfig.json` but nothing runs a compile check.
3. **Known rot is already present and went unnoticed** — see Evidence below.

### Evidence gathered while designing

Confirmed on the live system, 2026-07-25:

- **`flameshot` is listed in `install.sh:102` but is not installed.** `flameshot/` is tracked. Screenshots actually go through `hyprshot` (`keybinds.conf`) and `rofi/screenshot.sh`.
- **mako is dead.** `org.freedesktop.Notifications` is owned by swaync (PID 3933) — the DBus name a notification daemon must hold to receive any notification, and only one process can own it. mako is not running, has no `autostart.conf` entry, and no keybind references it. The only things touching it are `wall.sh:36` regenerating its colors on every wallpaper switch and `install.sh` backing it up.
  - **This corrects a prior decision.** `2026-07-19-dotfiles-polish-design.md` recorded "**mako stays** (still in use alongside SwayNC)" and placed its removal out of scope. That was an untested assumption; the DBus ownership check disproves it. The correction is recorded here rather than applied silently.
- **Two tracked symlinks hard-code the username.** `rofi/options/colors.rasi` and `waybar/colors.css` point at `/home/pwnjack/.cache/wal/...` absolutely. The `2026-07-15` CHANGELOG entry records "Portable symlinks: committed as relative symlinks instead of absolute `/home/<user>` paths" as a completed fix — it converted `hypr/config/colors.conf` and `options/wallpaper` but missed these two. They resolve on this machine and dangle on anyone else's. A partially-applied fix that reads as complete is precisely the class of rot doctor exists to catch.
- `rofi/keybinds-cheatsheet.sh` duplicates `keybinds.conf` as a hand-written `printf` block — two sources of truth for one dataset. Out of scope here, noted for a later project.

The point of doctor.sh is that findings like these surface automatically next time, for whatever the next component turns out to be. **The cleanup is an output of the tool, not a prerequisite for it** — the design deliberately does not delete anything up front.

## Design

### Core principle

Every check derives its targets from something already tracked. No manifest, no expected-state file, no list to maintain. Adding a keybind or an `exec-once` entry extends coverage automatically.

This is the same principle the cheatsheet violates, and the reason a hand-written `doctor/checks.conf` was rejected during design: it would be the cheatsheet bug rebuilt on purpose.

### Location and interface

Top-level `doctor.sh`, beside `install.sh`. It is a user-facing entry point, not a helper, and the README documents them symmetrically:

```bash
./install.sh    # set the system up
./doctor.sh     # verify it is still intact
```

**Report-only.** No `--fix`, no interactive prompts. Every finding prints the command that fixes it; the user runs it. This keeps the script safe to run at any time and free of repair logic that would need its own tests.

### Derivation table

| Check | Derived from | Severity |
|---|---|---|
| Dangling tracked symlink | `git ls-files -s`, mode `120000` | ERROR |
| Non-portable tracked symlink | same, target matching `^/home/` | WARN |
| Missing sourced config | `source =` lines in `hyprland.conf`, `hyprlock.conf` | ERROR |
| Missing pywal cache | `~/.cache/wal/colors-hyprland.conf` (target of `colors.conf`) | ERROR |
| Missing referenced path | every literal `~/.config/...` or `$HOME/.config/...` in any tracked file | ERROR |
| Missing `wall.sh` color script | the `apply_wal_colors.sh` paths listed in `wall.sh` | WARN |
| Keybind → absent binary | `exec,` targets in `keybinds.conf` | WARN |
| Autostart → absent binary | `exec-once =` in `autostart.conf` | WARN |
| Daemon not running | bare-binary `exec-once` entries → `pgrep -x` | WARN |
| Notification daemon identity | DBus owner of `org.freedesktop.Notifications` | INFO |
| Package drift | `PACKAGES=()` / `AUR_PACKAGES=()` parsed from `install.sh` vs `pacman -Q` | INFO |
| Orphan config | tracked config dir + no autostart entry + no running process | INFO |

Git reporting which files are symlinks is what makes the first two rows work without a list — mode `120000` in `git ls-files -s` output identifies all nine tracked symlinks (`ghostty/colors`, `gtk-3.0/thunar-colors.css`, `hypr/config/colors.conf`, `mako/config`, `options/wallpaper`, `rofi/options/colors.rasi`, `rofi/options/wallpaper.rasi`, `waybar/colors.css`, `waypaper/config.ini`) with no enumeration. This is exactly why derivation beats a manifest: a hand-written list would have been seeded from the same incomplete memory that produced the partial 2026-07-15 portability fix.

### Variable resolution

`keybinds.conf` invokes commands through Hyprland variables. Doctor resolves them the way Hyprland does before checking the binary:

- `$terminal`, `$browser` → `cat options/{terminal,browser}`
- `$fileManager`, `$textEditor` → `hypr/config/apptype.conf`
- `$polkitAgent` → `apptype.conf`

An unresolvable variable is itself a WARN — it means a config references something no longer defined.

### Severity model

- **ERROR** — the session is broken or will break on next login. Dangling symlink, missing `source` target, absent pywal cache.
- **WARN** — degraded. A keybind that silently does nothing, a daemon that failed to start.
- **INFO** — tidiness. Orphaned config, package drift, which process owns the notification bus.

**Exit 1 if any ERROR, else 0.** WARN and INFO never fail the run, so doctor stays usable in a script.

No suppression mechanism. There is no ignore file: a finding is either fixed or the thing that caused it is deleted. An ignore list would become a third source of truth where stale entries hide, and a doctor you have taught to stay quiet is a doctor you stop reading.

### Output

Grouped by category, findings under a one-line summary per group, fix command indented beneath each finding:

```
▸ Symlinks & cache
  ✓ 5 tracked symlinks resolve
  ✗ ERROR  hypr/config/colors.conf → ~/.cache/wal/colors-hyprland.conf (dangling)
           fix: wal -i "$(readlink -f ~/.config/options/wallpaper)"

▸ Packages
  · INFO   flameshot listed in install.sh PACKAGES but not installed
           fix: sudo pacman -S flameshot   (or drop it from install.sh:102)

2 errors, 3 warnings, 4 notices
```

Reuses `install.sh`'s existing `info` / `warning` / `success` helpers so the two entry points look like one tool.

### Scope boundaries

Two deliberate exclusions, both to avoid false positives that would train the user to ignore output:

1. **Scripts are not scanned for the binaries they invoke.** Reliably extracting "what commands does this bash script call" is a false-positive swamp — variables, heredocs, conditionals, and functions all defeat naive parsing. The repo's scripts already guard with `command -v` by convention, which handles the failure locally. Script *paths* are still validated by the referenced-path rule.
2. **One-shot `exec-once` entries are excluded from the process check.** `restore-wallpaper.sh`, `startup.sh`, and `watch_wallpaper.sh` are expected to exit. Only bare-binary entries get `pgrep`'d: waybar, swaync, swayosd-server, awww-daemon, hypridle, ags.

## Pre-commit hook

Tracked at `scripts/hooks/pre-commit`, activated by `install.sh` via:

```bash
git config core.hooksPath scripts/hooks
```

Using `core.hooksPath` rather than copying into `.git/hooks` means the hook is version-controlled, updates with a pull, and cannot silently diverge from the repo.

Behavior, on staged files only:

- staged `*.sh` → `shellcheck -S warning`
- staged `ags/**` → `ags bundle app.ts <scratch>`, output discarded

**On the AGS gate:** `ags bundle` is the only compile check available. There is no `tsc`, no `package.json`, and no `node_modules` in `ags/` — the `ags/gtk4` JSX types come from the AGS installation. esbuild catches syntax errors but **not type errors**, so `strict: true` in `ags/tsconfig.json` is currently unenforced. Accepted limitation: a syntax gate is worth having, and adding a real typecheck means installing TypeScript plus generating types via `ags types`, which is its own project.

**Separate from doctor.sh by design.** The hook validates code being committed; doctor validates the live system. Different questions, different cadence, no shared code beyond the output helpers.

## Verification

Acceptance is that doctor reproduces, unprompted, the findings established by hand during design:

- INFO: `flameshot` in `install.sh` PACKAGES, not installed
- INFO: mako orphaned — swaync owns `org.freedesktop.Notifications`
- WARN: `rofi/options/colors.rasi` and `waybar/colors.css` use absolute `/home/pwnjack` targets
- clean: all 9 tracked symlinks resolve; all 15 `source =` targets resolve
- exit 0 on the current system — verified 2026-07-25 that no ERROR-class condition exists today

Negative tests, run against a scratch copy so the live system is untouched:

- break a tracked symlink → ERROR, exit 1
- remove a `source =` target → ERROR, exit 1
- rename a binary out of PATH → WARN, exit 0

Hook tests: stage a script with a shellcheck warning → commit blocked; stage a `.tsx` with a syntax error → commit blocked; stage a clean change to both → commit succeeds.

## Out of scope

- Deleting `flameshot/`, `mako/`, or any other config. Doctor reports; removal is a separate decision made with its output in hand.
- Generating the rofi cheatsheet from `keybinds.conf`.
- GitHub Actions. Arch-only dependencies (`ags`, `astal`) make CI realistically shellcheck-only, and the hook already covers that locally.
- Auto-repair in any form.
- A real TypeScript typecheck for `ags/`.
