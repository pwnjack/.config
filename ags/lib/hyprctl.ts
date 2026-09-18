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

export function luaValue(value: string | number | boolean): string {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") return String(value)
    if (value === "true" || value === "false") return value
    if (/^-?(?:\d+\.?\d*|\.\d+)$/.test(value)) return value
    return JSON.stringify(value)
}

export async function setKeyword(keyword: string, value: string | number | boolean): Promise<void> {
    let expression: string

    if (keyword === "animation") {
        const [leaf, enabled, speed, bezier, ...styleParts] = String(value).split(",")
        const fields = [
            `leaf = ${JSON.stringify(leaf)}`,
            `enabled = ${enabled !== "0"}`,
            `speed = ${Number(speed)}`,
            `bezier = ${JSON.stringify(bezier)}`,
        ]
        const style = styleParts.join(",")
        if (style) fields.push(`style = ${JSON.stringify(style)}`)
        expression = `hl.animation({ ${fields.join(", ")} })`
    } else {
        let nested = luaValue(value)
        for (const key of keyword.split(":").reverse()) nested = `{ ${key} = ${nested} }`
        expression = `hl.config(${nested})`
    }

    await checkedHyprctl(["eval", expression])
}

export function getOption(name: string): string {
    const output = execSync(`hyprctl getoption ${name} -j`)
    if (!output) return ""
    try {
        const json = JSON.parse(output)
        if (json.int !== undefined) return String(json.int)
        if (json.float !== undefined) return String(json.float)
        if (json.str !== undefined) return json.str
        if (json.custom !== undefined) return String(json.custom).trim().split(/\s+/)[0] // custom values like gaps are "N N N N"; first token is the canonical value
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

/** hyprctl can report a Lua error in stdout even when the process exits zero. */
export async function checkedHyprctl(args: string[]): Promise<void> {
    const reply = (await execAsync(["hyprctl", ...args])).trim()
    if (reply !== "ok") throw new Error(reply || "Hyprland returned no confirmation")
}

export async function reloadConfig(): Promise<void> {
    await checkedHyprctl(["reload"])
    const errors = JSON.parse(await execAsync(["hyprctl", "configerrors", "-j"]))
    if (!Array.isArray(errors) || errors.some(error => typeof error !== "string" || error.trim() !== "")) {
        throw new Error(`Hyprland configuration errors: ${JSON.stringify(errors)}`)
    }
}
