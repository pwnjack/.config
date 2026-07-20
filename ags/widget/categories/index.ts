import { CategoryDef } from "../../lib/registry"
import { kwSlider, kwToggle } from "../components/rows"

// Temporary Appearance-only barrel — Task 4 replaces this with the full category set.
export const CATEGORIES: CategoryDef[] = [{
    id: "appearance", label: "Appearance", group: "Look & Feel",
    icon: "preferences-desktop-display-symbolic",
    description: "Borders, blur, gaps and opacity",
    rows: () => [
        kwToggle({ id: "appearance.blur", title: "Blur", icon: "weather-fog-symbolic",
            description: "Frosted-glass effect behind windows", keyword: "decoration:blur:enabled" }),
        kwSlider({ id: "appearance.rounding", title: "Corner Rounding", icon: "object-select-symbolic",
            description: "Window corner radius in pixels", keyword: "decoration:rounding",
            min: 0, max: 30, step: 1 }),
    ],
}]
