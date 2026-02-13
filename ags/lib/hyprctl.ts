import { execAsync } from "ags/process"
import GLib from "gi://GLib"

function execSync(cmd: string): string {
    try {
        const [ok, stdout, _stderr, _status] = GLib.spawn_command_line_sync(cmd)
        if (!ok) return ""
        return stdout ? new TextDecoder().decode(stdout).trim() : ""
    } catch (e) {
        console.error(`exec error: ${e}`)
        return ""
    }
}

export function setKeyword(keyword: string, value: string | number | boolean): void {
    const val = typeof value === "boolean" ? (value ? "true" : "false") : String(value)
    execAsync(["hyprctl", "keyword", keyword, val]).catch(console.error)
}

export function getOption(name: string): string {
    const output = execSync(`hyprctl getoption ${name} -j`)
    if (!output) return ""
    try {
        const json = JSON.parse(output)
        if (json.int !== undefined) return String(json.int)
        if (json.float !== undefined) return String(json.float)
        if (json.str !== undefined) return json.str
        if (json.set !== undefined) return String(json.set)
        return ""
    } catch {
        return ""
    }
}

export function getOptionBool(name: string): boolean {
    const output = execSync(`hyprctl getoption ${name} -j`)
    if (!output) return false
    try {
        const json = JSON.parse(output)
        return json.int === 1 || json.set === true
    } catch {
        return false
    }
}

export function getOptionInt(name: string): number {
    const val = getOption(name)
    return parseInt(val) || 0
}

export function getOptionFloat(name: string): number {
    const val = getOption(name)
    return parseFloat(val) || 0
}
