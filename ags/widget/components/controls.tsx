import Gtk from "gi://Gtk?version=4.0"

export function ToggleControl(p: { active: boolean; onToggled: (v: boolean) => void }): Gtk.Widget {
    const sw = new Gtk.Switch({ active: p.active, valign: Gtk.Align.CENTER })
    sw.connect("state-set", (_s: Gtk.Switch, state: boolean) => { p.onToggled(state); return false })
    return sw
}

export interface SliderControlProps {
    value: number; min: number; max: number; step: number
    format?: (v: number) => string
    onChanged: (v: number) => void
}

export function SliderControl(p: SliderControlProps): Gtk.Widget {
    let debounce: ReturnType<typeof setTimeout> | null = null
    const fmt = p.format ?? ((v: number) => String(v))
    const valueLabel = new Gtk.Label({
        label: fmt(p.value), cssClasses: ["slider-value"], widthChars: 6, xalign: 1,
    })
    const scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, p.min, p.max, p.step)
    scale.set_value(p.value)
    scale.set_draw_value(false)
    scale.set_size_request(180, -1)
    scale.add_css_class("settings-scale")
    scale.set_valign(Gtk.Align.CENTER)
    // Wheel must scroll the panel, not the slider
    const ctrls = scale.observe_controllers()
    const toRemove: Gtk.EventController[] = []
    for (let i = 0; i < ctrls.get_n_items(); i++) {
        const c = ctrls.get_item(i)
        if (c instanceof Gtk.EventControllerScroll) toRemove.push(c)
    }
    for (const c of toRemove) scale.remove_controller(c)
    scale.connect("value-changed", () => {
        const val = Math.round(scale.get_value() * 100) / 100
        valueLabel.label = fmt(val)                     // same closure — no tree walking
        if (debounce) clearTimeout(debounce)
        debounce = setTimeout(() => p.onChanged(val), 150)
    })
    const box = new Gtk.Box({ spacing: 8, valign: Gtk.Align.CENTER })
    box.append(scale); box.append(valueLabel)
    return box
}

export interface DropdownItem { label: string; value: string }

export function DropdownControl(p: { items: DropdownItem[]; active: string; onChanged: (value: string) => void }): Gtk.Widget {
    const dd = new Gtk.DropDown({
        model: Gtk.StringList.new(p.items.map(i => i.label)),
        valign: Gtk.Align.CENTER, cssClasses: ["settings-dropdown"],
    })
    const idx = p.items.findIndex(i => i.value === p.active)
    if (idx >= 0) dd.set_selected(idx)
    dd.connect("notify::selected", () => {
        const i = dd.get_selected()
        if (i < p.items.length && p.items[i].value !== p.active) p.onChanged(p.items[i].value)
    })
    return dd
}

export function EntryControl(p: { text: string; placeholder?: string; onCommit: (text: string) => void }): Gtk.Widget {
    let last = p.text
    const commit = () => {
        const text = entry.get_text()
        if (text === last) return
        last = text
        p.onCommit(text)
    }
    const entry = new Gtk.Entry({
        text: p.text, hexpand: false, widthChars: 18,
        placeholderText: p.placeholder ?? "", cssClasses: ["app-entry"],
        valign: Gtk.Align.CENTER,
    })
    entry.connect("activate", commit)
    const focus = new Gtk.EventControllerFocus()
    focus.connect("leave", commit)
    entry.add_controller(focus)
    return entry
}
