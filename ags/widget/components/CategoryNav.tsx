import Gtk from "gi://Gtk?version=4.0"

export interface Category {
    id: string
    label: string
    icon: string
}

export const CATEGORIES: Category[] = [
    { id: "toggles", label: "Toggles", icon: "emblem-default-symbolic" },
    { id: "appearance", label: "Appearance", icon: "preferences-desktop-display-symbolic" },
    { id: "animations", label: "Animations", icon: "preferences-desktop-effects-symbolic" },
    { id: "input", label: "Input", icon: "input-mouse-symbolic" },
    { id: "layout", label: "Layout", icon: "view-grid-symbolic" },
    { id: "notifications", label: "Notifications", icon: "preferences-system-notifications-symbolic" },
    { id: "power", label: "Power", icon: "battery-symbolic" },
    { id: "apps", label: "Apps", icon: "system-run-symbolic" },
    { id: "misc", label: "Misc", icon: "preferences-other-symbolic" },
]

interface CategoryNavProps {
    active: string
    onSelect: (id: string) => void
}

export default function CategoryNav({ active, onSelect }: CategoryNavProps) {
    const buttons: Map<string, Gtk.Button> = new Map()

    function setActive(id: string) {
        buttons.forEach((btn, catId) => {
            if (catId === id) {
                btn.cssClasses = ["nav-button", "nav-active"]
            } else {
                btn.cssClasses = ["nav-button"]
            }
        })
        onSelect(id)
    }

    return (
        <box
            cssClasses={["category-nav"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={2}
        >
            <label
                label="Settings"
                cssClasses={["nav-title"]}
                xalign={0}
            />
            <box cssClasses={["nav-separator"]} />
            {CATEGORIES.map(cat => (
                <button
                    cssClasses={[
                        "nav-button",
                        ...(cat.id === active ? ["nav-active"] : []),
                    ]}
                    onClicked={() => setActive(cat.id)}
                    $={(self: Gtk.Button) => { buttons.set(cat.id, self) }}
                >
                    <box spacing={8}>
                        <image iconName={cat.icon} />
                        <label label={cat.label} />
                    </box>
                </button>
            ))}
        </box>
    )
}
