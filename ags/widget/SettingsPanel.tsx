import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Toggles from "./categories/Toggles"
import Appearance from "./categories/Appearance"
import AnimationSettings from "./categories/AnimationSettings"
import Input from "./categories/Input"
import Layout from "./categories/Layout"
import Notifications from "./categories/Notifications"
import Power from "./categories/Power"
import Apps from "./categories/Apps"
import Misc from "./categories/Misc"
import CategoryNav from "./components/CategoryNav"

function CategoryContent({ category }: { category: string }) {
    switch (category) {
        case "toggles": return <Toggles />
        case "appearance": return <Appearance />
        case "animations": return <AnimationSettings />
        case "input": return <Input />
        case "layout": return <Layout />
        case "notifications": return <Notifications />
        case "power": return <Power />
        case "apps": return <Apps />
        case "misc": return <Misc />
        default: return <Toggles />
    }
}

export default function SettingsPanel() {
    const stack = new Gtk.Stack({
        transitionType: Gtk.StackTransitionType.CROSSFADE,
        transitionDuration: 150,
        hexpand: true,
        vexpand: true,
        hhomogeneous: true,
        vhomogeneous: true,
    })

    function makeScrollable(widget: Gtk.Widget): Gtk.ScrolledWindow {
        const scroll = new Gtk.ScrolledWindow({
            hscrollbarPolicy: Gtk.PolicyType.NEVER,
            vscrollbarPolicy: Gtk.PolicyType.AUTOMATIC,
            hexpand: true,
            vexpand: true,
            cssClasses: ["content-scroll"],
        })
        scroll.set_child(widget)
        return scroll
    }

    const categories = [
        "toggles", "appearance", "animations", "input",
        "layout", "notifications", "power", "apps", "misc",
    ]

    for (const id of categories) {
        const widget = CategoryContent({ category: id })
        if (widget instanceof Gtk.Widget) {
            stack.add_named(makeScrollable(widget), id)
        }
    }

    stack.set_visible_child_name("toggles")

    const nav = CategoryNav({
        active: "toggles",
        onSelect: (id: string) => {
            stack.set_visible_child_name(id)
        },
    })

    const layout = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL,
        cssClasses: ["panel-layout"],
    })

    if (nav instanceof Gtk.Widget) {
        layout.append(nav)
    }

    const contentWrapper = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        hexpand: true,
        vexpand: true,
        cssClasses: ["content-area"],
    })
    contentWrapper.append(stack)
    layout.append(contentWrapper)

    const keyController = new Gtk.EventControllerKey()

    return (
        <window
            name="settings-panel"
            namespace="settings-panel"
            application={app}
            cssClasses={["settings-window"]}
            anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
            exclusivity={Astal.Exclusivity.NORMAL}
            layer={Astal.Layer.OVERLAY}
            keymode={Astal.Keymode.EXCLUSIVE}
            visible
            $={(self: Astal.Window) => {
                keyController.connect("key-pressed", (_ctrl: Gtk.EventControllerKey, keyval: number) => {
                    if (keyval === Gdk.KEY_Escape) {
                        self.visible = false
                    }
                    return false
                })
                self.add_controller(keyController)
            }}
        >
            <box cssClasses={["panel-backdrop"]} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER}>
                <box cssClasses={["panel-container"]} widthRequest={780} heightRequest={580}>
                    {layout}
                </box>
            </box>
        </window>
    )
}
