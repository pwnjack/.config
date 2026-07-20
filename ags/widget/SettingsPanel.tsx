import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib"
import { execAsync } from "ags/process"
import CategoryNav from "./components/CategoryNav"
import SearchEntry from "./components/SearchEntry"
import ActionChip from "./components/ActionChip"
import { allCategories, searchRows, setCategories, setRefreshHandler } from "../lib/registry"
import { readOption } from "../lib/options"
import { CATEGORIES } from "./categories"

const HOME = GLib.get_home_dir()

function terminalExec(script: string) {
    const term = readOption("terminal") || "ghostty"
    execAsync(["hyprctl", "dispatch", "exec", `${term} -e ${script}`]).catch(console.error)
}

function categoryPage(catId: string): Gtk.Widget {
    const cat = allCategories().find(c => c.id === catId) ?? allCategories()[0]
    const page = new Gtk.Box({
        cssClasses: ["category-content"], orientation: Gtk.Orientation.VERTICAL, spacing: 6,
    })
    page.append(new Gtk.Label({ label: cat.label, cssClasses: ["category-title"], xalign: 0 }))
    page.append(new Gtk.Label({ label: cat.description, cssClasses: ["category-desc"], xalign: 0 }))
    page.append(new Gtk.Box({ cssClasses: ["content-separator"] }))
    for (const w of cat.extra?.() ?? []) page.append(w)
    for (const row of cat.rows()) page.append(row.build())
    return page
}

function resultsPage(query: string): Gtk.Widget {
    const page = new Gtk.Box({
        cssClasses: ["category-content"], orientation: Gtk.Orientation.VERTICAL, spacing: 6,
    })
    const matches = searchRows(query)
    page.append(new Gtk.Label({
        label: `Results for "${query}"`, cssClasses: ["category-title"], xalign: 0,
    }))
    page.append(new Gtk.Box({ cssClasses: ["content-separator"] }))
    if (matches.length === 0) {
        page.append(new Gtk.Label({ label: "No settings match.", cssClasses: ["results-empty"], xalign: 0 }))
    }
    for (const { cat, row } of matches) {
        const wrap = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL })
        wrap.append(new Gtk.Label({ label: cat.label, cssClasses: ["row-crumb"], xalign: 0 }))
        wrap.append(row.build())
        page.append(wrap)
    }
    return page
}

export default function SettingsPanel() {
    setCategories(CATEGORIES)

    let activeCategory = allCategories()[0].id
    let query = ""
    let searchWidget: Gtk.SearchEntry | null = null

    const scroll = new Gtk.ScrolledWindow({
        hscrollbarPolicy: Gtk.PolicyType.NEVER, vscrollbarPolicy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true, cssClasses: ["content-scroll"],
    })

    const render = () => {
        // Queries under 2 chars match nearly everything and each result row costs
        // a synchronous hyprctl read — treat them as no query.
        const q = query.trim().length >= 2 ? query : ""
        scroll.set_child(q ? resultsPage(q) : categoryPage(activeCategory))
    }
    setRefreshHandler(render)

    const sidebar = new Gtk.Box({
        cssClasses: ["category-nav"], orientation: Gtk.Orientation.VERTICAL, spacing: 2,
    })
    const rebuildSidebar = () => {
        let child = sidebar.get_first_child()
        while (child) { const next = child.get_next_sibling(); sidebar.remove(child); child = next }
        searchWidget = SearchEntry({ onChanged: q => { query = q; render() } })
        sidebar.append(searchWidget)
        sidebar.append(CategoryNav({
            active: activeCategory,
            onSelect: id => {
                activeCategory = id
                if (query) { query = ""; searchWidget?.set_text("") }
                render()
            },
        }))
    }

    const footer = new Gtk.Box({ cssClasses: ["panel-footer"], spacing: 8 })
    footer.append(ActionChip({ icon: "view-refresh-symbolic", label: "Reload Hyprland",
        onClicked: () => execAsync(["hyprctl", "reload"]).catch(console.error) }))
    footer.append(ActionChip({ icon: "media-playlist-repeat-symbolic", label: "Restart Waybar",
        onClicked: () => execAsync(["bash", `${HOME}/.config/scripts/waybar/waybar.sh`]).catch(console.error) }))
    footer.append(ActionChip({ icon: "software-update-available-symbolic", label: "Update System",
        onClicked: () => terminalExec(`${HOME}/.config/scripts/settings/update.sh`) }))
    footer.append(ActionChip({ icon: "utilities-terminal-symbolic", label: "Advanced (TUI)",
        onClicked: () => terminalExec(`${HOME}/.config/scripts/settings/settings.sh`) }))

    const content = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, hexpand: true, vexpand: true,
        cssClasses: ["content-area"],
    })
    content.append(scroll)
    content.append(footer)

    const layout = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, cssClasses: ["panel-layout"] })
    layout.append(sidebar)
    layout.append(content)

    const keyController = new Gtk.EventControllerKey()

    return (
        <window
            name="settings-panel"
            namespace="settings-panel"
            application={app}
            cssClasses={["settings-window"]}
            anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
            exclusivity={Astal.Exclusivity.NORMAL}
            layer={Astal.Layer.OVERLAY}
            keymode={Astal.Keymode.EXCLUSIVE}
            visible
            $={(self: Astal.Window) => {
                keyController.connect("key-pressed", (_c: Gtk.EventControllerKey, keyval: number) => {
                    if (keyval === Gdk.KEY_Escape) {
                        if (query) { query = ""; searchWidget?.set_text(""); render() }
                        else self.visible = false
                    }
                    return false
                })
                self.add_controller(keyController)
                // Freshness: rebuild everything each time the panel is shown
                self.connect("notify::visible", () => {
                    if (self.visible) { query = ""; rebuildSidebar(); render() }
                })
                rebuildSidebar()
                render()
            }}
        >
            <box cssClasses={["panel-backdrop"]} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER}>
                <box cssClasses={["panel-container"]} widthRequest={880} heightRequest={640}>
                    {layout}
                </box>
            </box>
        </window>
    )
}
