import { CategoryDef } from "../../lib/registry"
import { kwToggle, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { setAnimationPersistent, hasAnimationOverride, resetAnimation } from "../../lib/persist"
import GLib from "gi://GLib"

interface AnimState { enabled: boolean; speed: number; bezier: string; style: string }

function readAnimTree(): Map<string, AnimState> {
    const map = new Map<string, AnimState>()
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl animations -j")
        if (ok && stdout) {
            const anims = JSON.parse(new TextDecoder().decode(stdout))
            // hyprctl animations -j returns [animations[], beziers[]]
            const list = Array.isArray(anims[0]) ? anims[0] : anims
            for (const a of list) map.set(a.name, {
                enabled: !!a.enabled, speed: a.speed || 5,
                bezier: a.bezier || "default", style: a.style || "",
            })
        }
    } catch (e) { console.error(e) }
    return map
}

function setSpeed(a: AnimState, name: string, speed: number) {
    const base = `${name},${a.enabled ? 1 : 0},${Math.round(speed)},${a.bezier}`
    setAnimationPersistent(name, a.style ? `${base},${a.style}` : base)
}

const ANIMS: { label: string; name: string; desc: string }[] = [
    { label: "Windows", name: "windows", desc: "Open/close scale animation" },
    { label: "Windows In", name: "windowsIn", desc: "Window opening" },
    { label: "Windows Out", name: "windowsOut", desc: "Window closing" },
    { label: "Windows Move", name: "windowsMove", desc: "Drag and tile movement" },
    { label: "Fade", name: "fade", desc: "Opacity transitions" },
    { label: "Workspaces", name: "workspaces", desc: "Workspace switch slide" },
    { label: "Border", name: "border", desc: "Border color transitions" },
]

const Animations: CategoryDef = {
    id: "animations", label: "Animations", group: "Look & Feel",
    icon: "starred-symbolic",
    description: "Master switch and per-animation speeds",
    rows: () => {
        const tree = readAnimTree()
        const fallback: AnimState = { enabled: true, speed: 5, bezier: "default", style: "" }
        return [
            kwToggle({ id: "anim.master", title: "Animations", icon: "starred-symbolic",
                description: "Master switch for all animations", keyword: "animations:enabled" }),
            ...ANIMS.map(a => {
                const state = tree.get(a.name) ?? fallback
                return customRow({
                    id: `anim.${a.name}`, title: a.label, icon: "media-playback-start-symbolic",
                    description: a.desc,
                    control: () => SliderControl({ value: state.speed, min: 1, max: 10, step: 1,
                        onChanged: v => setSpeed(state, a.name, v) }),
                    onReset: () => resetAnimation(a.name),
                    resetVisible: () => hasAnimationOverride(a.name),
                })
            }),
        ]
    },
}
export default Animations
