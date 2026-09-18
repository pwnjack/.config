import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { luaValue, setKeyword, reloadConfig } from "./hyprctl"

const OVERRIDES_PATH = GLib.get_home_dir() + "/.config/hypr/config/overrides.lua"

const HEADER = `--
-- PANEL-MANAGED OVERRIDES
-- Written by the Super+I settings panel (ags/lib/persist.ts).
-- Required last from hyprland.lua so these values win over tracked defaults.
-- One hl.config() or hl.animation() call per line. Do not edit by hand; use the
-- panel, or delete a line to fall back to the tracked default.
--
`

function readLines(): string[] {
    try {
        const [ok, contents] = Gio.File.new_for_path(OVERRIDES_PATH).load_contents(null)
        if (!ok || !contents) throw new Error("Cannot read saved settings")
        return new TextDecoder().decode(contents).split("\n")
    } catch (e) {
        if (e instanceof GLib.Error && e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.NOT_FOUND)) return []
        throw e
    }
}

function writeLines(lines: string[]): void {
    const body = lines.filter(l => l.trim() !== "" && !l.startsWith("--")).join("\n")
    const text = HEADER + (body ? body + "\n" : "")
    const [ok] = Gio.File.new_for_path(OVERRIDES_PATH).replace_contents(
        new TextEncoder().encode(text), null, false, Gio.FileCreateFlags.NONE, null)
    if (!ok) throw new Error("Cannot save settings")
}

// Serialize the whole apply/save operation, including rollback. Rapid slider
// changes must not race each other or a reset of another row.
let pending: Promise<void> = Promise.resolve()
function enqueue(operation: () => Promise<void>): Promise<void> {
    const result = pending.then(operation)
    pending = result.catch(() => {}) // caller receives the original rejection
    return result
}

async function applyAndSave(apply: () => Promise<void>, save: () => void): Promise<void> {
    try {
        await apply()
    } catch (error) {
        console.error("Hyprland rejected a setting:", error)
        throw new Error("The setting could not be applied. Your saved settings are unchanged.")
    }
    try {
        save()
    } catch (error) {
        console.error("Could not save settings:", error)
        try { await reloadConfig() }
        catch (rollbackError) {
            console.error("Could not restore saved settings:", rollbackError)
            throw new Error("The setting could not be saved or restored. Reload Hyprland before trying again.")
        }
        throw new Error("The setting could not be saved. Your saved settings have been restored.")
    }
}

function displayLines(): string[] {
    try { return readLines() }
    catch (error) {
        console.error("Could not read saved settings:", error)
        return []
    }
}

export function getOverride(keyword: string): string | null {
    for (const line of displayLines()) {
        const m = line.match(/-- @override (\S+) (.*)$/)
        if (m && m[1] === keyword) return m[2]
    }
    return null
}

export function hasOverride(keyword: string): boolean {
    return getOverride(keyword) !== null
}

function configCall(keyword: string, value: string | number | boolean): string {
    let nested = luaValue(value)
    for (const key of keyword.split(":").reverse()) nested = `{ ${key} = ${nested} }`
    const marker = typeof value === "boolean" ? (value ? "true" : "false") : String(value)
    return `hl.config(${nested}) -- @override ${keyword} ${marker}`
}

function upsert(keyword: string, value: string | number | boolean): void {
    const lines = readLines().filter(l => !l.includes(`-- @override ${keyword} `))
    lines.push(configCall(keyword, value))
    writeLines(lines)
}

/** Apply now via hyprctl AND persist to overrides.lua. */
export function setPersistent(keyword: string, value: string | number | boolean): Promise<void> {
    return enqueue(() => applyAndSave(() => setKeyword(keyword, value), () => upsert(keyword, value)))
}

/** Remove an override, then let Hyprland evaluate the real configuration defaults. */
async function resetMatching(matches: (line: string) => boolean): Promise<void> {
    let before: string[]
    try { before = readLines() }
    catch (error) {
        console.error("Could not read settings for reset:", error)
        throw new Error("Your saved settings could not be read. Nothing has been reset.")
    }
    try { writeLines(before.filter(line => !matches(line))) }
    catch (error) {
        console.error("Could not save reset:", error)
        throw new Error("The setting could not be reset. Your saved settings are unchanged.")
    }
    try { await reloadConfig() }
    catch (error) {
        console.error("Could not apply reset:", error)
        try {
            writeLines(before)
            await reloadConfig()
        } catch (rollbackError) {
            console.error("Could not restore settings after reset:", rollbackError)
            throw new Error("The reset failed and could not be fully restored. Check your Hyprland configuration before trying again.")
        }
        throw new Error("The setting could not be reset. Your previous settings have been restored.")
    }
}

export function resetSetting(keyword: string): Promise<void> {
    return enqueue(() => resetMatching(line => line.includes(`-- @override ${keyword} `)))
}

/**
 * Persist a full animation line, e.g. "windows,1,6,default".
 * Stored as an hl.animation() call; matched/replaced by its marker comment.
 */
export function setAnimationPersistent(name: string, line: string): Promise<void> {
    return enqueue(() => applyAndSave(() => setKeyword("animation", line), () => {
        const lines = readLines().filter(l => !l.endsWith(`-- @animation ${name}`))
        const [leaf, enabled, speed, bezier, ...styleParts] = line.split(",")
        const fields = [
            `leaf = ${JSON.stringify(leaf)}`,
            `enabled = ${enabled !== "0"}`,
            `speed = ${Number(speed)}`,
            `bezier = ${JSON.stringify(bezier)}`,
        ]
        const style = styleParts.join(",")
        if (style) fields.push(`style = ${JSON.stringify(style)}`)
        lines.push(`hl.animation({ ${fields.join(", ")} }) -- @animation ${name}`)
        writeLines(lines)
    }))
}

export function hasAnimationOverride(name: string): boolean {
    return displayLines().some(l => l.endsWith(`-- @animation ${name}`))
}

export function resetAnimation(name: string): Promise<void> {
    return enqueue(() => resetMatching(line => line.endsWith(`-- @animation ${name}`)))
}
