# SDDM Wallpaper Sync

Scripts that keep the SDDM login screen background in sync with your desktop wallpaper.

## Files

| File | Purpose |
|------|---------|
| `watch_wallpaper.sh` | Watches for awww wallpaper changes (started via Hyprland autostart) |
| `update_sddm.sh` | User-side updater; delegates to the root script via sudo |
| `update_sddm_root.sh` | Root-side updater; converts the wallpaper into the SDDM theme background |
| `setup-sudo.sh` | One-time setup: grants passwordless sudo for `update_sddm_root.sh` only |
| `default.conf` | Reference SDDM configuration (copy to `/etc/sddm.conf` if desired) |

## Setup

### 1. Configure passwordless sudo (required for automatic sync)

```bash
~/.config/sddm/setup-sudo.sh
```

This installs `/etc/sudoers.d/sddm-wallpaper` allowing your user to run
`update_sddm_root.sh` as root without a password — nothing else.

> Security note: whatever can write to `~/.config/sddm/update_sddm_root.sh`
> effectively gains root access. Keep your home directory permissions sane.

### 2. Test it

```bash
~/.config/sddm/update_sddm.sh
```

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

- **Wallpaper not updating**: make sure passwordless sudo is configured (`setup-sudo.sh`)
- **ffmpeg not found**: install it with `sudo pacman -S ffmpeg`
- **Wrong theme updated**: check the `Current=` value under `[Theme]` in `/etc/sddm.conf`
