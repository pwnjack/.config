import { CategoryDef } from "../../lib/registry"
import { kwToggle, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { readTimeouts, writeTimeouts } from "../../lib/hypridle"

const fmtMin = (v: number) => {
    const m = Math.floor(v / 60), s = Math.round(v % 60)
    return s ? `${m}m${s}s` : `${m}m`
}

const Power: CategoryDef = {
    id: "power", label: "Power", group: "Hardware",
    icon: "battery-symbolic",
    description: "Idle timeouts and display power",
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
    ],
}
export default Power
