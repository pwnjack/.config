# Changelog

All notable changes to this dotfiles repository.

## [2026-08-02] - Unwired Tools

Closes the last of the four backlog chunks: three programs that were installed
on this machine and reachable from nothing.

### Added
- **Colour picker** on `$Mod SHIFT+C` (`scripts/hyprland/colorpicker.sh`).
  `hyprpicker` had been installed by `install.sh` and advertised in the README
  while bound to nothing, so a fresh machine paid for it and got nothing. Copies
  the hex and raises a toast. Corrects both defects in the `custom/hyprpicker`
  module deleted in `d952dfa`: `color-select-symbolic` renders **blank** in
  swaync 0.12.6, and the colour was passed as the notification title rather than
  its body. Emits lowercase hex via `-l`, and guards `wl-copy` as well as
  `hyprpicker` — an unguarded `wl-copy` is the one failure mode that actively
  misinforms, claiming "Colour copied" when nothing was.
- **Screenshot annotation** on `$Mod ALT+S` and as a fourth entry in the
  `$Mod SHIFT+S` menu (`scripts/hyprland/screenshot-annotate.sh`), capturing a
  region straight into `swappy`. `swappy` was installed with zero references
  anywhere in the repo and was not even listed in `install.sh`. Existing capture
  paths are untouched — annotation is opt-in, because an editor in front of
  every capture taxes the quick grab that is most of what screenshots are for.
  A tracked `swappy/config` points the save directory at
  `$HOME/Pictures/Screenshots` with the same filename format as every other
  screenshot; `$HOME`, not an absolute home path, per the host-neutral rule.
- **Pending-updates module** on the bar between `disk` and `network`
  (`scripts/waybar/updates.sh`), hidden entirely when nothing is due. This
  machine has no working notifier: `~/.config/autostart/arch-update-tray.desktop`
  names an uninstalled binary and Discover's carries `OnlyShowIn=KDE`. The AUR
  helper is derived from `options/aurhelper` rather than hardcoded, and the
  click opens the `scripts/settings/update.sh` that already existed rather than
  duplicating it.
- **`scripts/waybar/test-updates.sh`**, a sixteen-assertion suite discovered by
  `test.sh` with no registration step.

### Fixed
- **`pacman-contrib` was missing from `install.sh`**, so on a fresh install
  `checkupdates` would be absent, the repo count would silently fall to zero and
  the new module would never appear — recreating the very problem it exists to
  solve. Also added to the README package list, and `swappy` to
  `CONFIGS_TO_BACKUP` so an existing config is not overwritten unbacked.
- **`rofi/themes/screenshot/main.rasi` hardcoded `columns: 4`** with `lines: 1`,
  which would have wrapped the fifth menu entry out of view. Now `columns: 5`.

### Notes
Three findings from probing binaries rather than trusting their `--help`, all
recorded in the scripts themselves:
- **`checkupdates` exits 2 and `paru -Qua` exits 1** to mean "nothing found",
  so counting ignores exit status and counts lines. Gating on status would
  report zero forever while looking perfectly healthy — the failure mode is
  silence, which is why the suite pins all four status/output combinations.
- **`hyprshot -s` is a no-op in raw mode**: `save_geometry()` returns before
  `send_notification()` is reached. And `-r -s` parses only by accident —
  hyprshot's short spec declares `r:` as taking a required argument, so `getopt`
  binds `-s` as `-r`'s value. Reversing the two makes `getopt` fail, and
  hyprshot never checks its exit status, so it would write a file and pipe
  nothing. The script uses the unambiguous `--raw` and omits `-s`.
- **The updates click signals waybar from inside the launched command**, not
  after the terminal returns. `ghostty -e` does block (measured), but
  `options/terminal` is user-configurable and a single-instance terminal would
  return immediately, firing the refresh before the update began.

## [2026-08-02] - Host-Neutral Monitor Config

### Added
- **`scripts/doctor/checks/hardware.sh`** and
  **`scripts/doctor/test/test-hardware.sh`**: the sixth doctor module compares
  display outputs present in `/sys/class/drm` with connector names in tracked
  files, so it also works from a TTY with no compositor. It warns, rather than
  errors, for a possibly unplugged output and skips generated cache content
  behind tracked symlinks, Markdown, `docs/`, and `scripts/doctor/`. Its
  connector pattern includes repeated numeric suffixes for DisplayPort MST
  names such as `DP-1-1`.

### Changed
- **`hypr/config/hardware/monitor.conf`** now has one host-neutral
  `monitor=,highres@highrr,auto,1` rule instead of naming this desktop's
  output and carrying a `preferred` fallback.
- **`hypr/config/hardware/primary.conf` and `options/mainmonitor`** now ship
  empty: that means no monitor preference. `scripts/settings/settings.sh` and
  the Super+I panel still write a real connector name when the user selects
  one.
- **`wall.sh`, `restore-wallpaper.sh`, `update_sddm_root.sh`, and
  `watch_wallpaper.sh`** now branch explicitly on no preference; the three
  `eDP-1` guesses are gone.

### Fixed
- **`sddm/watch_wallpaper.sh` no longer dies silently** when `mainmonitor` is
  empty. Its inotify guard had compared every changed cache filename to the
  empty preference, so none could match and SDDM wallpaper sync stopped.

### Notes
- **`preferred` is not "the best mode"; it is the EDID preferred timing.** On
  this panel, applying the keywords and reading the resulting rate gave
  `preferred` → 2560x1440@59.951 and `highrr` → 2560x1440@143.998. The old
  catch-all was therefore a 60 Hz trap for a second monitor too.
- **`highrr` alone can trade resolution for refresh.** From an explicit
  1024x768@60, `highres@highrr` selected 2560x1440@143.998, proving it picks
  highest refresh at highest resolution. Do not reject the combined form with
  a binary strings search: the parser splits on `@`, so it contains no single
  `highres@highrr` literal.
- **hyprlock cannot be dry-run.** `hyprlock -c <file>` aborts at the Wayland
  connect in `hyprlock.cpp:63`, before parsing the config. Verify config
  changes with a real `hyprlock --grace 30` launch; the grace window lets any
  keypress dismiss the lock without a password. That is how `$monitor =` was
  confirmed to expand correctly.
- **The awww cache lookup is duplicated across three scripts on purpose.**
  `sddm/update_sddm_root.sh` runs as root against another user's home, and
  sourcing a helper from user-writable `~/.config/scripts/` would hand that
  user a root shell.
- **Animated awww wallpapers add a non-connector-named animation-frame file**
  beside per-output cache entries. With no preference the inotify guard lets
  it through, and `ls -t` can choose it first; `grep -oE '/.+$'` then fails to
  extract a path and the existing fallback catches it. Both paths degrade
  gracefully, and no animated wallpapers are in use here.
- **DRM sysfs has three connector states, not two.** Only `disconnected` is a
  definite absence; `unknown` is a driver that cannot hotplug-detect and is
  treated as present, so the check never claims an output is missing when it
  may be driving a display.
- **Collapsing `monitor.conf` exposed a removal-menu footgun.**
  `scripts/settings/advanced/monitor.sh` listed every `^monitor=` rule, so
  the catch-all became the only entry and the obvious choice wiped all monitor
  configuration. It now lists only output-naming rules (`^monitor=[^,]`) and
  explains when there are none.

## [2026-08-01] - Hardware Truth

### Added
- **`scripts/waybar/battery.sh`** + `custom/battery`: reports every battery on
  the machine by reading `/sys/class/power_supply` directly. waybar's own
  module counts only `SCOPE=System`, so this desktop logged `No batteries.`
  while a wireless mouse sat on the bus at 76%. `SCOPE` now selects behaviour
  instead of filtering — peripherals stay hidden until they drop below 25%, a
  system battery is always visible at every level.
- **`scripts/waybar/test-battery.sh`**: 33 fixture-driven assertions over a fake
  sysfs root (`BATTERY_SYSFS`), so the suite needs neither hardware nor root.

### Removed
- **waybar's built-in `battery` module**, its CSS, and `#battery.critical:not(.charging)`.
- **swaync's `backlight` widget.** `/sys/class/backlight` is empty; swaync was
  dropping the widget silently, so removing it changed nothing on screen.
- **Both `XF86MonBrightness*` keybinds.** `brightnessctl`'s only devices on this
  machine are the capslock, scrolllock and compose LEDs.

### Notes
- **A powered-off peripheral keeps its node and its last reading.** Switching
  the mouse off left `CAPACITY=75` in place; only `POWER_SUPPLY_ONLINE` flipped
  `1 → 0`. The scan skips present-and-`0`, not "not 1" — a laptop battery
  usually has no `ONLINE` attribute at all, since it lives on the Mains adapter.
- **Charge state is trusted for system batteries only.** The mouse reported
  `Discharging` and then `Unknown` minutes apart while sitting still. For a
  system battery `STATUS` is reliable, and charging suppresses the alert
  classes — what the deleted `:not(.charging)` rule encoded.
- **Two system batteries used to mask each other**, found in code review and
  fixed before release: the scan overwrote rather than accumulated, so a
  ThinkPad-style dual-battery machine would have shown the healthier one and
  reported `ok` while the other sat at 5%. System batteries now accumulate and
  the class takes the minimum across discharging ones.
- **swaync cannot host a live readout.** Its only text widget, `label`, takes a
  static string from `config.json`; there is no command-execution widget in
  0.12.6. That is why this lives on the bar and not in the sidebar.
- `bluetooth` and `battery` became self-contained 15px groups. A module that
  hides itself cannot be load-bearing for a gap — verified by screenshot: every
  module after it holds its exact x-position whether it shows or hides.

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
