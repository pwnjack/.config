import Gtk from "gi://Gtk?version=4.0"
import { MonitorInfo } from "../../lib/monitors"

export default function MonitorCard(p: { monitor: MonitorInfo; isMain: boolean; onSetMain: () => void }): Gtk.Widget {
    const card = new Gtk.Box({
        cssClasses: ["monitor-card"], orientation: Gtk.Orientation.VERTICAL, spacing: 4,
    })
    const head = new Gtk.Box({ spacing: 8 })
    head.append(new Gtk.Image({ iconName: "video-display-symbolic" }))
    head.append(new Gtk.Label({ label: p.monitor.name, cssClasses: ["monitor-name"], xalign: 0, hexpand: true }))
    if (p.isMain) {
        head.append(new Gtk.Label({ label: "MAIN", cssClasses: ["monitor-main-badge"] }))
    } else {
        const btn = new Gtk.Button({ label: "Set as main", cssClasses: ["monitor-set-main"] })
        btn.connect("clicked", p.onSetMain)
        head.append(btn)
    }
    card.append(head)
    const m = p.monitor
    card.append(new Gtk.Label({
        label: `${m.model}   ${m.width}x${m.height}@${Math.round(m.refreshRate)}Hz   scale ${m.scale}   at ${m.x},${m.y}`,
        cssClasses: ["monitor-detail"], xalign: 0,
    }))
    return card
}
