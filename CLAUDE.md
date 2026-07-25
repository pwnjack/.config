# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Hyprland dotfiles repository for Arch Linux / CachyOS. The entire repo lives at `~/.config` and is self-contained — all scripts, wallpapers, and user preferences are within this directory. Dynamic color theming is driven by pywal, which generates a 16-color palette from the active wallpaper and propagates it to Hyprland, Waybar, Rofi, SwayNC, and Mako.

## Key Commands

```bash
# Install on fresh system (interactive, checks deps via pacman/paru)
./install.sh              # Full install
./install.sh --dry-run    # Preview without changes
./install.sh --no-backup  # Skip config backup

# Validate the live system (report-only; exits 1 only on ERROR findings)
./doctor.sh

# Run the doctor's own test suite
./scripts/doctor/test/run-tests.sh

# Apply a new color scheme from wallpaper
wal -i /path/to/wallpaper.jpg

# Fix broken pywal symlink
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf

# Reload Hyprland config
hyprctl reload

# Restart waybar
killall waybar && waybar &

# Change user preferences (plain text files)
echo "firefox" > ~/.config/options/browser
echo "ghostty" > ~/.config/options/terminal
```

## Architecture

### Hyprland Config (modular, sourced from `hypr/hyprland.conf`)

```
hypr/config/
├── colors.conf              # Symlink -> ~/.cache/wal/colors-hyprland.conf
├── apptype.conf             # Default app definitions
├── hardware/
│   ├── monitor.conf         # Display resolution/layout
│   └── input.conf           # Keyboard/mouse settings
├── looks/
│   ├── decor.conf           # Borders, blur, rounding
│   └── animations.conf      # Window animations
├── setup/
│   ├── envvars.conf         # Environment variables
│   └── autostart.conf       # exec-once startup apps
└── software/
    ├── keybinds.conf        # All keyboard shortcuts
    ├── general.conf         # Misc settings
    └── rules.conf           # Window-specific rules
```

### Pywal Color Flow

Wallpaper image -> `wal -i` -> generates `~/.cache/wal/colors-*.conf` files -> symlinked/sourced by Hyprland (`colors.conf`), Waybar (`colors.css`), Rofi themes, and SwayNC. Changing the wallpaper via `scripts/hyprland/wall.sh` triggers this pipeline automatically. Generated state lives under `~/.cache` (`current_wallpaper`, `wal/rofi-wallpaper.rasi`, `wal/mako-config`, `wal/ghostty-colors`, `wal/thunar-gtk.css`, `waypaper-config.ini`); the repo tracks only symlinks to it, so wallpaper switches never dirty git.

### User Preferences (`options/`)

Simple text files (one value per file) that scripts read at runtime: `browser`, `terminal`, `editor`, `font`, `launchertype`, `mainmonitor`, `mediaplayer`, `screenshot`. `wallpaper` is a symlink to `~/.cache/current_wallpaper`, maintained by `wall.sh`. Scripts read these with `cat ~/.config/options/<name>` and use the value as-is.

### Scripts (`scripts/`)

- `hyprland/` — Startup, wallpaper switching (`wall.sh`), media control, AI chatbox launcher
- `waybar/` — Bar management and toggling
- `settings/` — Config utilities, updates, monitor detection
- `fonts/` — Font application automation

All scripts are bash. They check for command existence before running and read preferences from `options/`.

### API Keys

Stored in `~/.config/.env` (git-ignored). Template at `.env.example`. Loaded by Fish shell on startup and by the AI assistant launcher. Supports: `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`.

## Core Stack

| Role | Tool |
|------|------|
| WM | Hyprland (Wayland) |
| Bar | Waybar |
| Launcher | Rofi |
| Terminal | Ghostty |
| Notifications | SwayNC (toast + sidebar) |
| Shell | Fish + Starship |
| Editor | Neovim (LazyVim) |
| Theming | Pywal + GTK3/4 + Qt5/6 + Kvantum |

## Conventions

- The repo migrated from `~/Dots` to `~/.config` (Jan 2026). There should be no remaining references to `~/Dots`.
- Config is Arch/CachyOS-specific — package management uses `pacman` and `paru`/`yay` for AUR.
- Keybindings follow a macOS-inspired layout (Super key as primary modifier).
- `.gitignore` is aggressive (~318 lines) — only essential Hyprland/shell/utility configs are tracked. Application data directories (Obsidian, game launchers, Electron apps, etc.) are excluded.
- `doctor.sh` and its check modules derive every target from tracked files. When adding a check, never introduce a hand-written list of paths, binaries, or packages — parse the config that already declares them. A list is a second source of truth and will drift.
- Check modules must never run their loops in a pipeline (`cmd | while read`); the severity counters are shell variables and would be lost in the subshell, silently discarding every finding. Use `while read ...; do ... done < <(cmd)`. The test harness greps for this and fails the suite.
- Use `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git ls-files` — git C-quotes paths containing non-ASCII or quote characters, and the quoted form names no file on disk.
- `scripts/doctor/` and `docs/` are excluded from the doctor's literal-path scan: both deliberately contain example paths that do not exist.

## Doctor Architecture (`scripts/doctor/`)

```
doctor.sh                    # Entry point: sources lib + modules, guards the repo, exits 1 on ERROR
scripts/doctor/
├── lib.sh                   # group/ok/err/warn/note/summary, counters, doctor_q, doctor_require_repo
├── checks/
│   ├── symlinks.sh          # check_symlinks   — from `git ls-files -s` mode 120000
│   ├── references.sh        # check_references — from `source =` lines and literal ~/.config paths
│   ├── binaries.sh          # check_binaries   — from keybinds.conf `exec,` and autostart `exec-once`
│   └── services.sh          # check_services   — from autostart daemons, D-Bus roles, install.sh arrays
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module, sourced into one shared shell
```

All modules are sourced into a single shell, so: one public `check_<name>` function each, private helpers prefixed (`_sym_`, `_ref_`, `_bin_`, `_svc_`), and reserved names (`group ok err warn note summary doctor_reset doctor_q doctor_require_repo _finding`) are never redefined. Host probes (`pgrep`, `pacman`, `busctl`) each live in their own tiny function so tests can stub them.

`ok` is the all-clear and nothing else — print it only when a check found nothing at all, never as a consolation summary. Every path in a fix hint goes through `doctor_q`, and hints never contain `<placeholder>` text (the shell parses `<foo>` as a redirection).
