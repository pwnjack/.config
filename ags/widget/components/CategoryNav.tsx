import Gtk from "gi://Gtk?version=4.0"
import { allCategories } from "../../lib/registry"

const GROUP_ORDER = ["Look & Feel", "Behavior", "Hardware", "System"] as const

export default function CategoryNav(p: { active: string; onSelect: (id: string) => void }): Gtk.Widget {
    const buttons = new Map<string, Gtk.Button>()
    const nav = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 2 })
    const setActive = (id: string) => {
        buttons.forEach((btn, catId) =>
            btn.set_css_classes(catId === id ? ["nav-button", "nav-active"] : ["nav-button"]))
        p.onSelect(id)
    }
    for (const group of GROUP_ORDER) {
        const cats = allCategories().filter(c => c.group === group)
        if (cats.length === 0) continue
        nav.append(new Gtk.Label({ label: group.toUpperCase(), cssClasses: ["nav-section"], xalign: 0 }))
        for (const cat of cats) {
            const btn = new Gtk.Button({
                cssClasses: cat.id === p.active ? ["nav-button", "nav-active"] : ["nav-button"],
            })
            const box = new Gtk.Box({ spacing: 8 })
            box.append(new Gtk.Image({ iconName: cat.icon }))
            box.append(new Gtk.Label({ label: cat.label }))
            btn.set_child(box)
            btn.connect("clicked", () => setActive(cat.id))
            buttons.set(cat.id, btn)
            nav.append(btn)
        }
    }
    return nav
}
