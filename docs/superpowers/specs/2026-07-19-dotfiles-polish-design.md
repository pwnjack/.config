# Dotfiles Polish — Design

**Date:** 2026-07-19
**Repo:** `~/.config` (Hyprland dotfiles, Arch/CachyOS)
**Goals chosen by user:** clean & lean (only actively-used configs tracked) + smooth daily driving (no runtime git churn). Light-touch script work only — no structural refactor.

## Problem

1. Dead configs are tracked: `wofi/`, `wlogout/`, `kitty/kitty.conf` are superseded (Rofi launcher/powermenu, Ghostty terminal); `scripts/settings/placeholder.sh` is a stub.
2. Every wallpaper switch rewrites four tracked files (`mako/config`, `options/wallpaper`, `rofi/options/wallpaper.rasi`, `waypaper/config.ini`), leaving the repo permanently dirty.
3. `.claude/` and `paneflow/` sit untracked with no decision recorded.
4. Assorted script debris: dead fallback branches, shellcheck warnings, a possible stale `eww` reload in `wall.sh`.

## Design

### 1. Removals & repo hygiene

Delete `wofi/`, `wlogout/`, `kitty/kitty.conf`, and `scripts/settings/placeholder.sh`, including every reference: their blocks in `install.sh`, kitty fallback branches in `scripts/hyprland/startup.sh`, `scripts/fonts/apply-font.sh`, `scripts/settings/settings.sh`, and the settings menu entry pointing at the placeholder. Fallback-terminal logic uses the value of `options/terminal` instead of hardcoding kitty. **mako stays** (still in use alongside SwayNC).

Track `.claude/` and `paneflow/` after inspecting contents; gitignore anything that is cache, session state, or secrets.

Update `CLAUDE.md` and `README.md` so docs stop mentioning removed tools.

### 2. Wallpaper-churn fix (approach A: template + cache + symlink)

Principle: **tracked files never change at runtime.** Generated state lives in `~/.cache`, reached via tracked *relative* symlinks — the same pattern `hypr/config/colors.conf` already uses.

| File | Today | New design |
|---|---|---|
| `options/wallpaper` | `wall.sh` repoints this tracked symlink at each new wallpaper | Stable tracked symlink → `../../.cache/current_wallpaper`; `wall.sh` repoints the cache link instead. All ~16 consumers (hyprlock, rofi themes, sddm scripts) keep their paths. |
| `rofi/options/wallpaper.rasi` | `wall.sh` echoes a new `url(...)` into it | Tracked symlink → `../../../.cache/wal/rofi-wallpaper.rasi`; `wall.sh` writes there. |
| `mako/config` | `mako/apply_wal_colors.sh` seds colors in place | Tracked `mako/config.template` with placeholders; script renders template + pywal palette → `~/.cache/wal/mako-config`; `mako/config` is a tracked symlink to it. Font changes (via `apply-font.sh`, if it touches mako) route through the same render. |
| `waypaper/config.ini` | waypaper rewrites its own config on wallpaper pick | Tracked symlink → `~/.cache/waypaper-config.ini` + tracked template — **contingent on verifying** waypaper's save preserves symlinks. If waypaper does an atomic replace, plan B for this file only: untrack it and track `config.ini.example`. |

Fresh installs: the existing `install.sh` deploy step gains a render call that creates `~/.cache/current_wallpaper` (pointing at a bundled wallpaper) and renders the three generated files, so the system works before the first `wal -i`.

Migration on this machine: run the render once, convert the four files, commit. `git status` is clean from then on.

### 3. Light-touch script cleanup

- `shellcheck` across all scripts; fix real warnings only (quoting, word-splitting), no stylistic churn.
- Remove dead branches: kitty fallbacks, references to removed tools, and the `eww reload` in `wall.sh` **only after** confirming eww appears nowhere else in the setup.
- Keep the `sleep` timing hacks in `wall.sh` — load-bearing for the pywal pipeline.
- Error-handling idiom stays as-is ("check then act"); just ensure no script references a file the cleanup removed.

## Out of scope

- Shared `lib.sh` helper extraction or any script restructure (explicitly declined).
- Removing mako.
- New features.

## Verification

This is a live desktop; every change is exercised for real:

1. Wallpaper switch via waypaper → colors propagate (ghostty, waybar, mako, swaync, rofi background) **and** `git status --short` is empty.
2. `hyprctl reload` after hypr config edits; open rofi launcher/powermenu/screenshot menus to confirm the background import.
3. `bash -n` + `shellcheck` on every edited script; run each edited script once where safe.
4. `./install.sh --dry-run` after installer edits.

## Commit strategy

Small logical commits on `main`, one per domain: removals → churn fix → script cleanup → docs → tracking `.claude/`+`paneflow/`. Each independently revertable.
