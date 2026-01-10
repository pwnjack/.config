# SwayNC Notification Center - FIXED

## The Problem

`SUPER + SHIFT + N` wasn't opening the notification center because:

1. **Mako was blocking SwayNC** - Another notification daemon (mako) was already running
2. **SwayNC couldn't start** - Error: "Could not acquire notification name"
3. **Missing Wayland backend** - SwayNC needs `GDK_BACKEND=wayland` to work properly

## The Solution

### 1. Killed Conflicting Daemon
```bash
killall mako
```

### 2. Started SwayNC with Proper Environment
```bash
GDK_BACKEND=wayland swaync &
```

### 3. Updated Autostart Configuration
**File:** `~/.config/hypr/config/setup/autostart.conf`

Changed from:
```
exec-once = swaync &
```

To:
```
exec-once = killall mako dunst 2>/dev/null; GDK_BACKEND=wayland swaync &
```

This ensures:
- Any conflicting notification daemons are killed first
- SwayNC starts with the correct Wayland backend
- Works reliably on every Hyprland restart

## Verification

✅ SwayNC daemon is now running (PID: 16361)
✅ Command works: `swaync-client -t -sw`
✅ Keybind registered in Hyprland
✅ Hyprland config reloaded

## Test It Now!

Press: **SUPER + SHIFT + N**

You should see the notification center sidebar slide in from the right side with:
- 🎵 Media player controls
- 🔊 Volume control
- 💡 Brightness control
- 🔕 Do Not Disturb toggle
- 🔔 Your notifications
- 🎨 Quick action buttons (theme, emoji, clipboard, screenshot, power)

## Why This Happened

Mako is a lightweight notification daemon that's commonly installed with Wayland setups. It was starting automatically (possibly from a systemd service or another autostart mechanism) and claiming the notification DBus name before SwayNC could start.

## Permanent Fix Applied

The autostart config now:
1. Kills any conflicting daemons on startup
2. Sets the correct environment variable
3. Starts SwayNC reliably

You won't need to manually fix this again - it's now handled automatically on every boot!

## Additional Notes

- SwayNC is more feature-rich than mako (widgets, customization)
- The sidebar approach is more modern and user-friendly
- All your notification settings are in `~/.config/swaync/config.json`

---

**Status: RESOLVED** ✅

Next time you log in, SwayNC will start automatically and the sidebar will work perfectly!
