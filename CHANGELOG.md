# Changelog

All notable changes to this dotfiles repository.

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

### Found (reported, not acted on)
- **`exec-once = $polkitAgent` has never worked.** `hyprpolkitagent` is
  installed but ships no executable on `PATH` — only
  `/usr/lib/hyprpolkitagent/hyprpolkitagent`, a systemd user unit, and a D-Bus
  activation file. The autostart line fails silently on every login; polkit
  prompts work only because D-Bus activates the agent on demand.
- **mako is inert.** swaync owns `org.freedesktop.Notifications`, the D-Bus
  name a notification daemon must hold to receive anything. This corrects the
  "mako stays (still in use alongside SwayNC)" decision recorded in the
  2026-07-19 polish spec, which was never tested.
- `rofi/options/colors.rasi` and `waybar/colors.css` are tracked symlinks with
  absolute `/home/pwnjack` targets. The 2026-07-15 "portable symlinks" fix
  converted two of four cases and missed these.
- `waypaper/config.ini.template` references a `style.css` and a
  `keybindings.ini` that do not exist.
- `flameshot` is listed in `install.sh` but is not installed; `flameshot/` is
  tracked while screenshots go through `hyprshot` and `rofi/screenshot.sh`.

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
