import { CategoryDef } from "../../lib/registry"
import { kwToggle, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { readTimeouts, writeTimeouts } from "../../lib/hypridle"
import { readSchedule, writeSchedule, toClock, SUNSET_DEFAULTS } from "../../lib/hyprsunset"

const fmtMin = (v: number) => {
    const m = Math.floor(v / 60), s = Math.round(v % 60)
    return s ? `${m}m${s}s` : `${m}m`
}

const Power: CategoryDef = {
    id: "power", label: "Power", group: "Hardware",
    icon: "battery-symbolic",
    description: "Idle timeouts, display power and night light",
    rows: () => [
        customRow({ id: "power.lock", title: "Lock Timeout", icon: "system-lock-screen-symbolic",
            description: "Idle time before hyprlock engages",
            control: () => SliderControl({ value: readTimeouts().lock, min: 60, max: 1800, step: 30,
                format: fmtMin, onChanged: v => writeTimeouts({ ...readTimeouts(), lock: Math.round(v) }) }),
            onReset: () => writeTimeouts({ ...readTimeouts(), lock: 180 }),
            resetVisible: () => readTimeouts().lock !== 180 }),
        customRow({ id: "power.dpms", title: "Screen Off Timeout", icon: "video-display-symbolic",
            description: "Idle time before displays power down",
            control: () => SliderControl({ value: readTimeouts().dpms, min: 120, max: 3600, step: 60,
                format: fmtMin, onChanged: v => writeTimeouts({ ...readTimeouts(), dpms: Math.round(v) }) }),
            onReset: () => writeTimeouts({ ...readTimeouts(), dpms: 600 }),
            resetVisible: () => readTimeouts().dpms !== 600 }),
        kwToggle({ id: "power.dpms-key", title: "Wake on Key Press", icon: "input-keyboard-symbolic",
            description: "Screens power on when a key is pressed", keyword: "misc:key_press_enables_dpms" }),
        kwToggle({ id: "power.dpms-mouse", title: "Wake on Mouse Move", icon: "input-mouse-symbolic",
            description: "Screens power on when the mouse moves", keyword: "misc:mouse_move_enables_dpms" }),
        // redshift-status-on rather than the more standard night-light-symbolic:
        // Papirus-Dark (pinned in gtk-3.0/settings.ini) ships the whole symbolic
        // status/ set with the *light* theme's #444444, so night-light-symbolic
        // renders invisible on the dark icon plate. Only the entries symlinked
        // into panel/ are correctly themed, and this is one of them.
        customRow({ id: "power.nightlight-temp", title: "Night Light Warmth", icon: "redshift-status-on-symbolic",
            description: "Colour temperature applied on the evening schedule",
            keywords: ["nightlight", "hyprsunset", "blue light", "temperature"],
            control: () => SliderControl({ value: readSchedule().nightTemp, min: 2000, max: 6000, step: 100,
                format: v => `${Math.round(v)}K`,
                onChanged: v => writeSchedule({ ...readSchedule(), nightTemp: Math.round(v) }) }),
            onReset: () => writeSchedule({ ...readSchedule(), nightTemp: SUNSET_DEFAULTS.nightTemp }),
            resetVisible: () => readSchedule().nightTemp !== SUNSET_DEFAULTS.nightTemp }),
        customRow({ id: "power.nightlight-start", title: "Night Light Starts", icon: "weather-clear-night-symbolic",
            description: "Time of day the warm profile takes over",
            keywords: ["nightlight", "hyprsunset", "sunset", "schedule"],
            control: () => SliderControl({ value: readSchedule().nightMinutes, min: 0, max: 1410, step: 30,
                format: toClock,
                onChanged: v => writeSchedule({ ...readSchedule(), nightMinutes: Math.round(v) }) }),
            onReset: () => writeSchedule({ ...readSchedule(), nightMinutes: SUNSET_DEFAULTS.nightMinutes }),
            resetVisible: () => readSchedule().nightMinutes !== SUNSET_DEFAULTS.nightMinutes }),
        customRow({ id: "power.nightlight-end", title: "Night Light Ends", icon: "weather-clear-symbolic",
            description: "Time of day the neutral profile takes over",
            keywords: ["nightlight", "hyprsunset", "sunrise", "schedule"],
            control: () => SliderControl({ value: readSchedule().dayMinutes, min: 0, max: 1410, step: 30,
                format: toClock,
                onChanged: v => writeSchedule({ ...readSchedule(), dayMinutes: Math.round(v) }) }),
            onReset: () => writeSchedule({ ...readSchedule(), dayMinutes: SUNSET_DEFAULTS.dayMinutes }),
            resetVisible: () => readSchedule().dayMinutes !== SUNSET_DEFAULTS.dayMinutes }),
    ],
}
export default Power
