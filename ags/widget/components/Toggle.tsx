import Gtk from "gi://Gtk?version=4.0"

interface ToggleProps {
    label: string
    active: boolean
    onToggled: (active: boolean) => void
}

export default function Toggle({ label, active, onToggled }: ToggleProps) {
    return (
        <box cssClasses={["toggle-row"]} spacing={12}>
            <label
                label={label}
                hexpand
                xalign={0}
                cssClasses={["toggle-label"]}
            />
            <switch
                active={active}
                valign={Gtk.Align.CENTER}
                onStateSet={(_self: Gtk.Switch, state: boolean) => {
                    onToggled(state)
                    return false
                }}
            />
        </box>
    )
}
