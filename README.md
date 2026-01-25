# Hyprland Dotfiles

A clean, modern Hyprland configuration for CachyOS/Arch Linux with dynamic theming via pywal.

## Overview

This is a streamlined, production-ready Hyprland setup focused on aesthetics and usability. The configuration uses a modern dark theme with rounded corners, blur effects, and dynamic colors generated from your wallpaper.

### Features

- **Window Manager**: Hyprland with smooth animations and blur effects
- **Status Bar**: Waybar with weather, media controls, and system monitoring
- **Terminal**: Ghostty (primary), kitty (fallback)
- **Shell**: Fish with zoxide and starship prompt
- **Launcher**: Rofi with modern styling
- **Notifications**: SwayNC control center
- **Lock Screen**: Hyprlock with fingerprint support
- **Color Scheme**: Pywal dynamic theming from wallpaper

## Directory Structure

```
~/.config/
├── hypr/                       # Hyprland configuration
│   ├── hyprland.conf          # Main config manifest
│   ├── hyprlock.conf          # Lock screen
│   ├── hypridle.conf          # Idle management
│   └── config/                # Modular configuration
│       ├── colors.conf        # Pywal colors (symlink)
│       ├── apptype.conf       # Default applications
│       ├── cursortheme.conf   # Cursor theme
│       ├── hardware/          # Monitor and input settings
│       │   ├── monitor.conf
│       │   └── input.conf
│       ├── looks/             # Visual appearance
│       │   ├── decor.conf     # Borders, rounding, blur
│       │   └── animations.conf
│       ├── setup/             # Environment and startup
│       │   ├── envvars.conf
│       │   └── autostart.conf
│       └── software/          # Behavior and keybindings
│           ├── general.conf
│           ├── keybinds.conf
│           └── rules.conf
├── waybar/                    # Status bar
│   ├── config.jsonc           # Waybar modules
│   ├── style.css              # Waybar styling
│   └── colors.css             # Pywal color definitions
├── rofi/                      # Application launcher
│   ├── config.rasi            # Main rofi config
│   ├── launcher.sh            # App launcher script
│   ├── powermenu.sh           # Power menu script
│   ├── screenshot.sh          # Screenshot menu
│   ├── keybinds-cheatsheet.sh # Keybinds reference
│   ├── options/               # Rofi settings
│   │   ├── colors.rasi
│   │   ├── font.rasi
│   │   └── wallpaper.rasi
│   └── themes/                # Rofi theme files
│       ├── launcher/
│       ├── powermenu/
│       ├── screenshot/
│       ├── keybinds/
│       └── mode/
├── swaync/                    # Notification center
│   ├── config.json
│   ├── style.css
│   ├── notifications.css
│   ├── central_control.css
│   └── scripts/
├── options/                   # User preferences
│   ├── browser               # Default browser
│   ├── terminal              # Default terminal
│   ├── mainmonitor           # Primary display
│   ├── launchertype          # Rofi layout (vertical/horizontal)
│   └── ...
├── scripts/                   # Utility scripts
│   ├── hyprland/
│   ├── waybar/
│   └── settings/
├── fish/                      # Fish shell config
├── ghostty/                   # Ghostty terminal
├── kitty/                     # Kitty terminal (fallback)
├── nvim/                      # Neovim configuration
└── btop/                      # System monitor
```

## Keybindings

### Applications

| Shortcut | Action |
|----------|--------|
| `Super + Enter` | Terminal (Ghostty) |
| `Super + E` | File Manager (Thunar) |
| `Super + N` | Neovim (TUI) |
| `Super + T` | KWrite (GUI editor) |
| `Super + B` | Web Browser (Zen) |
| `Super + G` | Zed Editor |
| `Super + S` | Screenshot (region) |
| `Super + K` | Calculator |
| `Super + A` | AI Assistant |

### Window Management

| Shortcut | Action |
|----------|--------|
| `Super + Q` | Close window |
| `Super + W` | Close window (alt) |
| `Super + Shift + Q` | Exit Hyprland |
| `Super + V` | Toggle floating |
| `Super + F` | Toggle fullscreen |
| `Super + Shift + F` | Fullscreen (no gaps) |
| `Super + O` | Toggle split |
| `Super + P` | Pseudo tiling |
| `Super + Shift + V` | Pin window (PiP) |
| `Super + L` | Lock screen |

### Rofi Menus

| Shortcut | Action |
|----------|--------|
| `Super + Space` | Application launcher |
| `Super + Shift + L` | Power menu |
| `Super + Shift + S` | Screenshot menu |
| `Super + C` | Clipboard history |
| `Super + .` | Emoji picker |
| `Super + H` | Keybinds cheatsheet |

### Workspaces

| Shortcut | Action |
|----------|--------|
| `Super + 1-9,0` | Switch to workspace |
| `Super + Shift + 1-9,0` | Move window to workspace |
| `Super + Left/Right` | Previous/Next workspace |
| `Super + Shift + Left/Right` | Move window & follow |
| `Super + Tab` | Cycle windows |

### Window Navigation

| Shortcut | Action |
|----------|--------|
| `Alt + Arrows` | Move focus |
| `Alt + Ctrl + Arrows` | Resize window |
| `Alt + Shift + Arrows` | Move window |
| `Super + Mouse Drag` | Move window |
| `Super + Right-click Drag` | Resize window |

### Waybar

| Shortcut | Action |
|----------|--------|
| `Super + Shift + B` | Toggle Waybar |
| `Super + Alt + B` | Hide Waybar |
| `Super + Ctrl + B` | Waybar options |

### Utilities

| Shortcut | Action |
|----------|--------|
| `Super + I` | Settings menu |
| `Super + Shift + W` | Random wallpaper |
| `Super + Ctrl + W` | Waypaper GUI |
| `Ctrl + Shift + Esc` | System monitor |

## Installation

### Prerequisites

```bash
# Core packages
sudo pacman -S hyprland hyprlock hypridle waybar swaync swww \
               rofi-wayland ghostty kitty fish neovim \
               thunar yazi btop fastfetch playerctl \
               cliphist wl-clipboard python-pywal \
               qt5ct qt6ct nwg-look

# AUR packages
paru -S zen-browser-bin waybar-weather hyprshot
```

### Setup

1. Clone or copy configuration:
```bash
git clone <repo-url> ~/.config
```

2. Initialize pywal:
```bash
wal -i ~/Pictures/Wallpapers/your-wallpaper.jpg -n
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf
```

3. Set fish as default shell (optional):
```bash
chsh -s $(which fish)
```

4. Log out and select Hyprland from your login manager.

## Customization

### Pywal Colors

Colors are dynamically generated from your wallpaper:

```bash
wal -i /path/to/wallpaper.jpg
```

This updates colors across:
- Hyprland (borders, accents)
- Waybar
- Rofi
- SwayNC notifications

### User Preferences

Edit text files in `~/.config/options/`:

| File | Purpose | Example |
|------|---------|---------|
| `browser` | Default browser | `zen-browser` |
| `terminal` | Default terminal | `ghostty` |
| `mainmonitor` | Primary display | `DP-1` |
| `launchertype` | Rofi layout | `vertical` |

### Visual Appearance

- **Blur & Rounding**: `~/.config/hypr/config/looks/decor.conf`
- **Animations**: `~/.config/hypr/config/looks/animations.conf`
- **Window Rules**: `~/.config/hypr/config/software/rules.conf`

### Monitor Setup

Edit `~/.config/hypr/config/hardware/monitor.conf` for display configuration.

## Troubleshooting

### Colors not updating

Reload Hyprland after running wal:
```bash
hyprctl reload
```

### Pywal symlink broken

Recreate the symlink:
```bash
ln -sf ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/config/colors.conf
```

### Waybar not starting

Check for errors:
```bash
waybar &
```

Restart waybar:
```bash
killall waybar && waybar &
```

### Lock screen issues

Restart hypridle:
```bash
killall hypridle && hypridle &
```

## Dependencies

### Core

- hyprland, hyprlock, hypridle
- waybar, swaync
- swww (wallpaper daemon)
- rofi-wayland
- python-pywal

### Applications

- ghostty, kitty
- fish, neovim
- thunar, yazi
- btop, fastfetch

### Utilities

- playerctl, cliphist, wl-clipboard
- hyprshot, brightnessctl
- qt5ct, qt6ct, nwg-look

## Credits

- Hyprland: https://hyprland.org
- Pywal: https://github.com/dylanaraps/pywal
- Rofi themes adapted from: @adi1090x
- SwayNC theme based on: HyprNova

## License

MIT - Feel free to use, modify, and share.
