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
        if (!(key in entry) || key === "Hidden" || key === "X-systemd-skip") entry[key] = line.slice(eq + 1).trim()
    }
    return entry
}
const list = value => (value || "").split(";").map(s => s.trim()).filter(Boolean)
export function execBinary(entry) { return firstExecWord(entry.TryExec || entry.Exec || "") }
function firstExecWord(command) {
    let word = "", quote = "", started = false
    for (let index = 0; index < command.length; ++index) {
        const char = command[index]
        if (char === "\\" && index + 1 < command.length) { word += command[++index]; started = true; continue }
        if (quote) {
            if (char === quote) quote = ""
            else word += char
        } else if (char === "'" || char === '"') { quote = char; started = true }
        else if (/\s/.test(char)) { if (started) break }
        else { word += char; started = true }
    }
    return word
}
const trueValues = ["1", "yes", "y", "true", "t", "on"]
function isTrue(value) { return trueValues.includes((value || "").toLowerCase()) }
function scopeOf(entry, desktops) {
    if (entry.Type !== "Application") return "Not an application entry"
    if (!firstExecWord(entry.Exec || "")) return "No command to run"
    if (isTrue(entry["X-systemd-skip"])) return "Skipped by systemd"
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
        const tryBinary = described.TryExec ? firstExecWord(described.TryExec) : ""
        const commandBinary = firstExecWord(described.Exec || "")
        const binary = tryBinary && !onPath(tryBinary) ? tryBinary : commandBinary || tryBinary
        return {
            id, name: described.Name || id.replace(/\.desktop$/, ""),
            origin: base === undefined ? "user" : own === undefined ? "system" : "override",
            enabled: !isTrue(effective.Hidden),
            ignoredGnomeFlag: (effective["X-GNOME-Autostart-enabled"] || "").toLowerCase() === "false",
            scope: scopeOf(described, desktops), binary,
            installed: Boolean(commandBinary) && (!tryBinary || onPath(tryBinary)) && onPath(commandBinary), unit: unitName(id),
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

// systemd unit-name escaping: keep [A-Za-z0-9:_.] except a leading dot.
export function unitName(id) {
    const escaped = utf8Bytes(id.replace(/\.desktop$/, ""))
        .map((byte, index) => byte === 46 && index === 0 ? "\\x2e"
            : /[A-Za-z0-9:_.]/.test(String.fromCharCode(byte)) ? String.fromCharCode(byte) : "\\x" + byte.toString(16).padStart(2, "0")).join("")
    return `app-${escaped}@autostart.service`
}
export function isAutostartFileName(name) {
    // Backup suffixes also fail the required .desktop ending.
    return name.endsWith(".desktop") && !name.startsWith(".")
}
export function withStatus(entries, units) {
    const byUnit = new Map(units.map(u => [u.unit, u]))
    return entries.map(entry => {
        const unit = byUnit.get(entry.unit)
        let status
        if (entry.scope) status = { state: "none", label: "" }
        else if (!entry.installed) status = { state: "missing", label: `Not installed: ${entry.binary}` }
        else if (!unit) status = { state: "none", label: entry.enabled && !entry.scope ? "Not started this session" : "" }
        else if (unit.active === "failed") status = { state: "failed", label: "Failed" }
        else if (unit.active === "active" || unit.active === "activating") status = { state: "running", label: "Running" }
        else status = { state: "finished", label: "Finished" }
        return Object.assign({}, entry, { status })
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
    const newline = text.includes("\r\n") ? "\r\n" : "\n"
    let main = false, foundMain = false, lastMain = -1
    for (const line of text.split(newline)) {
        const trimmed = line.trim()
        if (trimmed.startsWith("[")) { main = trimmed === "[Desktop Entry]"; out.push(line); if (main) { foundMain = true; lastMain = out.length - 1 } continue }
        if (main && /^Hidden\s*=/.test(trimmed)) continue
        if (main && !hidden && /^X-GNOME-Autostart-enabled\s*=\s*false$/.test(trimmed)) continue
        out.push(line)
        if (main && trimmed) lastMain = out.length - 1
    }
    if (!foundMain) throw new Error("Not a desktop entry")
    if (hidden) out.splice(lastMain + 1, 0, "Hidden=true")
    return out.join(newline)
}

export function sessionCommands(lua) {
    const withoutBlocks = lua.replace(/--\[\[[\s\S]*?\]\]/g, "")
    const code = withoutBlocks.split("\n").map(line => {
        let quote = ""
        for (let index = 0; index < line.length; ++index) {
            const char = line[index]
            if (quote) {
                if (char === "\\") ++index
                else if (char === quote) quote = ""
            } else if (char === "'" || char === '"') quote = char
            else if (char === "-" && line[index + 1] === "-") return line.slice(0, index)
        }
        return line
    }).join("\n")
    const commands = [], pattern = /hl\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"(\s*\.\.)?/g
    let match
    while ((match = pattern.exec(code)) !== null)
        commands.push(match[1].replace(/\\(.)/g, "$1").replace(/\s+$/, "") + (match[2] ? " …" : ""))
    return commands
}
