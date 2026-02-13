import Gtk from "gi://Gtk?version=4.0"
import SettingsSlider from "../components/Slider"
import Dropdown from "../components/Dropdown"
import { readConfig, updateAndReload } from "../../lib/swaync"

export default function Notifications() {
    const config = readConfig()

    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Notifications" cssClasses={["category-title"]} xalign={0} />
            <label
                label="SwayNC notification daemon settings"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            <Dropdown
                label="Position X"
                options={["left", "center", "right"]}
                active={config["positionX"] || "right"}
                onChanged={(val) => updateAndReload("positionX", val)}
            />
            <Dropdown
                label="Position Y"
                options={["top", "bottom"]}
                active={config["positionY"] || "top"}
                onChanged={(val) => updateAndReload("positionY", val)}
            />
            <SettingsSlider
                label="Default Timeout (s)"
                value={config["timeout"] || 5}
                min={1}
                max={15}
                step={1}
                onChanged={(val) => updateAndReload("timeout", Math.round(val))}
            />
            <SettingsSlider
                label="Low Priority Timeout (s)"
                value={config["timeout-low"] || 3}
                min={1}
                max={10}
                step={1}
                onChanged={(val) => updateAndReload("timeout-low", Math.round(val))}
            />
            <SettingsSlider
                label="Notification Width"
                value={config["notification-window-width"] || 400}
                min={200}
                max={600}
                step={10}
                onChanged={(val) => updateAndReload("notification-window-width", Math.round(val))}
            />
            <SettingsSlider
                label="Control Center Width"
                value={config["control-center-width"] || 358}
                min={200}
                max={600}
                step={10}
                onChanged={(val) => updateAndReload("control-center-width", Math.round(val))}
            />
            <SettingsSlider
                label="Transition Time (ms)"
                value={config["transition-time"] || 100}
                min={0}
                max={500}
                step={25}
                onChanged={(val) => updateAndReload("transition-time", Math.round(val))}
            />
        </box>
    )
}
