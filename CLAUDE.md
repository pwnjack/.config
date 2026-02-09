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
echo "kitty" > ~/.config/options/terminal
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

Wallpaper image -> `wal -i` -> generates `~/.cache/wal/colors-*.conf` files -> symlinked/sourced by Hyprland (`colors.conf`), Waybar (`colors.css`), Rofi themes, SwayNC, and Mako. Changing the wallpaper via `scripts/hyprland/wall.sh` triggers this pipeline automatically.

### User Preferences (`options/`)

Simple text files (one value per file) that scripts read at runtime: `browser`, `terminal`, `editor`, `font`, `launchertype`, `mainmonitor`, `mediaplayer`, `screenshot`, `wallpaper` (symlink to current wallpaper). Scripts read these with `cat ~/.config/options/<name>` and use the value as-is.

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
| Terminal | Ghostty (primary), Kitty (fallback) |
| Notifications | SwayNC, Mako (fallback) |
| Shell | Fish + Starship |
| Editor | Neovim (LazyVim) |
| Theming | Pywal + GTK3/4 + Qt5/6 + Kvantum |

## Conventions

- The repo migrated from `~/Dots` to `~/.config` (Jan 2026). There should be no remaining references to `~/Dots`.
- Config is Arch/CachyOS-specific — package management uses `pacman` and `paru`/`yay` for AUR.
- Keybindings follow a macOS-inspired layout (Super key as primary modifier).
- `.gitignore` is aggressive (~318 lines) — only essential Hyprland/shell/utility configs are tracked. Application data directories (Obsidian, game launchers, Electron apps, etc.) are excluded.
