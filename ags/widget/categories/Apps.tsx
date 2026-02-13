import Gtk from "gi://Gtk?version=4.0"
import { readOption, writeOption, OPTIONS } from "../../lib/options"

const LABELS: Record<string, string> = {
    browser: "Browser",
    terminal: "Terminal",
    editor: "Editor",
    mediaplayer: "Media Player",
    launchertype: "Launcher Type",
}

export default function Apps() {
    return (
        <box
            cssClasses={["category-content"]}
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
        >
            <label label="Default Apps" cssClasses={["category-title"]} xalign={0} />
            <label
                label="Set default applications used by scripts"
                cssClasses={["category-desc"]}
                xalign={0}
            />
            <box cssClasses={["content-separator"]} />
            {OPTIONS.map(opt => (
                <box cssClasses={["app-row"]} spacing={12}>
                    <label
                        label={LABELS[opt] || opt}
                        widthChars={14}
                        xalign={0}
                        cssClasses={["app-label"]}
                    />
                    <entry
                        text={readOption(opt)}
                        hexpand
                        cssClasses={["app-entry"]}
                        onActivate={(self: Gtk.Entry) => {
                            writeOption(opt, self.get_text())
                        }}
                        $={(self: Gtk.Entry) => {
                            const controller = new Gtk.EventControllerFocus()
                            controller.connect("leave", () => {
                                writeOption(opt, self.get_text())
                            })
                            self.add_controller(controller)
                        }}
                    />
                </box>
            ))}
        </box>
    )
}
