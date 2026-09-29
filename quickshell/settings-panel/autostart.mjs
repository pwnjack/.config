// The rules systemd-xdg-autostart-generator applies, over file contents handed
// in by the backend. Pure, so the whole Startup page logic runs under Node.

export function parseEntry(text) {
    const entry = {}
    let main = false
    for (const raw of text.split("\n")) {
        const line = raw.trim()
        if (line.startsWith("[")) { main = line === "[Desktop Entry]"; continue }
        if (!main || !line || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 0) continue
        const key = line.slice(0, eq).trim()
        if (!(key in entry)) entry[key] = line.slice(eq + 1).trim()
    }
    return entry
}
const list = value => (value || "").split(";").map(s => s.trim()).filter(Boolean)
export function execBinary(entry) {
    if (entry.TryExec) return entry.TryExec
    const match = (entry.Exec || "").match(/^\s*(?:"((?:[^"\\]|\\.)*)"|(\S+))/)
    return match ? (match[1] ?? match[2]).replace(/\\(.)/g, "$1") : ""
}
function scopeOf(entry, desktops) {
    if (entry["X-systemd-skip"] === "true") return "Skipped by systemd"
    const only = list(entry.OnlyShowIn), not = list(entry.NotShowIn)
    if (only.length && !only.some(d => desktops.includes(d))) return `Only for ${only.join(", ")}`
    const excluded = not.filter(d => desktops.includes(d))
    if (excluded.length) return `Not for ${excluded.join(", ")}`
    return ""
}
export function autostartEntries({ system, user, desktops, onPath }) {
    const sys = new Map(system.map(f => [f.id, f.text]))
    const usr = new Map(user.map(f => [f.id, f.text]))
    return [...new Set([...sys.keys(), ...usr.keys()])].map(id => {
        const own = usr.get(id), base = sys.get(id)
        const effective = parseEntry(own ?? base)
        // A minimal override carries no Exec of its own: describe the file it masks.
        const described = own !== undefined && base !== undefined && isMinimalOverride(own) ? parseEntry(base) : effective
        const binary = execBinary(described)
        return {
            id, name: described.Name || id.replace(/\.desktop$/, ""),
            origin: base === undefined ? "user" : own === undefined ? "system" : "override",
            enabled: effective.Hidden !== "true" && effective["X-GNOME-Autostart-enabled"] !== "false",
            scope: scopeOf(described, desktops), binary, installed: !binary || onPath(binary), unit: unitName(id),
        }
    }).sort((a, b) => (b.enabled && !b.scope) - (a.enabled && !a.scope) || a.name.localeCompare(b.name))
}

function utf8Bytes(text) {
    const bytes = []
    for (const char of text) {
        const code = char.codePointAt(0)
        if (code < 0x80) bytes.push(code)
        else if (code < 0x800) bytes.push(0xc0 | code >> 6, 0x80 | code & 0x3f)
        else if (code < 0x10000) bytes.push(0xe0 | code >> 12, 0x80 | code >> 6 & 0x3f, 0x80 | code & 0x3f)
        else bytes.push(0xf0 | code >> 18, 0x80 | code >> 12 & 0x3f, 0x80 | code >> 6 & 0x3f, 0x80 | code & 0x3f)
    }
    return bytes
}

// systemd unit-name escaping: keep [A-Za-z0-9:_.], everything else becomes \xNN per byte.
export function unitName(id) {
    const escaped = utf8Bytes(id.replace(/\.desktop$/, ""))
        .map(byte => /[A-Za-z0-9:_.]/.test(String.fromCharCode(byte)) ? String.fromCharCode(byte) : "\\x" + byte.toString(16).padStart(2, "0")).join("")
    return `app-${escaped}@autostart.service`
}
export function withStatus(entries, units) {
    const byUnit = new Map(units.map(u => [u.unit, u]))
    return entries.map(entry => {
        const unit = byUnit.get(entry.unit)
        let status
        if (!entry.installed) status = { state: "missing", label: `Not installed: ${entry.binary}` }
        else if (!unit) status = { state: "none", label: entry.enabled && !entry.scope ? "Not started this session" : "" }
        else if (unit.active === "failed") status = { state: "failed", label: "Failed" }
        else if (unit.active === "active" || unit.active === "activating") status = { state: "running", label: "Running" }
        else status = { state: "finished", label: "Finished" }
        return { ...entry, status }
    })
}

export const minimalOverride = name => `[Desktop Entry]\nType=Application\nName=${name.replace(/[\r\n]+/g, " ")}\nHidden=true\n`
export function isMinimalOverride(text) {
    const lines = text.split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"))
    return lines.length === 4 && lines[0] === "[Desktop Entry]" && lines.includes("Type=Application")
        && lines.includes("Hidden=true") && lines.some(l => l.startsWith("Name="))
}
// Only [Desktop Entry]'s Hidden (and on enable the GNOME flag) changes; every other line is kept.
export function setHidden(text, hidden) {
    const out = []
    let main = false, lastMain = -1
    for (const line of text.split("\n")) {
        const trimmed = line.trim()
        if (trimmed.startsWith("[")) { main = trimmed === "[Desktop Entry]"; out.push(line); if (main) lastMain = out.length - 1; continue }
        if (main && /^Hidden\s*=/.test(trimmed)) continue
        if (main && !hidden && /^X-GNOME-Autostart-enabled\s*=\s*false$/.test(trimmed)) continue
        out.push(line)
        if (main && trimmed) lastMain = out.length - 1
    }
    if (hidden) out.splice(lastMain + 1, 0, "Hidden=true")
    return out.join("\n")
}

export function sessionCommands(lua) {
    const code = lua.split("\n").filter(line => !line.trim().startsWith("--")).join("\n")
    return [...code.matchAll(/hl\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"(\s*\.\.)?/g)]
        .map(match => match[1].replace(/\\(.)/g, "$1").trimEnd() + (match[2] ? " …" : ""))
}
