import GLib from "gi://GLib"
import Gio from "gi://Gio"
import GioUnix from "gi://GioUnix"
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
const kvantumPath = configDir + "/Kvantum/kvantum.kvconfig"
const kvantumDirs = [configDir + "/Kvantum", "/usr/share/Kvantum"]

function read(path) {
    const [ok, data] = Gio.File.new_for_path(path).load_contents(null)
    if (!ok) throw new Error(`Cannot read ${path}`)
    return new TextDecoder().decode(data)
}
function readBytes(path) {
    const [ok, data] = Gio.File.new_for_path(path).load_contents(null)
    if (!ok) throw new Error(`Cannot read ${path}`)
    return data
}
function writeBytes(path, data) {
    const [ok] = Gio.File.new_for_path(path).replace_contents(data, null, false, Gio.FileCreateFlags.NONE, null)
    if (!ok) throw new Error(`Cannot save ${path}`)
}
function write(path, text) {
    writeBytes(path, new TextEncoder().encode(text))
}
const exists = path => Gio.File.new_for_path(path).query_exists(null)
function children(path) {
    let enumerator
    try { enumerator = Gio.File.new_for_path(path).enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null) }
    catch (_) { return [] } // A missing search directory is normal.
    const names = []
    for (let info; (info = enumerator.next_file(null));) names.push(info.get_name())
    enumerator.close(null)
    return names
}
const home = GLib.get_home_dir()
const themeDirs = kind => [`${home}/.local/share/${kind}`, `${home}/.${kind}`, `/usr/share/${kind}`]
function themeNames(dirs, isTheme, builtins = []) {
    const names = new Set(builtins)
    for (const dir of dirs) for (const name of children(dir))
        if (!/[\r\n]/.test(name) && isTheme(`${dir}/${name}`)) names.add(name)
    return [...names].sort((a, b) => a.localeCompare(b)).map(name => ({ label: name, value: name }))
}
const hasIcons = dir => { try { return /^Directories=/m.test(read(`${dir}/index.theme`)) } catch (_) { return false } }
const mimeDefault = async mime => (await execAsync(["xdg-mime", "query", "default", mime])).trim()
// Each enumerator returns what the system has now, so validation and the
// dropdown can never disagree. GTK's built-ins have no theme directories:
// they are libgtk-3 resources (`gresource list libgtk-3.so.0`, minus win32).
const enumerators = {
    "gtk-themes": () => themeNames(themeDirs("themes"), dir => exists(`${dir}/gtk-3.0/gtk.css`), ["Adwaita", "HighContrast", "HighContrastInverse"]),
    "icon-themes": () => themeNames(themeDirs("icons"), hasIcons),
    "cursor-themes": () => themeNames(themeDirs("icons"), dir => exists(`${dir}/cursors`)),
    "kvantum-themes": () => themeNames(kvantumDirs, dir => exists(`${dir}/${dir.split("/").pop()}.kvconfig`)),
    applications: async (row, knownCurrent) => {
        const apps = Gio.AppInfo.get_all_for_type(row.mimes[0]).map(app => ({ label: app.get_name(), value: app.get_id() }))
        const current = knownCurrent === undefined ? await mimeDefault(row.mimes[0]) : knownCurrent
        if (current && !apps.some(app => app.value === current)) apps.push({ label: current.replace(/\.desktop$/, ""), value: current })
        return apps
    },
}
async function choicesFor(row, current) {
    if (row.items) return row.items
    if (!Object.hasOwn(enumerators, row.choices)) throw new Error("This setting has no choices")
    return enumerators[row.choices](row, current)
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

// hyprctl getoption names the value field after the option's type. `set` only
// says whether the config assigns the option, so it is never a value.
function keywordValue(data) {
    for (const field of ["bool", "int", "float", "str", "css", "custom"]) {
        if (data[field] === undefined) continue
        return field === "str" && data[field] === "[[EMPTY]]" ? "" : data[field]
    }
    throw new Error("Hyprland did not return a value")
}

const gtkIniPaths = ["gtk-3.0", "gtk-4.0"].map(dir => `${configDir}/${dir}/settings.ini`)
const gsettingsArgs = key => ["org.gnome.desktop.interface", key]
function gvariantValue(text) {
    const quoted = text.trim().match(/^'(.*)'$/)
    return quoted ? quoted[1] : Number(text)
}
const gvariantLiteral = value => typeof value === "number" ? String(value) : `'${String(value).replace(/[\\']/g, "\\$&")}'`
const regexEscape = text => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
function iniSection(text, name) {
    const header = new RegExp(`^(\\[${regexEscape(name)}\\])(\\r\\n|\\n|\\r|$)`, "m").exec(text)
    if (!header) return null
    const start = header.index + header[0].length
    const next = /^\[[^\r\n]*\](?=\r?$)/m.exec(text.slice(start))
    return { header, start, end: next ? start + next.index : text.length }
}
function iniValue(text, key, sectionName = "Settings") {
    const section = iniSection(text, sectionName)
    if (!section) return ""
    const pattern = new RegExp(`^${regexEscape(key)}=([^\\r\\n]*)(?=\\r?$)`, "m")
    return (pattern.exec(text.slice(section.start, section.end)) || [, ""])[1]
}
function iniSet(path, text, key, value, sectionName = "Settings") {
    if (/[\r\n]/.test(value)) throw new Error(`Cannot write a multiline value to ${path}`)
    const section = iniSection(text, sectionName)
    if (!section) throw new Error(`${path} has no [${sectionName}] section`)
    const line = `${key}=${value}`
    const body = text.slice(section.start, section.end)
    const pattern = new RegExp(`^${regexEscape(key)}=[^\\r\\n]*(?=\\r?$)`, "m")
    if (pattern.test(body))
        return text.slice(0, section.start) + body.replace(pattern, () => line) + text.slice(section.end)
    const ending = section.header[2]
    const insertion = ending ? `${line}${ending}` : `\n${line}\n`
    return text.slice(0, section.start) + insertion + text.slice(section.start)
}
// GTK 3 on Wayland reads some keys from gsettings and others from settings.ini,
// so both are written; the ini files are tracked and keep every other line.
function writeGtkIni(entries) {
    for (const path of gtkIniPaths) {
        if (!exists(path)) continue
        let text = read(path)
        for (const [key, value] of entries) text = iniSet(path, text, key, value)
        write(path, text)
    }
}
async function setGtk(row, value) {
    if (/[\r\n]/.test(String(value))) throw new Error("Cannot write a multiline GTK value")
    const before = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)]))
    const saved = gtkIniPaths.filter(exists).map(path => [path, read(path)])
    try {
        if (row.ini) writeGtkIni([[row.ini.key, row.ini.values ? row.ini.values[value] : String(value)]])
        await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(value)])
    } catch (error) {
        for (const [path, text] of saved) write(path, text)
        try { await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(before)]) }
        catch (rollback) { throw new Error(`${error.message}. Restoring the previous gsettings value also failed: ${rollback.message}`) }
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
                value = keywordValue(data)
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
            case "cursor": value = Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")])); break
            case "gtk": value = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)])); break
            case "idle": value = (await once("idle", () => idleValues(read(idlePath))))[row.key]; break
            case "sunset": value = (await once("sunset", () => sunsetValues(read(sunsetPath))))[row.key]; break
            case "swaync": value = (await once("swaync", () => JSON.parse(read(swayPath))))[row.key] ?? row.default; break
            case "kvantum": value = exists(kvantumPath) ? iniValue(read(kvantumPath), "theme", "General") : ""; break
            case "mime": value = await mimeDefault(row.mimes[0]); break
            }
            if (row.default !== undefined) reset = value !== row.default
            values[id] = row.choices ? { value, reset, choices: await choicesFor(row, value) } : { value, reset }
        } catch (error) { values[id] = { error: error.message } }
    }))
    const result = { values }
    if (includeMonitors) {
        result.monitors = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"]))
        result.mainMonitor = readOption("mainmonitor")
    }
    return result
}

const xkbLists = new Map()
function xkbList(...args) {
    const key = args.join(" ")
    if (!xkbLists.has(key)) xkbLists.set(key, execAsync(["localectl", ...args]).then(text => text.split("\n").filter(Boolean)))
    return xkbLists.get(key)
}
async function currentKeyword(key) {
    return String(keywordValue(JSON.parse(await execAsync(["hyprctl", "getoption", key, "-j"]))))
}
async function checkVariants(value, layouts) {
    if (!value) return
    const variants = value.split(",")
    if (variants.length > layouts.length) throw new Error("There are more variants than layouts")
    for (const [index, variant] of variants.entries()) {
        if (variant && !(await xkbList("list-x11-keymap-variants", layouts[index])).includes(variant))
            throw new Error(`${layouts[index]} has no variant ${variant}`)
    }
}
// A rejected keymap leaves Hyprland on its old one with only a log line, so
// every XKB name is checked before it is applied.
const checks = {
    "xkb-layout": async value => {
        const known = await xkbList("list-x11-keymap-layouts")
        const layouts = value.split(",")
        for (const layout of layouts) if (!known.includes(layout)) throw new Error(`Unknown keyboard layout ${layout}`)
        await checkVariants(await currentKeyword("input:kb_variant"), layouts)
    },
    "xkb-variant": async value => checkVariants(value, (await currentKeyword("input:kb_layout")).split(",")),
    "xkb-options": async value => {
        if (!value) return
        const known = await xkbList("list-x11-keymap-options")
        for (const option of value.split(",")) if (!known.includes(option)) throw new Error(`Unknown keyboard option ${option}`)
    },
    font: async value => {
        const families = (await execAsync(["fc-list", ":", "family"])).split("\n").flatMap(line => line.split(",")).map(name => name.trim())
        if (!families.includes(value)) throw new Error(`No installed font is named ${value}`)
    },
    command: value => {
        const program = value.split(/\s+/)[0]
        if (!GLib.find_program_in_path(program)) throw new Error(`${program} is not installed`)
    },
}
async function validate(row, value) {
    if (row.kind === "toggle" && typeof value !== "boolean") throw new Error("Expected an on/off value")
    if (row.kind === "slider" && (typeof value !== "number" || !Number.isFinite(value) || value < row.min || value > row.max)) throw new Error("Value is outside this setting's range")
    if (row.kind === "slider" && row.step >= 1 && !Number.isInteger(value)) throw new Error("Expected a whole number")
    if (row.kind === "select" && !(await choicesFor(row)).some(item => item.value === value)) throw new Error("Unknown choice")
    if (row.kind === "text") {
        if (typeof value !== "string" || /[\n\r\0]/.test(value) || value.length > 512) throw new Error("Enter a single-line value")
        if (!value.trim() && !row.optional) throw new Error("Enter a nonempty single-line value")
        if (row.check) await checks[row.check](value.trim())
    }
}
async function cursor(theme, size) {
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-theme"), theme])
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-size"), String(size)])
    writeGtkIni([["gtk-cursor-theme-name", theme], ["gtk-cursor-theme-size", String(size)]])
    await checkedHyprctl(["setcursor", theme, String(size)])
}
async function change(request) {
    const row = byId.get(request.id)
    if (!row) throw new Error("Unknown setting")
    if (request.op === "reset") {
        if (row.source === "keyword") {
            if (row.check === "xkb-layout" && persist.hasOverride("input:kb_variant")) throw new Error("Reset Layout Variant first; it may not exist for the default layout")
            return persist.resetSetting(row.key)
        }
        if (row.source === "animation") return persist.resetAnimation(row.key)
        if (row.default === undefined) throw new Error("This setting has no reset")
    }
    const value = request.op === "reset" ? row.default : request.value
    await validate(row, value)
    switch (row.source) {
    case "keyword": return persist.setPersistent(row.key, row.kind === "text" ? value.trim() : value)
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
            if (row.reload) await persistReload()
            if (row.key === "cursortheme") await cursor(readOption(row.key), Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")])))
        })
    }
    case "cursor": {
        const size = Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")]))
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
    case "kvantum": {
        const text = exists(kvantumPath) ? read(kvantumPath) : "[General]\n"
        const updated = iniSet(kvantumPath, text, "theme", value, "General")
        if (!exists(kvantumDirs[0])) Gio.File.new_for_path(kvantumDirs[0]).make_directory_with_parents(null)
        return write(kvantumPath, updated)
    }
    case "gtk": return setGtk(row, value)
    case "mime": {
        const app = GioUnix.DesktopAppInfo.new(value)
        const declared = new Set(app?.get_supported_types() || [])
        const mimes = row.mimes.filter(mime => declared.has(mime))
        if (!mimes.length) mimes.push(row.mimes[0])
        const path = configDir + "/mimeapps.list"
        const hadFile = exists(path)
        const before = hadFile ? readBytes(path) : null
        try {
            for (const mime of mimes) await execAsync(["xdg-mime", "default", value, mime])
        } catch (error) {
            try {
                if (hadFile) writeBytes(path, before)
                else if (exists(path)) Gio.File.new_for_path(path).delete(null)
            } catch (rollback) {
                error.message += `. Restoring mimeapps.list also failed: ${rollback.message}`
            }
            throw error
        }
        return
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
