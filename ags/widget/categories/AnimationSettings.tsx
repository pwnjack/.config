import Gtk from "gi://Gtk?version=4.0"
import SettingsSlider from "../components/Slider"
import { execAsync } from "ags/process"
import GLib from "gi://GLib"

function getAnimSpeed(name: string): number {
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl animations -j")
        if (!ok || !stdout) return 5
        const anims = JSON.parse(new TextDecoder().decode(stdout))
        for (const anim of anims) {
            if (anim.name === name) return anim.speed || 5
        }
    } catch { /* ignore */ }
    return 5
}

function setAnimSpeed(name: string, speed: number): void {
    // Read current animation config to preserve bezier and style
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl animations -j")
        if (!ok || !stdout) return
        const anims = JSON.parse(new TextDecoder().decode(stdout))
        for (const anim of anims) {
            if (anim.name === name) {
                const enabled = anim.enabled ? "1" : "0"
                const bezier = anim.bezier || "default"
                const style = anim.style || ""
                const cmd = style
                    ? `hyprctl keyword animation ${name},${enabled},${Math.round(speed)},${bezier},${style}`
                    : `hyprctl keyword animation ${name},${enabled},${Math.round(speed)},${bezier}`
                execAsync(["bash", "-c", cmd]).catch(console.error)
                return
            }
        }
    } catch { /* ignore */ }
}

interface AnimItem {
    label: string
    name: string
    defaultSpeed: number
}

const ANIMATIONS: AnimItem[] = [
    { label: "Windows", name: "windows", defaultSpeed: 6 },
    { label: "Windows In", name: "windowsIn", defaultSpeed: 6 },
    { label: "Windows Out", name: "windowsOut", defaultSpeed: 5 },
    { label: "Windows Move", name: "windowsMove", defaultSpeed: 5 },
    { label: "Fade", name: "fade", defaultSpeed: 10 },
    { label: "Workspaces", name: "workspaces", defaultSpeed: 5 },
    { label: "Border", name: "border", defaultSpeed: 1 },
]

export default function AnimationSettings() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Animations" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Animation speed for window and workspace transitions"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            {ANIMATIONS.map(item => (
                <SettingsSlider
                    label={item.label}
                    value={getAnimSpeed(item.name)}
                    min={1}
                    max={10}
                    step={1}
                    onChanged={(val) => setAnimSpeed(item.name, val)}
                />
            ))}
        </box>
    )
}
