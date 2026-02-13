import Gtk from "gi://Gtk?version=4.0"
import SettingsSlider from "../components/Slider"
import { setKeyword, getOptionInt, getOptionFloat } from "../../lib/hyprctl"

interface SliderItem {
    label: string
    keyword: string
    min: number
    max: number
    step: number
    isFloat?: boolean
}

const SLIDERS: SliderItem[] = [
    { label: "Gaps Inner", keyword: "general:gaps_in", min: 0, max: 20, step: 1 },
    { label: "Gaps Outer", keyword: "general:gaps_out", min: 0, max: 30, step: 1 },
    { label: "Border Width", keyword: "general:border_size", min: 0, max: 5, step: 1 },
    { label: "Corner Rounding", keyword: "decoration:rounding", min: 0, max: 30, step: 1 },
    { label: "Blur Size", keyword: "decoration:blur:size", min: 1, max: 20, step: 1 },
    { label: "Blur Passes", keyword: "decoration:blur:passes", min: 1, max: 6, step: 1 },
    { label: "Active Opacity", keyword: "decoration:active_opacity", min: 0.1, max: 1.0, step: 0.05, isFloat: true },
    { label: "Inactive Opacity", keyword: "decoration:inactive_opacity", min: 0.1, max: 1.0, step: 0.05, isFloat: true },
]

export default function Appearance() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Appearance" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Adjust visual settings with live preview"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            {SLIDERS.map(item => (
                <SettingsSlider
                    label={item.label}
                    value={item.isFloat ? getOptionFloat(item.keyword) : getOptionInt(item.keyword)}
                    min={item.min}
                    max={item.max}
                    step={item.step}
                    onChanged={(val) => setKeyword(item.keyword, val)}
                />
            ))}
        </box>
    )
}
