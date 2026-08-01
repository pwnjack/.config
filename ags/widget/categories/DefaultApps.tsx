import { CategoryDef } from "../../lib/registry"
import { optionEntry, customRow } from "../components/rows"
import { DropdownControl } from "../components/controls"
import { readOption, writeOption } from "../../lib/options"

const DefaultApps: CategoryDef = {
    id: "apps", label: "Default Apps", group: "System",
    icon: "system-run-symbolic",
    description: "Applications used by keybinds and scripts",
    rows: () => [
        optionEntry({ id: "apps.browser", title: "Browser", icon: "web-browser-symbolic",
            description: "Launched with Super+B", option: "browser", placeholder: "firefox" }),
        optionEntry({ id: "apps.terminal", title: "Terminal", icon: "utilities-terminal-symbolic",
            description: "Launched with Super+Return", option: "terminal", placeholder: "ghostty" }),
        optionEntry({ id: "apps.editor", title: "TUI Editor", icon: "accessories-text-editor-symbolic",
            description: "Used by Super+N and the TUI settings", option: "editor", placeholder: "nvim" }),
        customRow({ id: "apps.launcher", title: "Launcher Style", icon: "view-app-grid-symbolic",
            description: "Rofi layout used by Super+Space",
            control: () => DropdownControl({
                items: [{ label: "Vertical", value: "vertical" }, { label: "Horizontal", value: "horizontal" }],
                active: readOption("launchertype") || "vertical",
                onChanged: v => writeOption("launchertype", v),
            }) }),
    ],
}
export default DefaultApps
