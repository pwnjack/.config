import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

const CONFIG_PATH = GLib.get_home_dir() + "/.config/hypr/hyprsunset.conf"

/**
 * Night light schedule, as held by hypr/hyprsunset.conf.
 *
 * Times are minutes-from-midnight rather than "HH:MM" strings so the panel can
 * drive them with a slider and never produce a time hyprsunset would reject
 * ("Invalid time format: {}, skipping profile {}").
 */
export interface SunsetSchedule {
    dayMinutes: number
    dayTemp: number
    nightMinutes: number
    nightTemp: number
}

export const SUNSET_DEFAULTS: SunsetSchedule = {
    dayMinutes: 7 * 60,
    dayTemp: 6000,
    nightMinutes: 20 * 60,
    nightTemp: 4000,
}

export const toClock = (minutes: number): string => {
    const m = ((Math.round(minutes / 30) * 30) % 1440 + 1440) % 1440
    return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`
}

export function readSchedule(): SunsetSchedule {
    try {
        const [ok, contents] = GLib.file_get_contents(CONFIG_PATH)
        if (!ok || !contents) return { ...SUNSET_DEFAULTS }
        const text = new TextDecoder().decode(contents)

        const profiles: { minutes: number; temp: number }[] = []
        for (const block of text.split("profile {").slice(1)) {
            const body = block.split("}")[0]
            const time = body.match(/time\s*=\s*(\d{1,2}):(\d{2})/)
            const temp = body.match(/temperature\s*=\s*(\d+)/)
            if (!time || !temp) continue
            profiles.push({
                minutes: parseInt(time[1]) * 60 + parseInt(time[2]),
                temp: parseInt(temp[1]),
            })
        }
        if (profiles.length < 2) return { ...SUNSET_DEFAULTS }

        // Day is the neutral (highest temperature) profile, night the warmest.
        // Keying off temperature rather than order survives a hand-reordered file.
        const byTemp = [...profiles].sort((a, b) => b.temp - a.temp)
        const day = byTemp[0]
        const night = byTemp[byTemp.length - 1]

        return {
            dayMinutes: day.minutes, dayTemp: day.temp,
            nightMinutes: night.minutes, nightTemp: night.temp,
        }
    } catch (e) {
        console.error("Failed to read hyprsunset config:", e)
        return { ...SUNSET_DEFAULTS }
    }
}

export function writeSchedule(s: SunsetSchedule): void {
    // gamma is deliberately omitted from the profiles: it is a multiplier here,
    // not a percentage, so "gamma = 100" is read as 10000% and the daemon exits.
    // Left out, it defaults to 100%.
    const config = `#
# Hyprsunset Configuration
# Night light: shifts display colour temperature on a clock-time schedule
#
# Reference: https://wiki.hyprland.org/Hypr-Ecosystem/hyprsunset/
#
# Profiles are keyed on wall-clock time, not real dusk. The daemon applies
# whichever profile is most recent, and switches on its own timer -- so a
# manual override via scripts/hyprland/nightlight.sh naturally expires at the
# next boundary below.
#
# Edited by the AGS settings panel (Power category), same as hypridle.conf.
#

max-gamma = 100

# Daytime: neutral, no colour shift
profile {
    time = ${toClock(s.dayMinutes)}
    temperature = ${s.dayTemp}
}

# Evening: warm
profile {
    time = ${toClock(s.nightMinutes)}
    temperature = ${s.nightTemp}
}
`
    try {
        const file = Gio.File.new_for_path(CONFIG_PATH)
        const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null)
        const bytes = new TextEncoder().encode(config)
        stream.write_bytes(new GLib.Bytes(bytes), null)
        stream.close(null)
        // hyprsunset has no config-reload request, so restart it. It applies the
        // profile matching the current time on startup.
        execAsync(["bash", "-c", "killall hyprsunset 2>/dev/null; hyprsunset &"]).catch(console.error)
    } catch (e) {
        console.error("Failed to write hyprsunset config:", e)
    }
}
