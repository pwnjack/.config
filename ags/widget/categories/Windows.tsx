import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwDropdown } from "../components/rows"

const Windows: CategoryDef = {
    id: "windows", label: "Windows", group: "Behavior",
    icon: "view-grid-symbolic",
    description: "Tiling layout and window behavior",
    rows: () => [
        kwDropdown({ id: "win.layout", title: "Layout Mode", icon: "view-grid-symbolic",
            description: "Dwindle splits like a binary tree; master keeps one main window",
            keyword: "general:layout",
            items: [{ label: "Dwindle", value: "dwindle" }, { label: "Master", value: "master" }] }),
        kwToggle({ id: "win.preserve-split", title: "Preserve Split", icon: "object-flip-horizontal-symbolic",
            description: "Keep split direction when windows close", keyword: "dwindle:preserve_split" }),
        kwToggle({ id: "win.smart-split", title: "Smart Split", icon: "object-rotate-right-symbolic",
            description: "Split direction follows cursor position", keyword: "dwindle:smart_split" }),
        kwToggle({ id: "win.tearing", title: "Allow Tearing", icon: "video-display-symbolic",
            description: "Reduces latency in games; may cause glitches", keyword: "general:allow_tearing" }),
        kwToggle({ id: "win.resize-border", title: "Resize on Border", icon: "view-restore-symbolic",
            description: "Drag window edges to resize", keyword: "general:resize_on_border" }),
        kwToggle({ id: "win.xwayland", title: "XWayland", icon: "application-x-executable-symbolic",
            description: "Support for X11-only applications", keyword: "xwayland:enabled" }),
    ],
}
export default Windows
