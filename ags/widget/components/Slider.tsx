import Gtk from "gi://Gtk?version=4.0"

interface SliderProps {
    label: string
    value: number
    min: number
    max: number
    step: number
    onChanged: (value: number) => void
}

export default function SettingsSlider({ label, value, min, max, step, onChanged }: SliderProps) {
    let debounceTimer: number | null = null

    return (
        <box cssClasses={["slider-row"]} orientation={Gtk.Orientation.VERTICAL} spacing={4}>
            <box spacing={8}>
                <label
                    label={label}
                    hexpand
                    xalign={0}
                    cssClasses={["slider-label"]}
                />
                <label
                    label={String(value)}
                    cssClasses={["slider-value"]}
                    widthChars={4}
                    xalign={1}
                />
            </box>
            <slider
                widthRequest={300}
                drawValue={false}
                cssClasses={["settings-scale"]}
                min={min}
                max={max}
                step={step}
                value={value}
                $={(self: Gtk.Scale) => {
                    // Remove built-in scroll controllers so wheel scrolls the panel instead
                    const controllers = self.observe_controllers()
                    for (let i = 0; i < controllers.get_n_items(); i++) {
                        const ctrl = controllers.get_item(i)
                        if (ctrl instanceof Gtk.EventControllerScroll) {
                            self.remove_controller(ctrl)
                        }
                    }
                }}
                onChangeValue={(self) => {
                    const val = Math.round(self.value * 100) / 100
                    // Update the value label
                    const parent = self.get_parent() as Gtk.Box
                    if (parent) {
                        const headerBox = parent.get_first_child() as Gtk.Box
                        if (headerBox) {
                            let child = headerBox.get_first_child()
                            while (child) {
                                if (child instanceof Gtk.Label && child.cssClasses.includes("slider-value")) {
                                    child.label = String(val)
                                    break
                                }
                                child = child.get_next_sibling()
                            }
                        }
                    }
                    // Debounce hyprctl calls
                    if (debounceTimer) clearTimeout(debounceTimer)
                    debounceTimer = setTimeout(() => onChanged(val), 100) as unknown as number
                }}
            />
        </box>
    )
}
