# Changelog

All notable changes to this dotfiles repository.

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
