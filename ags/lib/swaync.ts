import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

const CONFIG_PATH = GLib.get_home_dir() + "/.config/swaync/config.json"

export function readConfig(): Record<string, any> {
    try {
        const [ok, contents] = GLib.file_get_contents(CONFIG_PATH)
        if (!ok || !contents) return {}
        return JSON.parse(new TextDecoder().decode(contents))
    } catch (e) {
        console.error("Failed to read swaync config:", e)
        return {}
    }
}

export function writeConfig(config: Record<string, any>): void {
    try {
        const file = Gio.File.new_for_path(CONFIG_PATH)
        const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null)
        const bytes = new TextEncoder().encode(JSON.stringify(config, null, 2) + "\n")
        stream.write_bytes(new GLib.Bytes(bytes), null)
        stream.close(null)
    } catch (e) {
        console.error("Failed to write swaync config:", e)
    }
}

export function updateAndReload(key: string, value: any): void {
    const config = readConfig()
    config[key] = value
    writeConfig(config)
    execAsync(["swaync-client", "-rs"]).catch(console.error)
}
