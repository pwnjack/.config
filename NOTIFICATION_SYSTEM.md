# Notification System - Mako (CachyOS Default)

## Configuration

Your system uses **Mako** as the notification daemon, which is the CachyOS default and required by `cachyos-hyprland-settings`.

### Why Mako?

- ✅ **System requirement** - Required by CachyOS Hyprland settings
- ✅ **Lightweight** - Minimal resource usage
- ✅ **Simple** - Clean toast-style notifications
- ✅ **Integrated** - Works seamlessly with CachyOS

### SwayNC Removed

SwayNC was removed because:
- Conflicts with mako (can't run both)
- Breaking CachyOS system dependencies is risky
- The sidebar UI didn't meet your preferences

## Mako Features

### Configuration Location
`~/.config/mako/config`

### Available Commands

```bash
# Dismiss last notification
makoctl dismiss

# Dismiss all notifications
makoctl dismiss --all

# Restore last dismissed notification
makoctl restore

# List current notifications
makoctl list

# Invoke default action on last notification
makoctl invoke

# Reload mako configuration
makoctl reload
```

### Styling Notifications

Mako uses a simple config file format. Example:

```ini
# ~/.config/mako/config

# Appearance
font=JetBrains Mono 11
background-color=#2e3440
text-color=#d8dee9
border-color=#88c0d0
border-size=2
border-radius=10

# Behavior
default-timeout=5000
ignore-timeout=0

# Position
anchor=top-right
margin=10
```

### Adding Keybinds (Optional)

You can add keybinds for mako controls in `hypr/config/software/keybinds.conf`:

```conf
# Notification controls
bind = $Mod SHIFT, N, exec, makoctl dismiss          # Dismiss last
bind = $Mod SHIFT, D, exec, makoctl dismiss --all    # Dismiss all
bind = $Mod SHIFT, R, exec, makoctl restore          # Restore last
```

## Current Setup

**Autostart:** `exec-once = mako` in [autostart.conf](hypr/config/setup/autostart.conf#L3)

**Status:** ✅ Mako is running and handling notifications

**Waybar:** Notification module removed (was SwayNC-specific)

## Alternative: Dunst

If you want a different notification daemon with more features:

1. Install: `sudo pacman -S dunst`
2. Replace in autostart: `exec-once = dunst`
3. Configure: `~/.config/dunst/dunstrc`

Dunst features:
- History viewer (dunstctl history)
- More theming options
- Action buttons in notifications
- Context menu

**Note:** May conflict with CachyOS settings package requirements.

## Notifications Work Automatically

Applications send notifications via D-Bus, and mako displays them as toast pop-ups in the corner of your screen. No manual action needed!

Examples:
- Volume changes (swayosd)
- Brightness changes (swayosd)
- Application notifications (Discord, Spotify, etc.)
- System notifications

---

**Current System:** Mako (CachyOS default) ✅
**Status:** Working correctly
**No sidebar:** Toast notifications only (by design)

## ✨ Pywal Color Integration - ADDED!

### Automatic Theming

Mako notifications now automatically match your wallpaper colors!

**How it works:**
1. Change your wallpaper (waypaper, wall.sh, etc.)
2. Pywal extracts colors from the image
3. Mako config regenerates with matching colors
4. Notifications seamlessly match your theme

**Updated on every wallpaper change:**
- Background color (with transparency)
- Text color  
- Border colors (normal, low, critical)
- App-specific accent colors

**Script:** `~/.config/mako/apply_wal_colors.sh`
**Called by:** `~/.config/scripts/hyprland/wall.sh`

See [mako/README.md](mako/README.md) for full details and customization options.

### Test It

```bash
# Change wallpaper
waypaper

# Send test notification
notify-send "Theme Test" "Mako colors match your wallpaper!"
```

Your notifications will now have beautiful, automatically-matched colors! 🎨
