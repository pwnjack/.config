import app from "ags/gtk4/app"
import SettingsPanel from "./widget/SettingsPanel"
import { buildCss } from "./style"

app.start({
    instanceName: "settings-panel",
    css: buildCss(),
    main() {
        SettingsPanel()
        const win = app.get_window("settings-panel")
        if (win) win.visible = false
    },
})
