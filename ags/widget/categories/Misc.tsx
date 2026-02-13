import Gtk from "gi://Gtk?version=4.0"
import Toggle from "../components/Toggle"
import SettingsSlider from "../components/Slider"
import { setKeyword, getOptionBool, getOptionInt } from "../../lib/hyprctl"
import { readOption, writeOption } from "../../lib/options"

export default function Misc() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Miscellaneous" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Cursor, fonts, and other settings"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />

            <box cssClasses={["app-row"]} spacing={12}>
                <label label="Cursor Theme" widthChars={14} xalign={0} cssClasses={["app-label"]} />
                <entry
                    text={readOption("cursortheme") || "Bibata-Modern-Classic"}
                    hexpand
                    cssClasses={["app-entry"]}
                    onActivate={(self: Gtk.Entry) => {
                        const val = self.get_text()
                        setKeyword("cursor:theme", val)
                        writeOption("cursortheme", val)
                    }}
                    $={(self: Gtk.Entry) => {
                        const controller = new Gtk.EventControllerFocus()
                        controller.connect("leave", () => {
                            const val = self.get_text()
                            setKeyword("cursor:theme", val)
                            writeOption("cursortheme", val)
                        })
                        self.add_controller(controller)
                    }}
                />
            </box>

            <SettingsSlider
                label="Cursor Size"
                value={getOptionInt("cursor:size") || 24}
                min={16}
                max={48}
                step={2}
                onChanged={(val) => setKeyword("cursor:size", Math.round(val))}
            />

            <box cssClasses={["app-row"]} spacing={12}>
                <label label="Font" widthChars={14} xalign={0} cssClasses={["app-label"]} />
                <entry
                    text={readOption("font")}
                    hexpand
                    cssClasses={["app-entry"]}
                    onActivate={(self: Gtk.Entry) => {
                        writeOption("font", self.get_text())
                    }}
                    $={(self: Gtk.Entry) => {
                        const controller = new Gtk.EventControllerFocus()
                        controller.connect("leave", () => {
                            writeOption("font", self.get_text())
                        })
                        self.add_controller(controller)
                    }}
                />
            </box>

            <box cssClasses={["app-row"]} spacing={12}>
                <label label="GTK Font" widthChars={14} xalign={0} cssClasses={["app-label"]} />
                <entry
                    text={readOption("font-gtk")}
                    hexpand
                    cssClasses={["app-entry"]}
                    onActivate={(self: Gtk.Entry) => {
                        writeOption("font-gtk", self.get_text())
                    }}
                    $={(self: Gtk.Entry) => {
                        const controller = new Gtk.EventControllerFocus()
                        controller.connect("leave", () => {
                            writeOption("font-gtk", self.get_text())
                        })
                        self.add_controller(controller)
                    }}
                />
            </box>

            <Toggle
                label="Hyprland Logo"
                active={!getOptionBool("misc:disable_hyprland_logo")}
                onToggled={(v) => setKeyword("misc:disable_hyprland_logo", !v)}
            />
            <Toggle
                label="Splash Rendering"
                active={!getOptionBool("misc:disable_splash_rendering")}
                onToggled={(v) => setKeyword("misc:disable_splash_rendering", !v)}
            />
            <Toggle
                label="Hyprcursor"
                active={getOptionBool("cursor:enable_hyprcursor")}
                onToggled={(v) => setKeyword("cursor:enable_hyprcursor", v)}
            />
        </box>
    )
}
