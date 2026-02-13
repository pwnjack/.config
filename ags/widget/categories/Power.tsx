import Gtk from "gi://Gtk?version=4.0"
import Toggle from "../components/Toggle"
import SettingsSlider from "../components/Slider"
import Dropdown from "../components/Dropdown"
import { setKeyword, getOptionBool, getOptionInt } from "../../lib/hyprctl"
import { readTimeouts, writeTimeouts } from "../../lib/hypridle"

function formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return s > 0 ? `${m}m ${s}s` : `${m}m`
}

export default function Power() {
    const timeouts = readTimeouts()

    const vrrValue = getOptionInt("misc:vrr")
    const vrrOptions = ["off", "on", "fullscreen only"]
    const vrrActive = vrrOptions[vrrValue] || "off"

    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Power" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Idle timeouts, DPMS, and adaptive sync"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            <SettingsSlider
                label={`Lock Timeout (${formatTime(timeouts.lock)})`}
                value={timeouts.lock}
                min={60}
                max={1800}
                step={30}
                onChanged={(val) => writeTimeouts({ ...timeouts, lock: Math.round(val) })}
            />
            <SettingsSlider
                label={`Screen Off Timeout (${formatTime(timeouts.dpms)})`}
                value={timeouts.dpms}
                min={120}
                max={3600}
                step={60}
                onChanged={(val) => writeTimeouts({ ...timeouts, dpms: Math.round(val) })}
            />
            <Dropdown
                label="VRR (Adaptive Sync)"
                options={["off", "on", "fullscreen only"]}
                active={vrrActive}
                onChanged={(val) => {
                    const idx = vrrOptions.indexOf(val)
                    setKeyword("misc:vrr", idx >= 0 ? idx : 0)
                }}
            />
            <Toggle
                label="DPMS on Key Press"
                active={getOptionBool("misc:key_press_enables_dpms")}
                onToggled={(v) => setKeyword("misc:key_press_enables_dpms", v)}
            />
            <Toggle
                label="DPMS on Mouse Move"
                active={getOptionBool("misc:mouse_move_enables_dpms")}
                onToggled={(v) => setKeyword("misc:mouse_move_enables_dpms", v)}
            />
        </box>
    )
}
