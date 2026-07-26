# Changelog

All notable changes to this dotfiles repository.

## [2026-07-26] - Night Light

### Added
- **`scripts/hyprland/nightlight.sh`**: the single entry point for hyprsunset
  (`toggle|on|off|auto|status|waybar`). The keybind, the waybar module and the
  settings panel all call it; none of them talks to `hyprctl hyprsunset`.
- **`hypr/hyprsunset.conf`**: the schedule, as clock-time `profile` blocks
  (07:00 neutral / 20:00 warm). Tracked and panel-writable, the same
  arrangement as `hypr/hypridle.conf`. `exec-once = hyprsunset` joins the
  System Services block in `autostart.conf`.
- **Two keybinds**: `$Mod SHIFT + D` toggles, `$Mod CTRL + D` returns to the
  schedule. Both self-document in the Super+H cheatsheet from their trailing
  comments, and `doctor.sh` picked both up with no new check.
- **Waybar `custom/nightlight`**, restored from the dead commented-out module
  but stateful: it reads real daemon state, so the icon cannot lie. Dim sun =
  neutral, moon = warm, pill background = manual override. The orphaned
  `#custom-nightlight` CSS rule left behind by the old removal is live again.
- **Three Power rows in the settings panel** (`ags/lib/hyprsunset.ts`,
  mirroring `hypridle.ts`): warmth, and both schedule boundaries. Times are
  minutes-from-midnight behind a slider so the panel cannot emit a time
  hyprsunset would reject.

### Notes
- **There is no state file, by design.** The daemon is the state, so all three
  surfaces agree by construction, and a manual override expires on its own when
  the daemon's profile timer next fires — no expiry logic to maintain.
- **`profile { gamma = 100 }` is read as 10000% and kills the daemon.** Profile
  gamma is a multiplier, not a percentage. It is optional, so it is omitted;
  top-level `max-gamma` *is* a percentage.
- **`identity` has no getter** — bare `identity` is a setter returning `ok`, and
  `temperature` still reports its old value while identity masks it. `off`
  writes the neutral temperature instead, which keeps state readable.
- **`--config` does not work** in hyprsunset 0.4.0 despite being in the binary's
  strings and absent from `--help`; the config path is fixed.
- **Icons resolve differently in the panel and in notifications**, and both bite.
  In the panel, symbolic names work but **Papirus-Dark ships its symbolic
  `status/` set with the light theme's `#444444`**, so `night-light-symbolic`
  renders invisible even though `Gtk.IconTheme.has_icon` returns true — the row
  uses `redshift-status-on-symbolic` (symlinked into `panel/`, correctly themed).
  In notifications, **swaync 0.12.6 renders no symbolic icon at all**, leaving
  the slot blank, so `notify-send` uses the non-symbolic `weather-clear-night` /
  `weather-clear` — which also mirror the bar's moon/sun glyphs. A name that
  renders in the panel proves nothing about a toast.
- `ags bundle` is esbuild, which strips types without checking them — a clean
  bundle is not a typecheck, and the ags/gi ambient types are not vendored, so
  standalone `tsc` cannot run against this tree at all.

## [2026-07-26] - Pywal Theming Completed

### Added
- **`scripts/theming/apply-wal.sh`**: fan-out driver for the wallpaper palette.
  It **globs** for `<component>/apply_wal_colors.sh` instead of listing
  components, so adding a themed component is one new file — no edit to the
  driver, to `wall.sh`, or to `install.sh`. Both of those now call it and name
  nothing. Every apply script must leave its output existing, falling back to
  defaults when pywal has not run, which is what keeps the tracked symlinks
  from dangling on a fresh checkout.
- **`scripts/theming/palette.sh`**: shared loader. `wal_load` fills a `wal`
  array from `~/.cache/wal/colors`; `wal_readable_on <hex>` picks the text
  color per background from BT.601 brightness. A wallpaper palette gives no
  contrast guarantees — the same slot can come out near-black on one image and
  near-white on the next, so any fixed foreground is unreadable half the time.
- **cava, btop and Starship follow the wallpaper.** cava and Starship are
  templated (`config.in`, `starship.toml.in`), since neither program can
  include another file; btop uses its native theme directory.

### Changed
- **Starship was tracked but inert.** Nothing ever initialised it, so the
  CachyOS vendor `fish_prompt` was in charge and `starship.toml` was never
  read. `fish/config.fish` now starts it, and the hardcoded Nord/orange hex is
  a `color1..color6` powerline ramp.
- `ghostty/` and `Thunar/` apply scripts no longer exit early on missing pywal
  input, so `install.sh` could drop its per-component `touch` fallbacks.

### Fixed
- **`install.sh` created an absolute symlink for `hypr/config/colors.conf`**,
  baking one machine's home path into a tracked file. Now relative.
- **`cava` was missing from the package list** despite `cava/` being tracked.
- **`$python` was styled with the language color** while sitting in the first
  powerline block, so an active virtualenv punched a mismatched chunk into it.

### Notes
- **cava 0.10.7 cannot use its own theme mechanism.** It corrupts the heap and
  aborts with `free(): invalid next size` on any vertical `gradient` — theme
  file or main config, at every stop count (5/5 crashes vs 0/5 for
  `horizontal_gradient`). Its own bundled `themes/solarized_dark` crashes it
  identically, so this is upstream. The palette goes to `horizontal_gradient`,
  which colours the spectrum by frequency.
- **fastfetch needed no change.** Its `keyColor` values and the CachyOS logo
  emit ANSI indices, and ghostty maps all 16 palette entries from pywal, so it
  already followed the wallpaper.
- btop is themed but has no reload signal: a running instance keeps the old
  colors until restarted.

## [2026-07-26] - Doctor & Lint Gate

### Added
- **`doctor.sh`**: report-only health check for the live system. Validates
  tracked symlinks, Hyprland `source` chains, literal `~/.config` references,
  keybind and autostart binaries, running daemons, D-Bus role ownership, and
  `install.sh` package drift. Every target is derived from tracked files, so
  there is no list to keep in sync. Exits 1 only on ERROR-class findings.
- **Pre-commit hook** (`scripts/hooks/pre-commit`, activated via
  `core.hooksPath`): `shellcheck` on staged scripts, the doctor test suite
  when `scripts/doctor/` changes, `ags bundle` on staged panel sources.
- **Doctor test suite** (`scripts/doctor/test/`): 207 assertions across a
  dependency-free harness that runs each check against throwaway git fixtures.

### Fixed
- **`install.sh --dry-run` could not run non-interactively.** `read` returns
  non-zero at EOF, and under `set -e` that aborted the script at the first
  prompt — so the dry run failed whenever any package was missing. Predates
  this work; surfaced by needing to verify the hook wiring.

### Found by doctor.sh, and fixed
- **`exec-once = $polkitAgent` had never worked.** `hyprpolkitagent` is
  installed but ships no executable on `PATH` — only
  `/usr/lib/hyprpolkitagent/hyprpolkitagent`, a systemd user unit, and a D-Bus
  activation file. The autostart line failed silently on every login; polkit
  prompts worked only because D-Bus activated the agent on demand. Now started
  through its systemd unit, which also picks up `Restart=on-failure`. The
  binary check gained systemd-unit validation so routing through `systemctl`
  does not blind the check that found this.
- **mako was inert.** swaync owns `org.freedesktop.Notifications`, the D-Bus
  name a notification daemon must hold to receive anything, so mako's config
  had no effect. `mako/` and its references in `wall.sh`, `install.sh` and
  `CLAUDE.md` are gone. This corrects the "mako stays (still in use alongside
  SwayNC)" decision recorded in the 2026-07-19 polish spec, which was never
  tested. The *package* stays — `cachyos-hyprland-settings` requires it.
- `rofi/options/colors.rasi` and `waybar/colors.css` were tracked symlinks
  with absolute `/home/pwnjack` targets, dangling for any other user. Now
  relative, completing the 2026-07-15 "portable symlinks" fix that converted
  two of four cases and missed these.
- `waypaper/config.ini.template` referenced a `style.css` and a
  `keybindings.ini` that have never existed. Removed.
- `flameshot` was listed in `install.sh` but not installed, and `flameshot/`
  was tracked while screenshots go through `hyprshot` and
  `rofi/screenshot.sh`. Both removed.

### Removed
- Four waybar module definitions no bar array referenced
  (`custom/appmenu`, `custom/wallpaper`, `custom/nightlight`,
  `custom/hyprpicker`) and their commented-out entries. Every defined module
  is now active; recoverable from git history if one is wanted back.
- `herdr/` runtime logs and session state are now gitignored.

## [2026-07-15] - Fresh-Install Hardening

### Fixed
- **install.sh now deploys**: running from a clone outside `~/.config` copies
  the dotfiles into place (previously it only installed packages)
- **Portable symlinks**: `hypr/config/colors.conf` and `options/wallpaper`
  are committed as relative symlinks instead of absolute `/home/<user>` paths
- **AUR detection**: `-bin`/`-git` package variants are now recognized as
  satisfying a dependency
- **SDDM scripts**: removed hardcoded username/paths; `setup-sudo.sh` now
  generates the sudoers rule itself (the referenced `sddm-wallpaper-sudoers`
  file never existed) and grants NOPASSWD only for `update_sddm_root.sh`
- **settings.sh**: fixed wrong-case script paths, `$cursortheme` variable
  mismatch, and references to files that don't exist (Guide/, dotsupgrade.sh,
  waybar/settings/items.jsonc); removed leftover GeoDots upgrade/remove menus
- **wall.sh**: no longer fails when optional components (Thunar, mako, eww,
  ags) are missing; all per-app color scripts are existence-checked
- **fish config**: CachyOS-specific config and zoxide are now optional
  (vanilla Arch compatible)
- **Tracked missing runtime deps**: `Thunar/apply_wal_colors.sh` (called by
  wall.sh but previously git-ignored) and `options/cursortheme`

### Changed
- **Package list**: single list auto-classified between pacman and AUR at
  install time; added everything the configs actually reference (hyprshot,
  hyprpicker, hyprsunset, jq, ffmpeg, inotify-tools, brightnessctl,
  pavucontrol, blueman, waypaper, aichat, ags/astal, ...)
- **monitor.conf**: added `monitor=,preferred,auto,1` fallback so unknown
  displays work out of the box
- **Docs**: README/QUICKSTART installation flow rewritten to match reality

### Removed
- `scripts/waybar/waybaropt.sh` and its `Super+Ctrl+B` bind (referenced
  waybar theme dirs that don't exist in this repo)
- Empty, unused `waybar/settings.jsonc`

## [2026-01-10] - Major Restructure

### Added
- **Self-contained structure**: Migrated from `~/Dots` to `~/.config` only
  - Created `~/.config/scripts/` for all helper scripts
  - Created `~/.config/wallpapers/` for wallpaper collection
  - Created `~/.config/options/` for user preference files
- **Installation script** (`install.sh`): Automated setup for fresh installations
  - Package dependency checking and installation
  - Pywal initialization
  - Backup creation
  - Symlink management
- **Comprehensive documentation**:
  - `README.md` with full setup instructions and troubleshooting
  - This `CHANGELOG.md` for tracking changes
- **Improved scripts**:
  - Added error handling to all shell scripts
  - Added command existence checks before execution
  - Added proper headers and comments to all scripts

### Changed
- **Path updates**: All config files now reference `~/.config` paths instead of `~/Dots`
  - `hyprland.conf`: Browser/terminal paths updated
  - `hyprlock.conf`: Wallpaper and script paths updated
  - `autostart.conf`: Script paths and monitor detection updated
  - `mediaexec.sh`: Options paths updated with fallbacks
  - `startup.sh`: Complete rewrite with error handling
  - `watch_wallpaper.sh`: Monitor path updated
- **Application defaults**:
  - Terminal: Changed from kitty to ghostty (with fallback)
  - Text editor: Changed from obsidian to nvim
  - Maintained: Zen browser, thunar, vesktop
- **Pywal integration**: Fixed symlink to properly sync with pywal
  - `~/.config/hypr/config/colors.conf` now properly symlinked to `~/.cache/wal/colors-hyprland.conf`
- **Configuration style**:
  - Standardized all comments to proper format
  - Added descriptive headers to all config files
  - Improved inline documentation

### Fixed
- **Symlink issue**: `colors.conf` was a regular file, now properly symlinked to pywal
- **Missing error handling**: Scripts now check for command existence
- **Git conflicts**: Removed `topgrade.toml` deletion from staging
- **Path dependencies**: All hardcoded paths to `~/Dots` removed

### Improved
- **.gitignore**: Enhanced to exclude all non-essential application configs
  - Explicitly excludes: Cursor, Obsidian, game launchers, VLC, etc.
  - Explicitly includes: Essential Hyprland, shell, and utility configs
  - Added patterns for new custom directories
- **Comments and documentation**: All config files have proper headers
- **Script robustness**: Commands check for existence before running
- **Terminal preference**: Ghostty set as primary with automatic fallback

### Removed
- Dependency on `~/Dots` directory structure
- Post-install and post-upgrade scripts (not needed for clean installs)
- References to kitty as primary terminal
- Hard dependency on external directory structure

## Migration Notes

### For Existing Users

If you're updating from the old structure:

1. The `~/Dots` directory is no longer used - all content is in `~/.config`
2. Scripts moved to `~/.config/scripts/`
3. Wallpapers moved to `~/.config/wallpapers/` (symlink to `~/Pictures/Wallpapers` also works)
4. Options files moved to `~/.config/options/`
5. Run `wal -i /path/to/wallpaper` to regenerate pywal colors if colors don't work

### Breaking Changes

- Scripts in `~/Dots/Scripts/` will no longer work - use `~/.config/scripts/`
- Wallpaper path changed - update your wallpaper symlinks
- Options path changed - any custom scripts reading `~/Dots/Options/` need updating

## Future Improvements

Planned enhancements:
- [ ] Add systemd user service for hypridle (cleaner than exec-once)
- [ ] Create theme switcher script for different style presets
- [ ] Add backup script for easy config snapshots
- [ ] Create update script to pull latest changes safely
- [ ] Add monitoring script to check for broken dependencies
- [ ] Document keybinding customization guide
- [ ] Add screenshots to README
- [ ] Create video tutorial for installation

## Credits

- Template base by @GeodeArc
- Restructured and polished: 2026-01-10
