import { CategoryDef, requestRefresh } from "../../lib/registry"
import { kwDropdown, customRow } from "../components/rows"
import MonitorCard from "../components/MonitorCard"
import ActionChip from "../components/ActionChip"
import { listMonitors, getMainMonitor, setMainMonitor } from "../../lib/monitors"
import { readOption } from "../../lib/options"
import { execAsync } from "ags/process"
import GLib from "gi://GLib"

const HOME = GLib.get_home_dir()

const Monitors: CategoryDef = {
    id: "monitors", label: "Monitors", group: "Hardware",
    icon: "video-display-symbolic",
    description: "Connected displays and adaptive sync",
    extra: () => {
        const main = getMainMonitor()
        const cards = listMonitors().map(m => MonitorCard({
            monitor: m, isMain: m.name === main,
            onSetMain: () => { setMainMonitor(m.name); requestRefresh() },
        }))
        const term = readOption("terminal") || "ghostty"
        cards.push(ActionChip({
            icon: "utilities-terminal-symbolic", label: "Advanced setup (resolution, position, rotation)",
            onClicked: () => execAsync(["hyprctl", "dispatch", "exec",
                `${term} -e ${HOME}/.config/scripts/settings/advanced/monitor.sh`]).catch(console.error),
        }))
        return cards
    },
    rows: () => [
        kwDropdown({ id: "monitors.vrr", title: "VRR (Adaptive Sync)", icon: "video-display-symbolic",
            description: "Variable refresh rate", keyword: "misc:vrr",
            items: [
                { label: "Off", value: "0" }, { label: "On", value: "1" },
                { label: "Fullscreen only", value: "2" },
            ] }),
    ],
}
export default Monitors
