# SDDM Wallpaper Sync Setup

This directory contains scripts to automatically sync your desktop wallpaper to the SDDM login screen.

## Setup Instructions

### 1. Configure Passwordless Sudo (Required)

The wallpaper update script needs sudo access to write to `/usr/share/sddm/themes/`. You need to configure passwordless sudo for the specific commands.

**Option A: Install the provided sudoers file (Recommended)**
```bash
sudo cp /home/pwnjack/.config/sddm/sddm-wallpaper-sudoers /etc/sudoers.d/sddm-wallpaper
sudo visudo -c  # Verify the syntax is correct
```

**Option B: Manual configuration**
Add these lines to `/etc/sudoers.d/sddm-wallpaper` (create the file if it doesn't exist):
```
pwnjack ALL=(ALL) NOPASSWD: /usr/bin/ffmpeg
pwnjack ALL=(ALL) NOPASSWD: /bin/rm -f /usr/share/sddm/themes/win11-sddm-theme/Backgrounds/wallpaper.jpg
pwnjack ALL=(ALL) NOPASSWD: /bin/rm -f /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/wallpaper.jpg
```

### 2. Verify Systemd Services

The systemd services should already be enabled. To verify:
```bash
systemctl --user status sddm-wallpaper.service
systemctl --user status sddm-wallpaper-shutdown.service
```

If they're not enabled, enable them:
```bash
systemctl --user enable sddm-wallpaper.service sddm-wallpaper-shutdown.service
systemctl --user start sddm-wallpaper.service
```

### 3. Test the Script

Test the update script manually:
```bash
/home/pwnjack/.config/sddm/update_sddm.sh
```

## How It Works

1. **On Session Start**: The `sddm-wallpaper.service` runs when your user session starts and updates the SDDM wallpaper immediately.

2. **On Wallpaper Change**: The `watch_wallpaper.sh` script (started via Hyprland autostart) watches for wallpaper changes and updates SDDM automatically.

3. **On Shutdown**: The `sddm-wallpaper-shutdown.service` runs before shutdown/reboot to ensure the wallpaper is updated for the next boot.

4. **Fallback**: The update script tries multiple sources:
   - First checks the swww cache file (`~/.cache/swww/$monitor`)
   - If not found, queries swww directly

## Troubleshooting

- **Wallpaper not updating on reboot**: Make sure passwordless sudo is configured correctly
- **Script fails silently**: Check logs with `journalctl --user -u sddm-wallpaper.service`
- **ffmpeg not found**: Install it with `sudo pacman -S ffmpeg`

