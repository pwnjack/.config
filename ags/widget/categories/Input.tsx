import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwSlider, kwDropdown } from "../components/rows"

const Input: CategoryDef = {
    id: "input", label: "Input", group: "Behavior",
    icon: "input-mouse-symbolic",
    description: "Mouse, keyboard and touchpad",
    rows: () => [
        kwSlider({ id: "input.sensitivity", title: "Mouse Sensitivity", icon: "input-mouse-symbolic",
            description: "-1 slow … +1 fast (libinput accel)", keyword: "input:sensitivity",
            min: -1.0, max: 1.0, step: 0.1, float: true }),
        kwDropdown({ id: "input.follow-mouse", title: "Focus Follows Mouse", icon: "focus-windows-symbolic",
            description: "How window focus follows the pointer", keyword: "input:follow_mouse",
            items: [
                { label: "Disabled", value: "0" }, { label: "Full", value: "1" },
                { label: "Loose", value: "2" }, { label: "Detached", value: "3" },
            ] }),
        kwToggle({ id: "input.numlock", title: "Numlock by Default", icon: "input-keyboard-symbolic",
            description: "Enable numlock at startup", keyword: "input:numlock_by_default" }),
        kwToggle({ id: "input.natural-scroll", title: "Natural Scroll (Touchpad)", icon: "touchpad-symbolic",
            description: "Content follows finger direction", keyword: "input:touchpad:natural_scroll" }),
        kwSlider({ id: "input.scroll-factor", title: "Touchpad Scroll Factor", icon: "touchpad-symbolic",
            description: "Scroll speed multiplier", keyword: "input:touchpad:scroll_factor",
            min: 0.1, max: 2.0, step: 0.1, float: true }),
    ],
}
export default Input
