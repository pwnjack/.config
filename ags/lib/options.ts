import GLib from "gi://GLib"
import Gio from "gi://Gio"

const OPTIONS_DIR = GLib.get_home_dir() + "/.config/options"

export function readOption(name: string): string {
    const path = `${OPTIONS_DIR}/${name}`
    try {
        const [ok, contents] = GLib.file_get_contents(path)
        if (!ok || !contents) return ""
        return new TextDecoder().decode(contents).trim()
    } catch {
        return ""
    }
}

export function writeOption(name: string, value: string): void {
    const path = `${OPTIONS_DIR}/${name}`
    try {
        const file = Gio.File.new_for_path(path)
        const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null)
        const bytes = new TextEncoder().encode(value + "\n")
        stream.write_bytes(new GLib.Bytes(bytes), null)
        stream.close(null)
    } catch (e) {
        console.error(`Failed to write option ${name}:`, e)
    }
}

export const OPTIONS = [
    "browser",
    "terminal",
    "editor",
    "mediaplayer",
    "launchertype",
] as const

export type OptionName = typeof OPTIONS[number]
