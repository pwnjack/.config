import Gtk from "gi://Gtk?version=4.0"
import SettingRow from "./SettingRow"
import { ToggleControl, SliderControl, DropdownControl, EntryControl, DropdownItem } from "./controls"
import { getOptionBool, getOptionInt, getOptionFloat, getOption } from "../../lib/hyprctl"
import { setPersistent, resetSetting, hasOverride } from "../../lib/persist"
import { readOption, writeOption } from "../../lib/options"
import { RowSpec, requestRefresh } from "../../lib/registry"

interface Base { id: string; title: string; description: string; icon: string; keywords?: string[] }

const resetProps = (keyword: string) => ({
    onReset: () => { resetSetting(keyword); requestRefresh() },
    resetVisible: hasOverride(keyword),
})

export function kwToggle(b: Base & { keyword: string }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: ToggleControl({
            active: getOptionBool(b.keyword),
            onToggled: v => setPersistent(b.keyword, v),
        }),
        ...resetProps(b.keyword),
    }) }
}

export function kwSlider(b: Base & {
    keyword: string; min: number; max: number; step: number
    float?: boolean; format?: (v: number) => string
}): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: SliderControl({
            value: b.float ? getOptionFloat(b.keyword) : getOptionInt(b.keyword),
            min: b.min, max: b.max, step: b.step, format: b.format,
            onChanged: v => setPersistent(b.keyword, b.float ? v : Math.round(v)),
        }),
        ...resetProps(b.keyword),
    }) }
}

export function kwDropdown(b: Base & { keyword: string; items: DropdownItem[] }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: DropdownControl({
            items: b.items, active: getOption(b.keyword),
            onChanged: v => setPersistent(b.keyword, v),
        }),
        ...resetProps(b.keyword),
    }) }
}

/** options/<name> free-text entry (persists by nature; no reset). */
export function optionEntry(b: Base & { option: string; placeholder?: string; onCommit?: (v: string) => void }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: EntryControl({
            text: readOption(b.option), placeholder: b.placeholder,
            onCommit: v => { writeOption(b.option, v); b.onCommit?.(v) },
        }),
    }) }
}

/** options/<name> enabled/disabled toggle with optional side effects. */
export function optionToggle(b: Base & { option: string; onChange?: (enabled: boolean) => void }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: ToggleControl({
            active: readOption(b.option) === "enabled",
            onToggled: v => { writeOption(b.option, v ? "enabled" : "disabled"); b.onChange?.(v) },
        }),
    }) }
}

/** Fully custom control row (swaync, hypridle, animations, monitors). */
export function customRow(b: Base & {
    control: () => Gtk.Widget
    onReset?: () => void; resetVisible?: () => boolean
}): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: b.control(),
        onReset: b.onReset ? () => { b.onReset!(); requestRefresh() } : undefined,
        resetVisible: b.resetVisible?.() ?? false,
    }) }
}
