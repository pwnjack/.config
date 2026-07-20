import GLib from "gi://GLib"
import Gio from "gi://Gio"

export interface MonitorInfo {
    name: string; model: string
    width: number; height: number; refreshRate: number
    scale: number; x: number; y: number; focused: boolean
}

export function listMonitors(): MonitorInfo[] {
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl monitors -j")
        if (!ok || !stdout) return []
        const raw = JSON.parse(new TextDecoder().decode(stdout))
        return raw.map((m: any) => ({
            name: m.name, model: m.model || "unknown",
            width: m.width, height: m.height, refreshRate: m.refreshRate,
            scale: m.scale, x: m.x, y: m.y, focused: m.focused,
        }))
    } catch (e) {
        console.error("listMonitors failed:", e)
        return []
    }
}

const MAIN_PATH = GLib.get_home_dir() + "/.config/options/mainmonitor"
const PRIMARY_CONF = GLib.get_home_dir() + "/.config/hypr/config/hardware/primary.conf"

export function getMainMonitor(): string {
    try {
        const [ok, c] = GLib.file_get_contents(MAIN_PATH)
        return ok && c ? new TextDecoder().decode(c).trim() : ""
    } catch { return "" }
}

/** Mirrors scripts/settings/settings.sh monitorselect(). */
export function setMainMonitor(name: string): void {
    const write = (path: string, text: string) => {
        try {
            Gio.File.new_for_path(path).replace_contents(
                new TextEncoder().encode(text), null, false, Gio.FileCreateFlags.NONE, null)
        } catch (e) { console.error(`write ${path} failed:`, e) }
    }
    write(MAIN_PATH, name + "\n")
    write(PRIMARY_CONF, `$monitor = ${name}\n`)
}
