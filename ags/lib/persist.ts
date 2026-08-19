import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"
import { setKeyword } from "./hyprctl"

const OVERRIDES_PATH = GLib.get_home_dir() + "/.config/hypr/config/overrides.lua"

const HEADER = `--
-- PANEL-MANAGED OVERRIDES
-- Written by the Super+I settings panel (ags/lib/persist.ts).
-- Required last from hyprland.lua so these values win over tracked defaults.
-- One hl.config() or hl.animation() call per line. Do not edit by hand; use the
-- panel, or delete a line to fall back to the tracked default.
--
`

// Mirrors the tracked repo configs (decor.lua, general.lua, input.lua).
export const DEFAULTS: Record<string, string> = {
    "general:gaps_in": "4",
    "general:gaps_out": "10",
    "general:border_size": "1",
    "general:resize_on_border": "true",
    "general:allow_tearing": "false",
    "general:layout": "dwindle",
    "decoration:rounding": "18",
    "decoration:active_opacity": "1.0",
    "decoration:inactive_opacity": "1.0",
    "decoration:shadow:enabled": "false",
    "decoration:blur:enabled": "true",
    "decoration:blur:size": "6",
    "decoration:blur:passes": "4",
    "animations:enabled": "true",
    "input:sensitivity": "0",
    "input:follow_mouse": "1",
    "input:numlock_by_default": "true",
    "input:touchpad:natural_scroll": "false",
    "input:touchpad:scroll_factor": "0.6",
    "dwindle:preserve_split": "true",
    "dwindle:smart_split": "false",
    "misc:vrr": "0",
    "misc:key_press_enables_dpms": "true",
    "misc:mouse_move_enables_dpms": "true",
    "xwayland:enabled": "true",
    "cursor:enable_hyprcursor": "true",
}

function readLines(): string[] {
    try {
        const [ok, contents] = GLib.file_get_contents(OVERRIDES_PATH)
        if (!ok || !contents) return []
        return new TextDecoder().decode(contents).split("\n")
    } catch {
        return []
    }
}

function writeLines(lines: string[]): void {
    const body = lines.filter(l => l.trim() !== "" && !l.startsWith("--")).join("\n")
    const text = HEADER + (body ? body + "\n" : "")
    try {
        const file = Gio.File.new_for_path(OVERRIDES_PATH)
        // replace_contents is atomic (writes temp file, then renames)
        file.replace_contents(new TextEncoder().encode(text), null, false,
            Gio.FileCreateFlags.NONE, null)
    } catch (e) {
        console.error("Failed to write overrides.lua:", e)
    }
}

export function getOverride(keyword: string): string | null {
    for (const line of readLines()) {
        const m = line.match(/-- @override (\S+) (.*)$/)
        if (m && m[1] === keyword) return m[2]
    }
    return null
}

export function hasOverride(keyword: string): boolean {
    return getOverride(keyword) !== null
}

function luaValue(value: string | number | boolean): string {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") return String(value)
    return JSON.stringify(value)
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

function removeLine(keyword: string): void {
    writeLines(readLines().filter(l => !l.includes(`-- @override ${keyword} `)))
}

/** Apply now via hyprctl AND persist to overrides.lua. */
export function setPersistent(keyword: string, value: string | number | boolean): void {
    setKeyword(keyword, value)
    upsert(keyword, value)
}

/** Remove the override and re-apply the tracked default (if known). */
export function resetSetting(keyword: string): void {
    removeLine(keyword)
    const def = DEFAULTS[keyword]
    if (def !== undefined) setKeyword(keyword, def)
}

/**
 * Persist a full animation line, e.g. "windows,1,6,default".
 * Stored as an hl.animation() call; matched/replaced by its marker comment.
 */
export function setAnimationPersistent(name: string, line: string): void {
    const lines = readLines().filter(l => !l.includes(`-- @animation ${name}`))
    const [leaf, enabled, speed, bezier, style] = line.split(",")
    const fields = [
        `leaf = ${JSON.stringify(leaf)}`,
        `enabled = ${enabled !== "0"}`,
        `speed = ${Number(speed)}`,
        `bezier = ${JSON.stringify(bezier)}`,
    ]
    if (style) fields.push(`style = ${JSON.stringify(style)}`)
    lines.push(`hl.animation({ ${fields.join(", ")} }) -- @animation ${name}`)
    writeLines(lines)
    setKeyword("animation", line)
}

export function hasAnimationOverride(name: string): boolean {
    return readLines().some(l => l.includes(`-- @animation ${name}`))
}

export function resetAnimation(name: string): void {
    writeLines(readLines().filter(l => !l.includes(`-- @animation ${name}`)))
    // No hyprctl re-apply: tracked animations.lua value returns on next reload.
    execAsync(["hyprctl", "reload"]).catch(console.error)
}
