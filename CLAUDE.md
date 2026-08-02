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

# Run every test suite in the repo (or --list to see which ones exist)
./test.sh

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

Wallpaper image -> `wal -i` -> generates `~/.cache/wal/colors-*.conf` files -> symlinked/sourced by Hyprland (`colors.conf`), Waybar (`colors.css`), Rofi themes, and SwayNC. Changing the wallpaper via `scripts/hyprland/wall.sh` triggers this pipeline automatically. Generated state lives under `~/.cache` (`current_wallpaper`, `wal/rofi-wallpaper.rasi`, `wal/ghostty-colors`, `wal/thunar-gtk.css`, `wal/cava-config`, `wal/btop.theme`, `wal/starship.toml`, `waypaper-config.ini`); the repo tracks only symlinks to it, so wallpaper switches never dirty git.

Components that need more than a plain include own a `<component>/apply_wal_colors.sh`. `scripts/theming/apply-wal.sh` is the driver: it **globs** for those scripts rather than listing them, so adding a themed component is one new file — no edit to the driver, to `wall.sh`, or to `install.sh`. Both of those call the driver and name no component.

Every `apply_wal_colors.sh` must:

1. Render into `~/.cache/wal/` and never write a tracked file.
2. **Always leave its output existing**, falling back to defaults when the pywal input is missing. The repo tracks a symlink to that output, and a dangling tracked symlink is an ERROR in `doctor.sh` — on a fresh checkout the cache is empty.
3. Be idempotent, and a no-op when its component is not installed.
4. Reload its own running consumer if that is possible. The driver knows nothing about `swaync-client` or `SIGUSR2`.

`scripts/theming/palette.sh` is the shared loader: `wal_load` fills a `wal` array from `~/.cache/wal/colors` (with a built-in fallback palette), and `wal_readable_on <hex>` returns whichever of the darkest/lightest palette entries stays legible on that background. Use it rather than re-parsing pywal output — a wallpaper palette gives no contrast guarantees, so any fixed text color is unreadable on some wallpapers.

Two components are templated (`<component>/<name>.in` -> rendered to cache -> tracked file is a symlink) because neither program has an include mechanism: **cava** and **starship**. Edit the `.in` file, never the symlink. cava is templated rather than using its native `theme =` support because cava 0.10.7 corrupts the heap on any vertical `gradient`, theme file or not — `horizontal_gradient` is the working path. **btop** uses its native theme directory instead, and **fastfetch** needs nothing: its `keyColor` values and the distro logo are ANSI indices, which the terminal already resolves to the pywal palette.

### Night Light (hyprsunset)

`hyprsunset` runs as a daemon from `autostart.conf` and owns the schedule in `hypr/hyprsunset.conf` — a tracked, panel-writable file, the same arrangement as `hypr/hypridle.conf`. `scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`; the keybind ($Mod SHIFT+D toggle, $Mod CTRL+D follow-schedule), the waybar `custom/nightlight` module and the panel's Power rows all call the script.

There is deliberately **no state file** — the daemon is the state, so every surface agrees by construction. A manual override is just a temperature write, which the daemon's own profile timer reclaims at the next scheduled boundary; that is what makes overrides self-expiring with no expiry logic to maintain.

Gotchas, all found by probing the binary rather than reading docs:

- **Profile `gamma` is a multiplier, not a percentage.** `gamma = 100` inside a `profile` block is read as `10000%` and the daemon *exits*. It is optional and defaults to 100%, so the profiles simply omit it. Top-level `max-gamma` **is** a percentage.
- **`identity` has no getter.** Bare `hyprctl hyprsunset identity` is a *setter* returning `ok`, and `temperature` keeps reporting its last set value while identity masks it — so identity state is unreadable. `off` therefore writes the neutral temperature instead of using identity, keeping state readable.
- **`--config` is not a working flag** in v0.4.0 despite the string being in the binary; the path is fixed. Changing the schedule means restarting the daemon (there is no reload request), which is what `ags/lib/hyprsunset.ts` does.
- **A crashed daemon leaves a stale socket**, so `pgrep` is not a liveness probe — only an actual request is.
- `reset temperature` re-applies the active profile; that is the `auto` subcommand.
- The waybar module declares `"signal": 8` so the script can `pkill -RTMIN+8 waybar` for an instant icon update instead of waiting out the interval.
- **Icons need different names in the panel and in notifications** — two separate traps:
  - *In the panel* (GTK4 `icon-name` lookup), symbolic icons work, but **Papirus-Dark ships its symbolic `status/` set with the light theme's `#444444`**, so `night-light-symbolic` renders invisible on a dark plate even though `Gtk.IconTheme.has_icon` returns true. Only entries symlinked into `panel/` are correctly themed. Check the resolved SVG's `ColorScheme-Text` before trusting a symbolic icon.
  - *In notifications*, **swaync 0.12.6 renders nothing at all for Papirus-Dark's symbolic icons** — it reserves the icon slot and leaves it blank. `notify-send -i` must use the **non-symbolic** name (`weather-clear-night`, not `weather-clear-night-symbolic`). A name that renders in the panel is no evidence it renders in a toast; screenshot the toast.

### Gaming (WoW / Battle.net)

`docs/gaming-wow.md` is the single source for this — **read it before touching
any game rule.** The launch chain is Faugus -> gamescope -> Battle.net -> WoW, so
the Hyprland client is *gamescope*, not the game, and every rule in
`rules.conf`'s `## GAME WINDOW RULES` block exists twice for that reason. The
launcher side (`faugus-launcher/**`) is git-ignored because Faugus rewrites it
every session, so the doc records that recipe as prose — including which flag
fixed what, and which tuning ideas were measured and rejected (gamemode buys
`nice -4` here and nothing else). Don't re-derive that survey.

### User Preferences (`options/`)

Simple text files (one value per file) that scripts read at runtime: `browser`, `terminal`, `editor`, `font`, `launchertype`, `mainmonitor`, `screenshot`. `wallpaper` is a symlink to `~/.cache/current_wallpaper`, maintained by `wall.sh`. Scripts read these with `cat ~/.config/options/<name>` and use the value as-is. `mainmonitor` is the one preference that is legitimately empty: empty means "no preference", and every consumer resolves it itself. hyprlock draws on every monitor via `$monitor =` in `hardware/primary.conf`; `wall.sh`, `restore-wallpaper.sh`, and both SDDM scripts fall back to whichever monitor awww reports first. Nothing guesses a connector name: a tracked default such as `DP-1` or `eDP-1` is wrong on the next machine, which `scripts/doctor/checks/hardware.sh` now guards. `hypr/config/hardware/monitor.conf` is host-neutral for the same reason and uses `highres@highrr`, not `preferred` or bare `highrr`: measured on this panel, `preferred` selected 2560x1440@59.951, while applying the combined form from 1024x768@60 selected 2560x1440@143.998.

### Scripts (`scripts/`)

- `hyprland/` — Startup, wallpaper switching (`wall.sh`), media control, night light (`nightlight.sh`), AI chatbox launcher
  - Media: `medialib.sh` is a sourced helper that picks *which* player the waybar module follows (first `Playing`, else first with a title). `mediaexec.sh` renders it (waybar JSON, or one plain line for hyprlock with `--plain`) and `mediactl.sh` drives transport through the same choice, so the title shown and the player controlled can never diverge. There is deliberately no stored player preference — bare `playerctl` picks by bus registration order, and selecting per-poll is what removed the old left-click scope toggle.
- `waybar/` — Bar management and toggling, plus `battery.sh`: the battery module for the whole machine. It reads `/sys/class/power_supply` directly because waybar's own module counts only `SCOPE=System` and so reported nothing on this desktop. `SCOPE` selects behaviour rather than filtering — `Device` peripherals stay hidden until they fall below 25% (the module appearing is the warning, which is what keeps it stateless), while system batteries are always visible and accumulate, with the alert class taking the minimum across discharging ones. A powered-off peripheral keeps its node *and* its last reading, so `POWER_SUPPLY_ONLINE` present-and-`0` is the skip test; a laptop battery has no `ONLINE` at all and must not be caught by it. Charge state is trusted for system batteries only. `BATTERY_SYSFS` overrides the scan root — that seam is how `test-battery.sh` runs without hardware, and how the bar is screenshotted with the module forced visible without editing a tracked file.
- `settings/` — Config utilities, updates, monitor detection
- `fonts/` — Font application automation
- `theming/` — Pywal fan-out driver (`apply-wal.sh`) and the shared palette loader (`palette.sh`)

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
- `rofi/keybinds-cheatsheet.sh` (Super+H) renders itself from `keybinds.conf` at runtime — never hand-edit the rows. A binding's trailing `#` comment is its label (`$vars` inside are resolved); without one the label comes from the dispatcher. Preview with `./rofi/keybinds-cheatsheet.sh --print`.
- `doctor.sh` and its check modules derive every target from tracked files. When adding a check, never introduce a hand-written list of paths, binaries, or packages — parse the config that already declares them. A list is a second source of truth and will drift.
- Check modules must never run their loops in a pipeline (`cmd | while read`); the severity counters are shell variables and would be lost in the subshell, silently discarding every finding. Use `while read ...; do ... done < <(cmd)`. The test harness greps for this and fails the suite.
- Use `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git ls-files` — git C-quotes paths containing non-ASCII or quote characters, and the quoted form names no file on disk.
- `scripts/doctor/` and `docs/` are excluded from the doctor's literal-path scan: both deliberately contain example paths that do not exist.
- `./test.sh` discovers suites rather than listing them: a tracked file is an entry point if it is named `run-tests.sh`, or matches `test-*.sh` and its directory has no `run-tests.sh`. Name a new suite either way and it is picked up — by the runner and by the pre-commit hook — with no registration step. A suite's *owning directory* is its own directory minus a trailing `test/` component, and that is what decides which commits run it; a top-level `test/` maps to the whole repo, which is why `test/test-runner.sh` runs on every commit. Each suite is run as `bash <path>` in its own subshell and the only contract is its exit code, so a sourced-fragment harness and a standalone script coexist unchanged.
- `scripts/hooks/pre-commit` decides nothing about which suites to run — it passes the staged paths to `test.sh --for`. It builds two staged listings on purpose: `--diff-filter=ACM` for shellcheck and `ags bundle` (a deleted file cannot be linted) and an unfiltered one for suite selection (a deletion is exactly when a suite most needs to run). Both use `--no-renames`, or git's single `R` record hides one of the two paths.

## Doctor Architecture (`scripts/doctor/`)

```
doctor.sh                    # Entry point: sources lib + modules, guards the repo, exits 1 on ERROR
scripts/doctor/
├── lib.sh                   # group/ok/err/warn/note/summary, counters, doctor_q, doctor_require_repo
├── checks/
│   ├── symlinks.sh          # check_symlinks   — from `git ls-files -s` mode 120000
│   ├── references.sh        # check_references — from `source =` lines and literal ~/.config paths
│   ├── binaries.sh          # check_binaries   — from keybinds.conf `exec,` and autostart `exec-once`
│   ├── services.sh          # check_services   — from autostart daemons, D-Bus roles, install.sh arrays
│   ├── waybar.sh            # check_waybar     — from config.jsonc's modules-* arrays and handler values
│   └── hardware.sh          # check_hardware   — /sys/class/drm present set vs tracked files
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module; sourced into one shared shell
```

All modules are sourced into a single shell, so: one public `check_<name>` function each, private helpers prefixed (`_sym_`, `_ref_`, `_bin_`, `_svc_`, `_way_`, `_hw_`), and reserved names (`group ok err warn note summary doctor_reset doctor_q doctor_require_repo _finding`) are never redefined. Host probes (`pgrep`, `pacman`, `busctl`, `command -v` via `_way_have_cmd`, `/sys/class/drm` via `_hw_present_outputs`) each live in their own tiny function so tests can stub them — or aim them at a fixture, which is what `DOCTOR_DRM_SYSFS` does.

`ok` is the all-clear and nothing else — print it only when a check found nothing at all, never as a consolation summary. Every path in a fix hint goes through `doctor_q`, and hints never contain `<placeholder>` text (the shell parses `<foo>` as a redirection).
