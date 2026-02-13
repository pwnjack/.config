import Gtk from "gi://Gtk?version=4.0"
import Toggle from "../components/Toggle"
import Dropdown from "../components/Dropdown"
import { setKeyword, getOptionBool } from "../../lib/hyprctl"
import GLib from "gi://GLib"

function getLayout(): string {
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl getoption general:layout -j")
        if (!ok || !stdout) return "dwindle"
        const json = JSON.parse(new TextDecoder().decode(stdout))
        return json.str?.trim() || "dwindle"
    } catch {
        return "dwindle"
    }
}

export default function Layout() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Layout" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Window tiling and layout behavior"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            <Dropdown
                label="Layout Mode"
                options={["dwindle", "master"]}
                active={getLayout()}
                onChanged={(val) => setKeyword("general:layout", val)}
            />
            <Toggle
                label="Pseudotile"
                active={getOptionBool("dwindle:pseudotile")}
                onToggled={(v) => setKeyword("dwindle:pseudotile", v)}
            />
            <Toggle
                label="Preserve Split"
                active={getOptionBool("dwindle:preserve_split")}
                onToggled={(v) => setKeyword("dwindle:preserve_split", v)}
            />
            <Toggle
                label="Smart Split"
                active={getOptionBool("dwindle:smart_split")}
                onToggled={(v) => setKeyword("dwindle:smart_split", v)}
            />
            <Toggle
                label="Allow Tearing"
                active={getOptionBool("general:allow_tearing")}
                onToggled={(v) => setKeyword("general:allow_tearing", v)}
            />
        </box>
    )
}
