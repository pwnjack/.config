# Quick Start Guide

## First Time Setup

```bash
# 1. Clone your dotfiles (if on a new machine)
git clone <your-repo> ~/.config

# 2. Run installation
cd ~/.config
./install.sh

# 3. Set colors with pywal
wal -i ~/Pictures/Wallpapers/wall1.jpg

# 4. Reload Hyprland
# Press SUPER+SHIFT+R or log out/in
```

## Essential Commands

### Window Manager
- `SUPER + ENTER` - Open terminal (Ghostty)
- `SUPER + Q` - Close window
- `SUPER + SPACE` - App launcher
- `SUPER + L` - Lock screen
- `SUPER + F` - Fullscreen
- `SUPER + V` - Toggle float
- `SUPER + SHIFT + L` - Power menu

### UI & Notifications
- `SUPER + H` - Keybinds cheatsheet
- `SUPER + SHIFT + B` - Toggle Waybar

### Workspaces
- `SUPER + [1-9]` - Switch workspace
- `SUPER + SHIFT + [1-9]` - Move window to workspace
- `SUPER + Mouse Scroll` - Cycle workspaces

### Color Scheme
```bash
# Change colors with pywal
wal -i /path/to/wallpaper.jpg

# Or use waypaper GUI
waypaper
```

### Configuration Files

| Component | Location |
|-----------|----------|
| Hyprland | `~/.config/hypr/hyprland.conf` |
| Waybar | `~/.config/waybar/config.jsonc` |
| Terminal | `~/.config/ghostty/config` |
| Shell | `~/.config/fish/config.fish` |
| Editor | `~/.config/nvim/` |
| Keybinds | `~/.config/hypr/config/software/keybinds.conf` |

### Quick Edits

```bash
# Change default browser
echo "firefox" > ~/.config/options/browser

# Change default terminal
echo "kitty" > ~/.config/options/terminal

# Change primary monitor
echo "HDMI-A-1" > ~/.config/options/mainmonitor

# Edit keybindings
nvim ~/.config/hypr/config/software/keybinds.conf
```

## Troubleshooting

### Reload Everything
```bash
# Reload Hyprland config
hyprctl reload

# Or press: SUPER + SHIFT + R

# Restart waybar
killall waybar && waybar &

# Restart notifications
killall swaync && swaync &
```

### Check Logs
```bash
# Hyprland log
cat /tmp/hypr/$(/usr/bin/ls -t /tmp/hypr | head -n 1)/hyprland.log

# Systemd user services
systemctl --user status hypridle
```

### Broken Colors
```bash
# Regenerate pywal colors
wal -i ~/Pictures/Wallpapers/wall1.jpg

# Recreate symlink
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf

# Reload Hyprland
hyprctl reload
```

## Daily Workflow

### Screenshots
- `SUPER + PRINT` - Area selection
- `SUPER + SHIFT + PRINT` - Full screen

### Media Controls
- `Media keys` - Play/pause, next, previous
- `playerctl` CLI - Control from terminal

### Clipboard
```bash
# View clipboard history
cliphist list | rofi -dmenu | cliphist decode | wl-copy

# Or use keybind (check keybinds.conf)
```

## Customization

### Add Startup Applications
Edit: `~/.config/hypr/config/setup/autostart.conf`
```
exec-once = your-app
```

### Window Rules
Edit: `~/.config/hypr/config/software/rules.conf`
```
windowrulev2 = float, class:^(your-app)$
```

### Waybar Modules
Edit: `~/.config/waybar/config.jsonc`

### Themes
```bash
# Available themes are in hypr/themes/
# Switch by sourcing different theme files
```

## Backup & Restore

### Manual Backup
```bash
# Backup current config
cp -r ~/.config/hypr ~/hypr-backup-$(date +%Y%m%d)

# Restore
cp -r ~/hypr-backup-DATE ~/.config/hypr
```

### Git Management
```bash
# Commit your changes
cd ~/.config
git add .
git commit -m "Updated keybindings"
git push

# Update from repo
git pull
```

## Getting Help

1. Check `README.md` for full documentation
2. Hyprland Wiki: https://wiki.hyprland.org
3. Check logs in `/tmp/hypr/`
4. Run install script with `--dry-run` to diagnose

---

**Tip**: Bookmark this file for quick reference!
