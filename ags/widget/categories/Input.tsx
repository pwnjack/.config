import Gtk from "gi://Gtk?version=4.0"
import Toggle from "../components/Toggle"
import SettingsSlider from "../components/Slider"
import Dropdown from "../components/Dropdown"
import { setKeyword, getOptionBool, getOptionInt, getOptionFloat } from "../../lib/hyprctl"

export default function Input() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Input" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Mouse, keyboard, and touchpad settings"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            <SettingsSlider
                label="Mouse Sensitivity"
                value={getOptionFloat("input:sensitivity")}
                min={-1.0}
                max={1.0}
                step={0.1}
                onChanged={(val) => setKeyword("input:sensitivity", val)}
            />
            <Dropdown
                label="Follow Mouse"
                options={["0", "1", "2", "3"]}
                active={String(getOptionInt("input:follow_mouse"))}
                onChanged={(val) => setKeyword("input:follow_mouse", parseInt(val))}
            />
            <Toggle
                label="Numlock by Default"
                active={getOptionBool("input:numlock_by_default")}
                onToggled={(v) => setKeyword("input:numlock_by_default", v)}
            />
            <Toggle
                label="Natural Scroll (Touchpad)"
                active={getOptionBool("input:touchpad:natural_scroll")}
                onToggled={(v) => setKeyword("input:touchpad:natural_scroll", v)}
            />
            <SettingsSlider
                label="Touchpad Scroll Factor"
                value={getOptionFloat("input:touchpad:scroll_factor")}
                min={0.1}
                max={2.0}
                step={0.1}
                onChanged={(val) => setKeyword("input:touchpad:scroll_factor", val)}
            />
            <Toggle
                label="Resize on Border"
                active={getOptionBool("general:resize_on_border")}
                onToggled={(v) => setKeyword("general:resize_on_border", v)}
            />
        </box>
    )
}
