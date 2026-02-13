import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

const CONFIG_PATH = GLib.get_home_dir() + "/.config/hypr/hypridle.conf"

interface HypridleTimeouts {
    lock: number
    dpms: number
}

export function readTimeouts(): HypridleTimeouts {
    try {
        const [ok, contents] = GLib.file_get_contents(CONFIG_PATH)
        if (!ok || !contents) return { lock: 180, dpms: 600 }
        const text = new TextDecoder().decode(contents)

        const listeners = text.split("listener {")
        let lock = 180
        let dpms = 600

        for (const block of listeners) {
            const timeoutMatch = block.match(/timeout\s*=\s*(\d+)/)
            if (!timeoutMatch) continue
            const timeout = parseInt(timeoutMatch[1])
            if (block.includes("hyprlock")) lock = timeout
            if (block.includes("dpms off")) dpms = timeout
        }

        return { lock, dpms }
    } catch (e) {
        console.error("Failed to read hypridle config:", e)
        return { lock: 180, dpms: 600 }
    }
}

export function writeTimeouts(timeouts: HypridleTimeouts): void {
    const config = `#
# Hypridle Configuration
# Manages screen locking and power management based on inactivity
#
# Reference: https://wiki.hyprland.org/Hypr-Ecosystem/hypridle/
#

general {
    lock_cmd = pidof hyprlock || hyprlock       # Avoid starting multiple hyprlock instances
    before_sleep_cmd = loginctl lock-session    # Lock before system suspend
    after_sleep_cmd = hyprctl dispatch dpms on  # Turn on display after wake
    ignore_dbus_inhibit = false                 # Respect inhibit requests (e.g., video playback)
}

# Lock screen after inactivity
listener {
    timeout = ${timeouts.lock}
    on-timeout = hyprlock
    on-resume = echo "Unlocked"
}

# Turn off monitor after inactivity
listener {
    timeout = ${timeouts.dpms}
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}
`
    try {
        const file = Gio.File.new_for_path(CONFIG_PATH)
        const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null)
        const bytes = new TextEncoder().encode(config)
        stream.write_bytes(new GLib.Bytes(bytes), null)
        stream.close(null)
        // Restart hypridle to apply
        execAsync(["bash", "-c", "killall hypridle 2>/dev/null; hypridle &"]).catch(console.error)
    } catch (e) {
        console.error("Failed to write hypridle config:", e)
    }
}
