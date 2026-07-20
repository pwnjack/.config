import Gtk from "gi://Gtk?version=4.0"

export interface SettingRowProps {
    icon: string
    title: string
    description: string
    control: Gtk.Widget
    onReset?: () => void
    resetVisible?: boolean
}

export default function SettingRow(p: SettingRowProps): Gtk.Widget {
    const row = new Gtk.Box({ cssClasses: ["setting-row"], spacing: 12 })

    const plate = new Gtk.Box({ cssClasses: ["row-icon"], valign: Gtk.Align.CENTER })
    plate.append(new Gtk.Image({ iconName: p.icon }))
    row.append(plate)

    const text = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, hexpand: true, valign: Gtk.Align.CENTER,
    })
    text.append(new Gtk.Label({ label: p.title, xalign: 0, cssClasses: ["row-title"] }))
    text.append(new Gtk.Label({
        label: p.description, xalign: 0, cssClasses: ["row-desc"], wrap: true,
    }))
    row.append(text)

    if (p.onReset) {
        const reset = new Gtk.Button({
            iconName: "edit-undo-symbolic", cssClasses: ["reset-btn"],
            valign: Gtk.Align.CENTER, tooltipText: "Reset to default",
            visible: p.resetVisible ?? false,
        })
        reset.connect("clicked", () => p.onReset!())
        row.append(reset)
    }
    row.append(p.control)
    return row
}
