# Hyprland Dotfiles

A clean, self-contained Hyprland configuration for CachyOS/Arch Linux with dynamic theming via pywal.

## Features

- **Window Manager**: Hyprland with carefully tuned animations and blur effects
- **Status Bar**: Waybar with weather integration, media controls, and system stats
- **Terminal**: Ghostty (primary) with kitty fallback
- **Shell**: Fish with zoxide and starship prompt
- **Browser**: Zen Browser
- **File Manager**: Thunar (GUI), Yazi (TUI)
- **Editor**: Neovim
- **Launcher**: Rofi
- **Notifications**: SwayNC
- **Lock Screen**: Hyprlock with fingerprint support
- **Idle Management**: Hypridle
- **Color Scheme**: Pywal dynamic theming
- **Media**: Playerctl integration for media controls

## Directory Structure

```
~/.config/
├── hypr/                    # Hyprland configuration
│   ├── hyprland.conf       # Main config manifest
│   ├── hyprlock.conf       # Lock screen config
│   ├── hypridle.conf       # Idle/power management
│   └── config/             # Modular config files
│       ├── apptype.conf    # Default applications
│       ├── colors.conf     # Pywal symlink
│       ├── cursortheme.conf
│       ├── hardware/       # Monitor, input devices
│       ├── looks/          # Animations, decorations
│       ├── setup/          # Environment, autostart
│       └── software/       # Keybinds, rules, general
├── scripts/                # Custom scripts
│   ├── hyprland/          # Hyprland-specific scripts
│   ├── settings/          # Settings management
│   ├── themes/            # Theme switchers
│   ├── waybar/            # Waybar utilities
│   └── fonts/             # Font management
├── wallpapers/            # Wallpaper collection
├── options/               # User preferences (text files)
│   ├── browser           # Default browser
│   ├── terminal          # Default terminal
│   ├── mainmonitor       # Primary monitor
│   └── ...
├── waybar/               # Waybar configuration
├── fish/                 # Fish shell config
├── ghostty/              # Ghostty terminal config
├── nvim/                 # Neovim configuration
├── rofi/                 # Rofi launcher config
├── swaync/               # Notification center
├── btop/                 # System monitor
├── fastfetch/            # System info tool
└── mimeapps.list         # Default applications
```

## Installation

### Fresh Install

1. Clone this repository:
```bash
git clone <your-repo-url> ~/.config
cd ~/.config
```

2. Run the installation script:
```bash
./install.sh
```

The script will:
- Check and install required packages
- Create necessary directories
- Set up pywal integration
- Copy wallpapers
- Configure symlinks
- Backup existing configs

### Manual Installation

If you prefer manual setup:

1. Install required packages:
```bash
# Essential packages
sudo pacman -S hyprland hyprlock hypridle waybar swaync swayosd swww \
               rofi-wayland wofi wlogout ghostty kitty fish neovim \
               thunar yazi btop fastfetch flameshot playerctl \
               cliphist wl-clipboard python-pywal qt5ct qt6ct \
               nwg-look hyprpolkitagent

# AUR packages (using paru/yay)
paru -S zen-browser-bin vesktop waybar-weather
```

2. Initialize pywal:
```bash
mkdir -p ~/.cache/wal
wal -i ~/Pictures/Wallpapers/wall1.jpg -n
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf
```

3. Set fish as default shell (optional):
```bash
chsh -s $(which fish)
```

4. Log out and select Hyprland from your login manager

## Configuration

### Pywal Color Scheme

This setup uses pywal for dynamic color theming. To change the color scheme:

```bash
wal -i /path/to/wallpaper.jpg
```

This will automatically update:
- Hyprland colors
- Terminal colors
- Waybar theme
- Rofi colors

The Hyprland color config is symlinked to `~/.cache/wal/colors-hyprland.conf`.

### User Preferences

Simple text files in `~/.config/options/` control application defaults:

- `browser` - Default web browser
- `terminal` - Default terminal emulator
- `mainmonitor` - Primary monitor identifier
- `player` - Media player for controls
- `mediaicon` - Icon for media display

Edit these files to change preferences without touching config files.

### Monitor Configuration

Edit `~/.config/hypr/config/hardware/monitor.conf` for your monitor setup.

Current primary monitor is set in:
- `~/.config/hypr/config/hardware/primary.conf`
- `~/.config/options/mainmonitor`

### Keybindings

Default keybindings (see `hypr/config/software/keybinds.conf` for full list):

| Key Combo | Action |
|-----------|--------|
| `SUPER + ENTER` | Open terminal (ghostty) |
| `SUPER + Q` | Close window |
| `SUPER + D` | Application launcher (rofi) |
| `SUPER + E` | File manager (thunar) |
| `SUPER + L` | Lock screen |
| `SUPER + F` | Toggle fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + SHIFT + E` | Power menu |
| `SUPER + [1-9]` | Switch to workspace |
| `SUPER + SHIFT + [1-9]` | Move window to workspace |
| `SUPER + Mouse drag` | Move window |
| `SUPER + Mouse right drag` | Resize window |

### Adding Wallpapers

1. Place wallpapers in `~/.config/wallpapers/` or `~/Pictures/Wallpapers/`
2. Run: `wal -i /path/to/wallpaper.jpg`
3. Use waypaper or swww for wallpaper management

## Customization

### Animations

Edit `~/.config/hypr/config/looks/animations.conf` to adjust animation speeds and curves.

### Blur Effects

Blur settings are in `~/.config/hypr/config/looks/decor.conf`.

Layer rules for blur are in main `hyprland.conf`.

### Window Rules

Add custom window rules in `~/.config/hypr/config/software/rules.conf`.

Example:
```
windowrulev2 = float, class:^(calculator)$
windowrulev2 = size 400 300, class:^(calculator)$
```

## Scripts

### Hyprland Scripts

- `mediaexec.sh` - Display current media on lock screen
- `startup.sh` - Handle conditional startup actions
- `wall.sh` - Wallpaper management

### Maintenance

Keep scripts executable:
```bash
find ~/.config/scripts -type f -name "*.sh" -exec chmod +x {} \;
```

## Troubleshooting

### Colors not updating after wal

Reload Hyprland: `SUPER + SHIFT + R`

### Pywal symlink broken

Recreate symlink:
```bash
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf
```

### Missing packages

Run the install script with `--dry-run` to see what's missing:
```bash
./install.sh --dry-run
```

### Lock screen not working

Check hypridle status:
```bash
systemctl --user status hypridle
```

Restart hypridle:
```bash
killall hypridle && hypridle &
```

### Waybar not showing weather

Check if waybar-weather is installed:
```bash
which waybar-weather
```

The weather module uses a wrapper script at `~/.config/waybar/waybar-weather-wrapper.sh`.

## Dependencies

### Essential Packages

Core window manager and utilities:
- hyprland, hyprlock, hypridle
- waybar, swaync, swayosd
- swww (wallpaper daemon)
- rofi-wayland, wofi, wlogout
- hyprpolkitagent

Applications:
- ghostty, kitty (terminals)
- fish (shell)
- neovim (editor)
- thunar, yazi (file managers)

System utilities:
- btop, fastfetch
- playerctl, cliphist, wl-clipboard
- python-pywal

Theming:
- qt5ct, qt6ct, nwg-look

### AUR Packages

- zen-browser-bin
- vesktop
- waybar-weather

## Backups

The install script creates backups at:
```
~/.config-backup-YYYYMMDD-HHMMSS/
```

To restore from backup:
```bash
cp -r ~/.config-backup-*/hypr ~/.config/
```

## Credits

- Original template by @GeodeArc
- Hyprland: https://hyprland.org
- Pywal: https://github.com/dylanaraps/pywal
- CachyOS: https://cachyos.org

## License

Feel free to use, modify, and share these dotfiles.

## Support

For Hyprland issues: https://wiki.hyprland.org
For these dotfiles: Open an issue in your repository
