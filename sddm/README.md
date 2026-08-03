# SDDM Wallpaper Sync

Scripts that keep the SDDM login screen background in sync with your desktop wallpaper.

## Files

| File | Purpose |
|------|---------|
| `watch_wallpaper.sh` | Watches for awww wallpaper changes (started via Hyprland autostart) |
| `update_sddm.sh` | User-side updater; delegates to the installed root-owned helper via sudo |
| `update_sddm_root.sh` | Tracked source for the privileged helper; converts the wallpaper into the SDDM theme background |
| `setup-sudo.sh` | Installs or upgrades the root-owned helper and its passwordless-sudo rule |
| `default.conf` | Reference SDDM configuration (copy to `/etc/sddm.conf` if desired) |

## Setup

### 1. Configure passwordless sudo (required for automatic sync)

```bash
~/.config/sddm/setup-sudo.sh
```

This installs `sddm-wallpaper-update` as a root-owned, mode-0755 helper in
`/usr/local/bin`, then installs a sudoers drop-in allowing your user to run that
helper as root without a password only when its sole argument is your exact
username. Re-run the setup command after changing `update_sddm_root.sh`; it
upgrades the installed copy when the tracked source has changed.

The automatic passwordless path closes one specific escalation path: it runs
the root-owned installed copy, not a user-writable script in `$HOME`. The manual
installation path does not close that boundary. `setup-sudo.sh` installs from
`$SCRIPT_DIR/update_sddm_root.sh`, which is user-writable here, so anything able
to change that source gains root execution the next time the user runs setup.

On this host the SDDM theme directory is also user-owned. Until its ownership
is corrected, the passwordless grant remains a root-write primitive because
the helper writes `Backgrounds/wallpaper.jpg` as root beneath a directory the
user controls. The helper also passes a user-selected wallpaper to ffmpeg while
running as root.

### 2. Test it

```bash
~/.config/sddm/update_sddm.sh
```

Run `~/.config/doctor.sh` at any time to check the effective sudo grant, helper
installation and drift, theme-directory ownership, ffmpeg, watcher process,
and whether the greeter image is older than the newest awww cache trigger.

## How It Works

1. **On wallpaper change**: `watch_wallpaper.sh` (started via Hyprland autostart)
   notices the awww cache update and runs `update_sddm.sh`.
2. **Wallpaper detection**: the updater reads the awww cache
   (`~/.cache/awww/<version>/<monitor>`), falling back to the
   `~/.config/options/wallpaper` symlink.
3. **Conversion**: `ffmpeg` writes the image to
   `/usr/share/sddm/themes/<theme>/Backgrounds/wallpaper.jpg` for the theme
   configured in `/etc/sddm.conf` (default: `sddm-astronaut-theme`).

## Troubleshooting

- **Wallpaper not updating**: run `~/.config/doctor.sh`; then apply its setup or watcher fix
- **ffmpeg not found**: install it with `sudo pacman -S ffmpeg`
- **Wrong theme updated**: check the `Current=` value under `[Theme]` in `/etc/sddm.conf`
