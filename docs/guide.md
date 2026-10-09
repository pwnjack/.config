# Guide

Everything beyond the [README](../README.md): how the pieces fit, day-to-day use,
customization and maintenance. Keybindings have their own generated page,
[keybindings.md](keybindings.md).

## Core Stack

| Component | Application |
|-----------|-------------|
| Window Manager | Hyprland |
| Status Bar | Waybar |
| Launcher | Rofi |
| Settings panel | Quickshell (Super+I, exits when closed) |
| Terminal | Ghostty (`options/terminal`) |
| Notifications | SwayNC |
| Lock Screen | Hyprlock |
| File Manager | Thunar / Yazi |
| Browser | Zen Browser (`options/browser`) |
| Editor | Neovim |
| Shell | Fish + Starship |

## Structure

```
~/.config/
├── hypr/          # Hyprland: modular Lua config from hyprland.lua,
│                  # plus Hyprlang configs for hyprlock/idle/sunset
├── waybar/        # Bar: config.jsonc, style.css, pywal colors
├── rofi/          # Launcher, power and clipboard menus
├── swaync/        # Notification daemon and sidebar
├── quickshell/    # On-demand settings panel, wallpaper carousel, keybinds overlay
├── options/       # User preferences, one value per text file
├── scripts/       # doctor/, theming/, waybar/, hyprland/, hooks/, docs/
├── fish/ ghostty/ nvim/ btop/ cava/ starship/   # Per-app config
├── claude/ codex/ # Optional AI agent harness (see below)
├── docs/          # This guide and deep dives (keybindings, gaming)
├── test/          # Tests for the runner and the generated docs
├── install.sh     # Fresh-system setup
├── doctor.sh      # Health check (see Maintenance)
└── test.sh        # Test runner (see Maintenance)
```

`CLAUDE.md` carries the detailed `hypr/config/` breakdown and the design notes
behind each piece. Files ending in `.in` are templates and their non-`.in`
counterparts are generated symlinks — edit the template.

## Everyday use

### Keybindings
| Key | Action |
|-----|--------|
| `Super + Enter` | Terminal (`options/terminal`) |
| `Super + Space` | App launcher |
| `Super + Q/W` | Close window |
| `Super + L` | Lock screen |
| `Super + H` | Keybindings overlay |

Those five are the ones worth memorising.
**[docs/keybindings.md](keybindings.md) has every binding**, grouped by
section — or press `Super + H` for the same list, searchable, without leaving
the desktop.

Both are rendered from `hypr/config/software/keybinds.lua` by one parser, so
neither can drift from the bindings it documents. After editing the config, run
`./scripts/docs/generate-keybindings.sh`; `test/test-docs.sh` fails on a stale
copy, so the pre-commit hook catches a forgotten regeneration.

Navigation follows one rule: **every window and workspace binding carries `Super`**,
so `Alt`/`Ctrl` + arrows always reach the focused app (browser back/forward,
shell word jumps, editor line moves, TUI prompts). On the arrows, `Super` alone
moves focus, `+ Shift` moves the window, `+ Alt` resizes it, and `+ Ctrl`
switches workspace (`+ Ctrl + Shift` takes the window along). Ghostty's own
`Ctrl + Enter` fullscreen is unbound; `Super + F` is the one fullscreen key.

### Feature notes

The **colour picker** (`Super + Shift + C`) copies the selected screen pixel as
a lowercase hex value and sends a notification.

**Annotation** is opt-in, so the quick grab stays quick: `Super + Alt + S`
captures a region straight into swappy, and the capture strip
(`Super + Shift + S`) has an Annotate toggle for the same flow. Saved images land in `~/Pictures/Screenshots`
with an `_annotated` suffix. swappy reports success by closing, which means you
can save *or* copy one annotation, not both.

The **pending-updates module** sits between the disk and network readouts and
appears only when repository or AUR updates exist — the module showing up is
the notification. Left-click opens `scripts/settings/update.sh` in your
configured terminal; right-click forces a refresh. The AUR command comes from
`options/aurhelper`, and repository checks need `pacman-contrib`
(`checkupdates`).

The **night-light module** reflects the temperature `hyprsunset` has actually
applied. Left-click (or `Super + Shift + D`) switches between warm and neutral
as a manual override — both are overrides, and the daemon reclaims either at
the next scheduled boundary. Right-click (or `Super + Ctrl + D`) hands control
back to the schedule in `hypr/hyprsunset.conf` immediately.

`Super + Shift + B` restarts Waybar; `Super + Alt + B` shows and hides it.

### Idle efficiency

The settings panel and wallpaper carousel are launched on demand and exit when
closed, so neither keeps a UI runtime resident. Waybar uses signals for
workspace changes, media controls, night-light actions, and completed updates;
their intervals are safety fallbacks rather than the primary refresh path.
Compared with the previous intervals, custom workspace, media, and GPU commands
drop from about 92 launches per idle minute to 16. The GPU module also limits
`nvidia-smi` to one probe every 30 seconds. See the component docs for measured
panel and carousel memory.

### Media

Media keys play/pause and skip in whichever player is active; `playerctl`
does the same from a terminal.

### Clipboard
```bash
# View clipboard history
cliphist list | rofi -dmenu | cliphist decode | wl-copy

# Or use keybind (check keybinds.lua)
```

## Configuration

### Configuration Files

| Component | Location |
|-----------|----------|
| Hyprland | `~/.config/hypr/hyprland.lua` |
| Waybar | `~/.config/waybar/config.jsonc` |
| Terminal | `~/.config/ghostty/config` |
| Shell | `~/.config/fish/config.fish` |
| Fuzzy finder (Ctrl+R history, Ctrl+T file, Alt+C cd) | `~/.config/fish/conf.d/fzf.fish` |
| Git diffs (delta; identity stays in `~/.gitconfig`) | `~/.config/git/config` |
| Editor | `~/.config/nvim/` |
| Keybinds | `~/.config/hypr/config/software/keybinds.lua` |


### Quick edits

```bash
# Change default browser
echo "firefox" > ~/.config/options/browser

# Change default terminal
echo "ghostty" > ~/.config/options/terminal

# Change primary monitor. Leave this EMPTY for no preference: hyprlock then
# draws on every monitor, and wallpaper scripts use the first monitor awww
# reports (what a single-monitor machine wants). The settings panel (Super+I)
# writes this file and hypr/config/hardware/primary.conf together.
echo "HDMI-A-1" > ~/.config/options/mainmonitor

# Edit keybindings
nvim ~/.config/hypr/config/software/keybinds.lua
```

### User Preferences

Simple text files in `~/.config/options/`:

```bash
~/.config/options/
├── browser      # zen-browser
├── terminal     # ghostty
├── launchertype # vertical
├── mainmonitor  # empty = no preference
└── ...
```

### Wallpaper Carousel

**Super+Ctrl+W** toggles a fullscreen wallpaper carousel on the focused monitor.
Browse with Left/Right, the mouse wheel, or a card click. Press Enter, click the
selected card, or use **Apply wallpaper** to apply to all monitors. **Ctrl+F**
searches filenames; **Escape** closes without applying a selection.

The carousel reads the folder from Waypaper and keeps the existing awww/pywal
theme pipeline. **Super+Shift+W** still selects a random wallpaper; run `waypaper`
for the original picker and folder settings. Quickshell starts on first use.
See [controls, integration, and verification](wallpaper-carousel.md).

### Pywal Colors

Generate colors from any wallpaper:

```bash
wal -i /path/to/wallpaper.jpg
```

Colors automatically apply to Hyprland, Waybar, Rofi, SwayNC, ghostty, Thunar,
cava, btop, Neovim and the Starship prompt. Open Neovim windows re-theme in
place unless you picked another colour scheme in them; before pywal has run
once, Neovim uses LazyVim's tokyonight. fastfetch and bat (and so man pages)
follow too, without rendering anything — they colour by ANSI index, and the
terminal palette is pywal's.

Components needing more than a plain include own a
`<component>/apply_wal_colors.sh`, rendering into `~/.cache/wal/`. The repo
tracks only a symlink to the result, so switching wallpapers never dirties git.
`scripts/theming/apply-wal.sh` runs them all — it finds them by glob, so adding
a themed component means adding one file and nothing else:

```bash
# Re-render every component's colors without changing the wallpaper
~/.config/scripts/theming/apply-wal.sh
```

Two components are templated because neither program can include another file:
edit `cava/config.in` and `starship/starship.toml.in`, never `cava/config` or
`starship.toml` — those are symlinks to the rendered copies.

### Visual Tweaks

**Blur & Rounding:** `~/.config/hypr/config/looks/decor.lua`
```lua
hl.config("decoration", {
    rounding = 18,
    blur = { enabled = true, size = 6, passes = 4 },
})
```

**Animations:** `~/.config/hypr/config/looks/animations.lua`

**Window Rules:** `~/.config/hypr/config/software/rules.lua`

### Displays

Use the Displays page of the settings panel (Super+I). Per-machine rules are written to ~/.local/state/hypr/monitors.lua and loaded by ~/.config/hypr/config/hardware/monitor.lua, which stays host-neutral.

### Startup applications
Edit: `~/.config/hypr/config/setup/autostart.lua`
```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("your-app")
end)
```


### Waybar modules

Edit `~/.config/waybar/config.jsonc`; `Super + Shift + B` restarts the bar.

### Window rules
Edit: `~/.config/hypr/config/software/rules.lua`
```lua
hl.window_rule({
    name = "float-your-app",
    match = { class = "^(your-app)$" },
    float = true,
})
```

## API Keys & Environment Variables

API keys and secrets are stored in `~/.config/.env` (git-ignored).

### Setup

```bash
# Copy the example file
cp ~/.config/.env.example ~/.config/.env

# Edit with your API keys
nano ~/.config/.env
```

### Supported Keys

- `GEMINI_API_KEY` - Google Gemini AI
- `OPENAI_API_KEY` - OpenAI/ChatGPT (optional)
- `ANTHROPIC_API_KEY` - Claude (optional)
- `GROQ_API_KEY` - Groq (optional)
- `MISTRAL_API_KEY` - Mistral (optional)

The `.env` file is automatically loaded by:
- Fish shell (on startup)
- AI assistant launcher script

### Security

- `.env` is git-ignored and never committed
- Use `.env.example` as a template in your repository
- Keep your API keys private

## AI agent harness (optional)

`claude/` and `codex/` hold a delegation harness for Claude Code and Codex:
global instructions, routing and review skills, one hook, and curated
settings. Only what was written here is tracked — logins, history, memory,
caches and anything the tools write themselves stay out of the repo, so a
fresh machine stays fresh.

`install.sh` offers it (default No) when Claude Code or Codex is installed; it
carries the repo owner's personal agent instructions and plugins, so it is
never applied silently. `scripts/agents/setup.sh` skips any tool that is not
installed. After installing and signing in to Claude Code and/or Codex, run:

```bash
~/.config/scripts/agents/setup.sh            # or --dry-run to preview
```

It symlinks the skills, hook and global instructions into `~/.claude` and
`~/.codex`, merges `claude/settings.json` into the live settings (other keys are
left alone), installs the listed Claude plugins, and lets Herdr install its own
hooks when Herdr is present. Codex models are named by codename (`sol`,
`luna`, …) and always resolve to the newest listed version; see
`claude/skills/_shared/handoff.md`.

## Maintenance

```bash
./doctor.sh          # validate the live system
./doctor.sh --help   # usage
```

`doctor.sh` reports and never modifies anything. Every check derives its
targets from tracked files — git's symlink modes, Lua `require()` calls,
`hl.exec_cmd()` targets in keybinds and autostart, and the package arrays in
`install.sh` — so adding a keybind or an autostart entry extends coverage
automatically. There is no list to keep in sync.

| Severity | Meaning | Exit code |
|----------|---------|-----------|
| `ERROR` | The session is broken or will break on next login | exits 1 |
| `WARN` | Degraded — a keybind does nothing, a daemon did not start | exits 0 |
| `INFO` | Tidiness — orphaned config, package drift | exits 0 |

What it checks:

- **Symlinks** — dangling targets, non-portable absolute paths, and links
  clobbered by a regular file (which git still reports as a symlink)
- **Config references** — every Lua `require()` and Hyprlang `source =` target,
  every literal `~/.config` path in a tracked file, the `wall.sh` colour
  fan-out, and both Hyprland/Hyprlock pywal caches
- **Binaries** — every command passed to `hl.exec_cmd()` by keybinds or
  autostart, resolving the application table indirection first
- **Services** — autostart daemons actually running, who owns
  `org.freedesktop.Notifications`, and `install.sh` package drift
- **Waybar** — every module on the bar has a config block, every block is on
  the bar, and every command an `exec`, click or scroll handler invokes is
  installed
- **Hyprctl Lua compatibility** — tracked runtime calls do not use the removed
  `hyprctl keyword` or positional dispatcher forms

A pre-commit hook (`scripts/hooks/pre-commit`, activated by `install.sh` via
`core.hooksPath`) runs `shellcheck` on staged shell scripts and the test suites
covering whatever the commit touches. The Quickshell panel has its own UI and
backend suite. All checks run in a private snapshot of the index, so partially staged
changes are checked as they will be committed. The working tree and real index
are untouched. The snapshot contains staged files and blobs, without commit
history. Bypass with `git commit --no-verify`.

Run every test suite with `./test.sh`. Suites are discovered, not registered:
`./test.sh --list` prints the current set and each one is runnable on its own,
so naming and tracking a new file `test-*.sh` or `run-tests.sh` is the whole of
adding one. Run new, untracked suites directly until they are staged. The panel
persistence suite uses Node.js with built-in TypeScript support and module hooks
(verified with Node.js 26.8.2); installation and hook fixtures use Python 3.

## Installation details

The install script checks/installs all dependencies, deploys the configs to
`~/.config`, initializes pywal, and wires up all symlinks. Deployment copies
only tracked files and backs up exactly the existing files it will replace,
including symlinks. Untracked application data stays out of deployment;
directory symlinks and file/directory conflicts are rejected before copying:

```bash
# Clone anywhere (a fresh ~/.config is never empty, so use a staging dir)
git clone https://github.com/pwnjack/.config.git ~/dotfiles
cd ~/dotfiles
./install.sh            # interactive; use --dry-run to preview
```

Log out and select Hyprland from your display manager.

To keep `~/.config` itself under git afterwards (this repo is designed to
live there):

```bash
cd ~/.config
git init -b main
git remote add origin https://github.com/pwnjack/.config.git
git fetch origin
git reset origin/main   # marks repo files as tracked without touching them
```

### Manual

```bash
# Core (official/CachyOS repos)
sudo pacman -S hyprland hyprlock hypridle hyprpolkitagent hyprshot swappy \
               hyprpicker hyprsunset waybar swaync quickshell rofi rofi-emoji \
               ghostty fish starship fzf fd neovim zed kwrite thunar yazi \
               btop bottom fastfetch cava playerctl cliphist wl-clipboard \
               python-pywal qt5ct qt6ct nwg-look pavucontrol blueman \
               nm-connection-editor gnome-calculator jq ffmpeg inotify-tools \
               zoxide git-delta shellcheck python nodejs gjs pacman-contrib ttf-firacode-nerd \
               ttf-cascadia-mono-nerd ttf-nerd-fonts-symbols noto-fonts \
               noto-fonts-emoji

# AUR / CachyOS-only (paru or yay)
paru -S zen-browser-bin vesktop waybar-weather awww waypaper aichat resources

# Initialize pywal and render every component's cache file
wal -i ~/.config/wallpapers/wall1.jpg
~/.config/scripts/theming/apply-wal.sh

# Set fish as default shell (optional)
chsh -s $(which fish)
```

### Keeping your changes in git

```bash
cd ~/.config
git add -A && git commit -m "Describe your change"
git pull   # pick up updates
```

### Backup and restore
```bash
# Backup current config
cp -a ~/.config/hypr ~/hypr-backup-$(date +%Y%m%d)

# Restore
cp -a --remove-destination ~/hypr-backup-DATE/. ~/.config/hypr/
```

Installer backups mirror the relative paths of files it replaces. To restore
one, copy its **contents** back into `~/.config`:

```bash
cp -a --remove-destination ~/.config-backup-YYYYMMDD-HHMMSS/. ~/.config/
```

This restores backed-up files; it does not remove files first introduced by
installation. Existing destination directories should be real directories,
not symlinks to another configuration tree.

## Troubleshooting

**Colors not updating after wal:**
```bash
hyprctl reload
```

**Pywal symlink broken:**
```bash
~/.config/hypr/apply_wal_colors.sh
```

**Waybar issues:**
```bash
killall waybar && waybar &
```

**Lock screen not working:**
```bash
killall hypridle && hypridle &
```

**Restart notifications:**
```bash
killall swaync && swaync &
```

**Colors look wrong everywhere:**
```bash
wal -i ~/.config/wallpapers/wall1.jpg   # regenerate the palette
~/.config/hypr/apply_wal_colors.sh      # re-render Hyprland + Hyprlock colors
hyprctl reload
```
btop has no reload signal, so a running instance keeps the old colors until
you restart it.

**Logs:**
```bash
# Hyprland log
cat /tmp/hypr/$(/usr/bin/ls -t /tmp/hypr | head -n 1)/hyprland.log

# Systemd user services
systemctl --user status hypridle
```

More help: the [Hyprland wiki](https://wiki.hyprland.org).
