import Gtk from "gi://Gtk?version=4.0"

interface DropdownProps {
    label: string
    options: string[]
    active: string
    onChanged: (value: string) => void
}

export default function Dropdown({ label, options, active, onChanged }: DropdownProps) {
    const dropdown = new Gtk.DropDown({
        model: Gtk.StringList.new(options),
        valign: Gtk.Align.CENTER,
        cssClasses: ["settings-dropdown"],
    })

    const activeIndex = options.indexOf(active)
    if (activeIndex >= 0) dropdown.set_selected(activeIndex)

    dropdown.connect("notify::selected", () => {
        const idx = dropdown.get_selected()
        if (idx < options.length) {
            onChanged(options[idx])
        }
    })

    return (
        <box cssClasses={["dropdown-row"]} spacing={12}>
            <label
                label={label}
                hexpand
                xalign={0}
                cssClasses={["dropdown-label"]}
            />
            {dropdown}
        </box>
    )
}
