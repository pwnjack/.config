import Gtk from "gi://Gtk?version=4.0"

export default function ActionChip(p: { icon: string; label: string; onClicked: () => void }): Gtk.Widget {
    const btn = new Gtk.Button({ cssClasses: ["action-chip"], valign: Gtk.Align.CENTER, halign: Gtk.Align.START })
    const box = new Gtk.Box({ spacing: 6 })
    box.append(new Gtk.Image({ iconName: p.icon }))
    box.append(new Gtk.Label({ label: p.label }))
    btn.set_child(box)
    btn.connect("clicked", p.onClicked)
    return btn
}
