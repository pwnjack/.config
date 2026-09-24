import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "./process.js"
import { checkedHyprctl } from "./hyprctl.js"
import * as persist from "./persist.js"

const configDir = GLib.get_home_dir() + "/.config"
const catalog = JSON.parse(read(configDir + "/quickshell/settings-panel/catalog.json"))
const byId = new Map(catalog.rows.map(row => [row.id, row]))
const optionPath = key => `${configDir}/options/${key}`
const idlePath = configDir + "/hypr/hypridle.conf"
const sunsetPath = configDir + "/hypr/hyprsunset.conf"
const swayPath = configDir + "/swaync/config.json"

function read(path) {
    const [ok, data] = Gio.File.new_for_path(path).load_contents(null)
    if (!ok) throw new Error(`Cannot read ${path}`)
    return new TextDecoder().decode(data)
}
function write(path, text) {
    const [ok] = Gio.File.new_for_path(path).replace_contents(
        new TextEncoder().encode(text), null, false, Gio.FileCreateFlags.NONE, null)
    if (!ok) throw new Error(`Cannot save ${path}`)
}
function readOption(key) { return read(optionPath(key)).trim() }
function idleValues(text) {
    const values = {}
    for (const block of text.match(/listener\s*\{[^}]*\}/g) || []) {
        const timeout = block.match(/\btimeout\s*=\s*(\d+)/)
        if (!timeout) continue
        if (block.includes("hyprlock")) values.lock = Number(timeout[1])
        if (/dpms/.test(block) && /off/.test(block)) values.dpms = Number(timeout[1])
    }
    if (values.lock === undefined || values.dpms === undefined) throw new Error("Cannot identify idle timeout listeners")
    return values
}
function sunsetValues(text) {
    const profiles = (text.match(/profile\s*\{[^}]*\}/g) || []).map(block => {
        const time = block.match(/\btime\s*=\s*(\d{1,2}):(\d{2})/)
        const temp = block.match(/\btemperature\s*=\s*(\d+)/)
        if (!time || !temp) throw new Error("Cannot read the night light schedule")
        return { block, minutes: Number(time[1]) * 60 + Number(time[2]), temp: Number(temp[1]) }
    }).sort((a, b) => b.temp - a.temp)
    if (profiles.length !== 2) throw new Error("The panel requires a day and an evening profile")
    const [day, night] = profiles
    return { day, night, dayMinutes: day.minutes, nightMinutes: night.minutes, nightTemp: night.temp }
}
const clock = minutes => `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`

function detached(args) {
    if (!GLib.find_program_in_path(args[0])) throw new Error(`${args[0]} is not installed`)
    GLib.spawn_async(null, args, null, GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.STDOUT_TO_DEV_NULL | GLib.SpawnFlags.STDERR_TO_DEV_NULL, null)
}
const delay = milliseconds => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => { resolve(); return GLib.SOURCE_REMOVE }))
async function restart(name) {
    if (!GLib.find_program_in_path(name)) throw new Error(`${name} is not installed`)
    try { await execAsync(["pkill", "-x", name]) } catch (_) { /* It may not be running. */ }
    // Wait for the old daemon to exit before starting the replacement.
    for (let attempt = 0; attempt < 30; attempt++) {
        try { await execAsync(["pgrep", "-x", name]) } catch (_) { break }
        if (attempt === 29) throw new Error(`${name} did not stop`)
        await delay(50)
    }
    detached([name])
    await delay(150)
    if (name === "hyprsunset") {
        const status = await execAsync(["bash", configDir + "/scripts/hyprland/nightlight.sh", "status"])
        if (status === "unavailable") throw new Error("Night light did not restart")
    }
    else await execAsync(["pgrep", "-x", name])
}
async function saveAndApply(path, text, apply) {
    const before = read(path)
    write(path, text)
    try { await apply() }
    catch (error) {
        try { write(path, before); await apply() }
        catch (rollback) { throw new Error(`${error.message}. Restoring the previous settings also failed: ${rollback.message}`) }
        throw new Error(`${error.message}. Previous settings restored.`)
    }
}

async function snapshot(ids, includeMonitors) {
    // Share category reads, including one animation tree per request.
    const cached = new Map()
    const once = (key, fn) => {
        if (!cached.has(key)) cached.set(key, Promise.resolve().then(fn))
        return cached.get(key)
    }
    const values = {}
    await Promise.all(ids.map(async id => {
        const row = byId.get(id)
        if (!row) throw new Error("Unknown setting")
        try {
            let value, reset = false
            switch (row.source) {
            case "keyword": {
                const data = JSON.parse(await execAsync(["hyprctl", "getoption", row.key, "-j"]))
                value = data.int ?? data.float ?? data.str ?? data.custom ?? data.set
                if (value === undefined) throw new Error("Hyprland did not return a value")
                if (row.kind === "toggle") value = value === true || value === 1
                else if (row.kind === "slider") value = Number(String(value).trim().split(/\s+/)[0])
                else value = String(value)
                reset = persist.hasOverride(row.key)
                break
            }
            case "animation": {
                const raw = await once("animations", async () => JSON.parse(await execAsync(["hyprctl", "animations", "-j"])))
                const tree = Array.isArray(raw[0]) ? raw[0] : raw
                const animation = tree.find(item => item.name === row.key)
                if (!animation) throw new Error("Animation is unavailable")
                value = animation.speed
                reset = persist.hasAnimationOverride(row.key)
                break
            }
            case "option": value = readOption(row.key); if (row.kind === "toggle") value = value === "enabled"; break
            case "cursor": value = Number(await execAsync(["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"])); break
            case "idle": value = (await once("idle", () => idleValues(read(idlePath))))[row.key]; break
            case "sunset": value = (await once("sunset", () => sunsetValues(read(sunsetPath))))[row.key]; break
            case "swaync": value = (await once("swaync", () => JSON.parse(read(swayPath))))[row.key] ?? row.default; break
            }
            if (row.default !== undefined) reset = value !== row.default
            values[id] = { value, reset }
        } catch (error) { values[id] = { error: error.message } }
    }))
    const result = { values }
    if (includeMonitors) {
        result.monitors = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"]))
        result.mainMonitor = readOption("mainmonitor")
    }
    return result
}

function validate(row, value) {
    if (row.kind === "toggle" && typeof value !== "boolean") throw new Error("Expected an on/off value")
    if (row.kind === "slider" && (typeof value !== "number" || !Number.isFinite(value) || value < row.min || value > row.max)) throw new Error("Value is outside this setting's range")
    if (row.kind === "slider" && row.step >= 1 && !Number.isInteger(value)) throw new Error("Expected a whole number")
    if (row.kind === "select" && !row.items.some(item => item.value === value)) throw new Error("Unknown choice")
    if (row.kind === "text" && (typeof value !== "string" || !value.trim() || /[\n\r\0]/.test(value) || value.length > 512)) throw new Error("Enter a nonempty single-line value")
}
async function cursor(theme, size) {
    await execAsync(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme])
    await execAsync(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", String(size)])
    await checkedHyprctl(["setcursor", theme, String(size)])
}
async function change(request) {
    const row = byId.get(request.id)
    if (!row) throw new Error("Unknown setting")
    if (request.op === "reset") {
        if (row.source === "keyword") return persist.resetSetting(row.key)
        if (row.source === "animation") return persist.resetAnimation(row.key)
        if (row.default === undefined) throw new Error("This setting has no reset")
    }
    const value = request.op === "reset" ? row.default : request.value
    validate(row, value)
    switch (row.source) {
    case "keyword": return persist.setPersistent(row.key, value)
    case "animation": {
        const raw = JSON.parse(await execAsync(["hyprctl", "animations", "-j"]))
        const animation = (Array.isArray(raw[0]) ? raw[0] : raw).find(item => item.name === row.key)
        if (!animation) throw new Error("Animation is unavailable")
        return persist.setAnimationPersistent(row.key, [row.key, animation.enabled ? 1 : 0, value, animation.bezier || "default", animation.style || ""].join(","))
    }
    case "option": {
        const text = row.kind === "toggle" ? (value ? "enabled" : "disabled") : value.trim()
        return saveAndApply(optionPath(row.key), text + "\n", async () => {
            if (row.key === "font" || row.key === "font-gtk") await execAsync(["bash", configDir + "/scripts/fonts/apply-font.sh"])
            // hypr/config/apptype.lua reads these at parse time.
            if (["terminal", "browser", "editor"].includes(row.key)) await persistReload()
            if (row.key === "cursortheme") await cursor(readOption(row.key), Number(await execAsync(["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"])))
        })
    }
    case "cursor": {
        const size = Number(await execAsync(["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"]))
        const theme = readOption("cursortheme")
        try { await cursor(theme, value) } catch (error) { await cursor(theme, size); throw error }
        return
    }
    case "idle": {
        const before = read(idlePath)
        idleValues(before)
        const text = before.replace(/listener\s*\{[^}]*\}/g, block => {
            const match = row.key === "lock" ? block.includes("hyprlock") : /dpms/.test(block) && /off/.test(block)
            return match ? block.replace(/(\btimeout\s*=\s*)\d+/, `$1${value}`) : block
        })
        return saveAndApply(idlePath, text, () => restart("hypridle"))
    }
    case "sunset": {
        const before = read(sunsetPath)
        const schedule = sunsetValues(before)
        const updated = { ...schedule, [row.key]: value }
        if (updated.dayMinutes === updated.nightMinutes) throw new Error("Day and evening must start at different times")
        const profile = row.key === "dayMinutes" ? schedule.day : schedule.night
        const block = row.key === "nightTemp"
            ? profile.block.replace(/(\btemperature\s*=\s*)\d+/, `$1${value}`)
            : profile.block.replace(/(\btime\s*=\s*)\d{1,2}:\d{2}/, `$1${clock(value)}`)
        return saveAndApply(sunsetPath, before.replace(profile.block, block), () => restart("hyprsunset"))
    }
    case "swaync": {
        const config = JSON.parse(read(swayPath))
        config[row.key] = value
        return saveAndApply(swayPath, JSON.stringify(config, null, 2) + "\n", () => execAsync(["swaync-client", "-rs"]))
    }
    }
}

export async function dispatch(request) {
    if (request.op === "read") {
        if (!Array.isArray(request.ids) || request.ids.length > catalog.rows.length) throw new Error("Invalid settings request")
        return snapshot([...new Set(request.ids)], request.monitors === true)
    }
    if (request.op === "set" || request.op === "reset") { await change(request); return {} }
    if (request.op === "mainMonitor") {
        const monitors = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"]))
        if (request.value !== "" && !monitors.some(m => m.name === request.value)) throw new Error("Display is no longer connected")
        if (typeof request.value !== "string" || /[\r\n\0$]/.test(request.value)) throw new Error("Invalid display name")
        const primary = configDir + "/hypr/config/hardware/primary.conf"
        const before = read(optionPath("mainmonitor"))
        write(optionPath("mainmonitor"), request.value + "\n")
        try { write(primary, "$monitor = " + request.value + "\n") }
        catch (error) { write(optionPath("mainmonitor"), before); throw error }
        return {}
    }
    if (request.op === "action") {
        if (request.id === "reload") { await persistReload(); return {} }
        const scripts = { waybar: "/scripts/waybar/waybar.sh", update: "/scripts/settings/update.sh", monitors: "/scripts/settings/advanced/monitor.sh" }
        if (!Object.hasOwn(scripts, request.id)) throw new Error("Unknown action")
        const path = configDir + scripts[request.id]
        detached(request.id === "waybar" ? ["bash", path] : [readOption("terminal") || "ghostty", "-e", path])
        return {}
    }
    throw new Error("Unknown operation")
}
async function persistReload() {
    await checkedHyprctl(["reload"])
    const errors = JSON.parse(await execAsync(["hyprctl", "configerrors", "-j"]))
    if (!Array.isArray(errors) || errors.some(error => String(error).trim())) throw new Error("Hyprland reports configuration errors")
}
