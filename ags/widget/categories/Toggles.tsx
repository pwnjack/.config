import Gtk from "gi://Gtk?version=4.0"
import Toggle from "../components/Toggle"
import { setKeyword, getOptionBool } from "../../lib/hyprctl"

interface ToggleItem {
    label: string
    keyword: string
}

const TOGGLES: ToggleItem[] = [
    { label: "Blur", keyword: "decoration:blur:enabled" },
    { label: "Animations", keyword: "animations:enabled" },
    { label: "Shadows", keyword: "decoration:shadow:enabled" },
    { label: "XWayland", keyword: "xwayland:enabled" },
]

export default function Toggles() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Toggles" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Enable or disable Hyprland features"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            {TOGGLES.map(item => (
                <Toggle
                    label={item.label}
                    active={getOptionBool(item.keyword)}
                    onToggled={(active) => setKeyword(item.keyword, active)}
                />
            ))}
        </box>
    )
}
