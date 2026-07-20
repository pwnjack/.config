import { CategoryDef } from "../../lib/registry"
import { customRow } from "../components/rows"
import { SliderControl, DropdownControl } from "../components/controls"
import { readConfig, updateAndReload, SWAYNC_DEFAULTS } from "../../lib/swaync"

function snSlider(id: string, title: string, icon: string, desc: string, key: string,
    min: number, max: number, step: number) {
    return customRow({
        id, title, icon, description: desc,
        control: () => SliderControl({
            value: Number(readConfig()[key] ?? SWAYNC_DEFAULTS[key]),
            min, max, step, onChanged: v => updateAndReload(key, Math.round(v)),
        }),
        onReset: () => updateAndReload(key, SWAYNC_DEFAULTS[key]),
        resetVisible: () => readConfig()[key] !== undefined
            && readConfig()[key] !== SWAYNC_DEFAULTS[key],
    })
}

const Notifications: CategoryDef = {
    id: "notifications", label: "Notifications", group: "Behavior",
    icon: "preferences-system-notifications-symbolic",
    description: "SwayNC toasts and control center",
    rows: () => [
        customRow({ id: "notif.pos-x", title: "Position X", icon: "object-flip-horizontal-symbolic",
            description: "Horizontal screen edge for toasts",
            control: () => DropdownControl({
                items: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }],
                active: String(readConfig()["positionX"] ?? SWAYNC_DEFAULTS["positionX"]),
                onChanged: v => updateAndReload("positionX", v),
            }) }),
        customRow({ id: "notif.pos-y", title: "Position Y", icon: "object-flip-vertical-symbolic",
            description: "Vertical screen edge for toasts",
            control: () => DropdownControl({
                items: [{ label: "Top", value: "top" }, { label: "Bottom", value: "bottom" }],
                active: String(readConfig()["positionY"] ?? SWAYNC_DEFAULTS["positionY"]),
                onChanged: v => updateAndReload("positionY", v),
            }) }),
        snSlider("notif.timeout", "Default Timeout", "alarm-symbolic",
            "Seconds a toast stays on screen", "timeout", 1, 15, 1),
        snSlider("notif.timeout-low", "Low Priority Timeout", "alarm-symbolic",
            "Seconds for low-priority toasts", "timeout-low", 1, 10, 1),
        snSlider("notif.width", "Notification Width", "object-flip-horizontal-symbolic",
            "Toast width in pixels", "notification-window-width", 200, 600, 10),
        snSlider("notif.cc-width", "Control Center Width", "sidebar-show-symbolic",
            "Sidebar width in pixels", "control-center-width", 200, 600, 10),
        snSlider("notif.transition", "Transition Time", "media-playback-start-symbolic",
            "Animation duration in ms", "transition-time", 0, 500, 25),
    ],
}
export default Notifications
