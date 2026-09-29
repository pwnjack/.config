import GLib from "gi://GLib"
import { execAsync } from "./process.js"
import { callSystem, getProperty } from "./dbus.js"

const timedate = ["org.freedesktop.timedate1", "/org/freedesktop/timedate1", "org.freedesktop.timedate1"]
const locale1 = ["org.freedesktop.locale1", "/org/freedesktop/locale1", "org.freedesktop.locale1"]
// Everything a "Formats" choice sets; LANG, LC_CTYPE, LC_COLLATE and LC_MESSAGES are left alone.
export const FORMAT_KEYS = ["LC_NUMERIC", "LC_TIME", "LC_MONETARY", "LC_PAPER", "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION"]

function parseValue(source) {
    const text = source.trimStart()
    if (text.startsWith("'")) {
        const end = text.indexOf("'", 1)
        if (end < 0 || !/^\s*(?:#.*)?$/.test(text.slice(end + 1))) return null
        return text.slice(1, end)
    }
    if (text.startsWith('"')) {
        let value = ""
        let escaped = false
        for (let index = 1; index < text.length; ++index) {
            const character = text[index]
            if (escaped) { value += character; escaped = false }
            else if (character === "\\") escaped = true
            else if (character === '"')
                return /^\s*(?:#.*)?$/.test(text.slice(index + 1)) ? value : null
            else value += character
        }
        return null
    }
    return text.replace(/[ \t]+#.*$/, "").trimEnd()
}
export function parseLocaleConf(text) {
    const vars = {}
    for (const line of text.split("\n")) {
        if (/^\s*(?:#|$)/.test(line)) continue
        const match = line.match(/^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=([\s\S]*)$/)
        if (!match) continue
        const value = parseValue(match[2])
        if (value !== null) vars[match[1]] = value
    }
    return vars
}
// Order-preserving: existing keys keep their place, new ones are appended.
export function localeAssignments(current, key, value) {
    const next = Array.isArray(current)
        ? Object.fromEntries(current.flatMap(assignment => {
            const separator = assignment.indexOf("=")
            return separator > 0 ? [[assignment.slice(0, separator), assignment.slice(separator + 1)]] : []
        }))
        : { ...current }
    if (key === "language") next.LANG = value
    else for (const name of FORMAT_KEYS) next[name] = value
    return Object.entries(next).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`)
}
function timezoneOf(link) {
    const match = link?.match(/zoneinfo\/(.+)$/)
    if (!match) return "UTC"
    return match[1].replace(/^(?:posix|right)\//, "") || "UTC"
}
// Each row reads only its own source, so one unavailable service or file cannot
// turn every Date & Region row into an error.
export async function regionValue(key, read, exists) {
    switch (key) {
    case "timezone": {
        try { return { value: timezoneOf(GLib.file_read_link("/etc/localtime")) } }
        catch (_error) { return { value: "UTC" } }
    }
    case "ntp": {
        const [ntp, synced] = await Promise.all([getProperty(...timedate, "NTP"), getProperty(...timedate, "NTPSynchronized")])
        return { value: ntp, note: synced ? "Synchronized with a time server" : "Not synchronized yet" }
    }
    case "language": {
        const locale = exists("/etc/locale.conf") ? parseLocaleConf(read("/etc/locale.conf")) : {}
        return { value: locale.LANG || "C.UTF-8" }
    }
    case "formats": {
        const locale = exists("/etc/locale.conf") ? parseLocaleConf(read("/etc/locale.conf")) : {}
        return { value: locale.LC_TIME || locale.LANG || "C.UTF-8" }
    }
    }
    throw new Error("Unknown region setting")
}
export const regionEnumerators = {
    timezones: async (_row, _current, once) => (await once("timezones", async () => (await callSystem(...timedate, "ListTimezones", null, null))[0]))
        .slice().sort().map(zone => ({ label: zone.replace(/_/g, " ").replace(/\//g, " / "), value: zone })),
    locales: async (_row, _current, once) => (await once("locales", async () => (await execAsync(["localectl", "list-locales"])).split("\n")))
        .map(line => line.trim()).filter(line => /\.UTF-8$/i.test(line)).map(line => ({ label: line, value: line })),
}
export async function setRegion(key, value) {
    if (key === "timezone") return callSystem(...timedate, "SetTimezone", "(sb)", [value, true], { interactive: true })
    if (key === "ntp") return callSystem(...timedate, "SetNTP", "(bb)", [value, true], { interactive: true })
    const current = await getProperty(...locale1, "Locale")
    return callSystem(...locale1, "SetLocale", "(asb)", [localeAssignments(current, key, value), true], { interactive: true })
}
