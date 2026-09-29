import GLib from "gi://GLib"
import { execAsync } from "./process.js"
import { callSystem, getProperty } from "./dbus.js"

const timedate = ["org.freedesktop.timedate1", "/org/freedesktop/timedate1", "org.freedesktop.timedate1"]
const locale1 = ["org.freedesktop.locale1", "/org/freedesktop/locale1", "org.freedesktop.locale1"]
// Everything a "Formats" choice sets; LANG, LC_CTYPE, LC_COLLATE and LC_MESSAGES are left alone.
export const FORMAT_KEYS = ["LC_NUMERIC", "LC_TIME", "LC_MONETARY", "LC_PAPER", "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION"]

export function parseLocaleConf(text) {
    const vars = {}
    for (const line of text.split("\n")) {
        const match = line.match(/^\s*([A-Z_]+)=("?)([^"]*)\2\s*$/)
        if (match) vars[match[1]] = match[3]
    }
    return vars
}
// Order-preserving: existing keys keep their place, new ones are appended.
export function localeAssignments(current, key, value) {
    const next = { ...current }
    if (key === "language") next.LANG = value
    else for (const name of FORMAT_KEYS) next[name] = value
    return Object.entries(next).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`)
}
function timezoneOf(link) {
    const match = link?.match(/zoneinfo\/(.+)$/)
    if (!match) throw new Error("The time zone is not set")
    return match[1]
}
// Files first: /etc/localtime and /etc/locale.conf cost nothing; D-Bus only for NTP.
export async function regionState(read) {
    const [ntp, synced] = await Promise.all([getProperty(...timedate, "NTP"), getProperty(...timedate, "NTPSynchronized")])
    return { timezone: timezoneOf(GLib.file_read_link("/etc/localtime")), ntp, synced, locale: parseLocaleConf(read("/etc/locale.conf")) }
}
export function regionValue(key, state) {
    switch (key) {
    case "timezone": return { value: state.timezone }
    case "ntp": return { value: state.ntp, note: state.synced ? "Synchronized with a time server" : "Not synchronized yet" }
    case "language": return { value: state.locale.LANG || "C.UTF-8" }
    case "formats": return { value: state.locale.LC_TIME || state.locale.LANG || "C.UTF-8" }
    }
    throw new Error("Unknown region setting")
}
export const regionEnumerators = {
    timezones: async (_row, _current, once) => (await once("timezones", async () => (await callSystem(...timedate, "ListTimezones", null, null))[0]))
        .slice().sort().map(zone => ({ label: zone.replace(/_/g, " ").replace(/\//g, " / "), value: zone })),
    locales: async (_row, _current, once) => (await once("locales", async () => (await execAsync(["localectl", "list-locales"])).split("\n")))
        .map(line => line.trim()).filter(line => /\.UTF-8$/i.test(line)).map(line => ({ label: line, value: line })),
}
export function setRegion(key, value, state) {
    if (key === "timezone") return callSystem(...timedate, "SetTimezone", "(sb)", [value, true], { interactive: true })
    if (key === "ntp") return callSystem(...timedate, "SetNTP", "(bb)", [value, true], { interactive: true })
    return callSystem(...locale1, "SetLocale", "(asb)", [localeAssignments(state.locale, key, value), true], { interactive: true })
}
