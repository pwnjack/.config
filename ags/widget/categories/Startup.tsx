import { CategoryDef } from "../../lib/registry"
import { optionToggle } from "../components/rows"
import { execAsync } from "ags/process"

const Startup: CategoryDef = {
    id: "startup", label: "Startup", group: "System",
    icon: "system-restart-symbolic",
    description: "What happens when Hyprland starts",
    rows: () => [
        optionToggle({ id: "startup.autologin", title: "Lock on Autologin", icon: "system-lock-screen-symbolic",
            description: "Run hyprlock at startup when logged in automatically", option: "autologin" }),
        optionToggle({ id: "startup.clock", title: "Desktop Clock", icon: "preferences-system-time-symbolic",
            description: "eww clock widget on the desktop", option: "clock",
            onChange: v => {
                if (v) execAsync(["bash", "-c", "command -v eww >/dev/null && eww open clock"]).catch(console.error)
                // pkill terminates the whole eww daemon — fine while the clock is the only eww widget
                else execAsync(["bash", "-c", "pkill eww"]).catch(console.error)
            } }),
        optionToggle({ id: "startup.randomwallpaper", title: "Random Wallpaper", icon: "preferences-desktop-wallpaper-symbolic",
            description: "Pick a random wallpaper (and palette) on each login", option: "randomwallpaper",
            keywords: ["waypaper", "pywal"] }),
    ],
}
export default Startup
