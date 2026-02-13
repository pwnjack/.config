import app from "ags/gtk4/app"
import SettingsPanel from "./widget/SettingsPanel"
import { loadColors } from "./lib/colors"

const c = loadColors()

const css = `
.settings-window {
    background-color: transparent;
}

.panel-backdrop {
    background-color: transparent;
}

.panel-container {
    background-color: alpha(${c.background}, 0.85);
    border-radius: 16px;
    border: 1px solid alpha(${c.colors[4]}, 0.4);
    padding: 0;
}

.panel-layout {
    min-width: 780px;
    min-height: 580px;
}

.category-nav {
    background-color: alpha(${c.colors[0]}, 0.5);
    padding: 16px;
    min-width: 180px;
    border-radius: 16px 0 0 16px;
}

.nav-title {
    font-size: 18px;
    font-weight: bold;
    color: ${c.foreground};
    margin-bottom: 8px;
    padding: 4px 8px;
}

.nav-separator {
    min-height: 1px;
    background-color: alpha(${c.colors[8]}, 0.3);
    margin-bottom: 8px;
}

.nav-button {
    background-color: transparent;
    color: ${c.colors[7]};
    padding: 6px 12px;
    border-radius: 8px;
    border: none;
    font-size: 13px;
}

.nav-button:hover {
    background-color: alpha(${c.colors[4]}, 0.2);
}

.nav-active {
    background-color: alpha(${c.colors[4]}, 0.3);
    color: ${c.colors[6]};
    font-weight: bold;
}

.nav-active:hover {
    background-color: alpha(${c.colors[4]}, 0.35);
}

.content-area {
    padding: 24px 28px;
}

.content-scroll {
    border-radius: 0 16px 16px 0;
}

.content-scroll undershoot.top,
.content-scroll undershoot.bottom {
    background: none;
}

.content-scroll scrollbar {
    background-color: transparent;
    padding: 2px;
}

.content-scroll scrollbar slider {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 99px;
    min-width: 4px;
}

.content-scroll scrollbar slider:hover {
    background-color: alpha(${c.colors[8]}, 0.5);
}

.category-content {
    padding: 4px;
}

.category-title {
    font-size: 20px;
    font-weight: bold;
    color: ${c.foreground};
}

.category-desc {
    font-size: 12px;
    color: ${c.colors[8]};
    margin-bottom: 4px;
}

.content-separator {
    min-height: 1px;
    background-color: alpha(${c.colors[8]}, 0.2);
    margin-bottom: 8px;
}

.toggle-row {
    padding: 10px 8px;
    border-radius: 8px;
}

.toggle-row:hover {
    background-color: alpha(${c.colors[4]}, 0.1);
}

.toggle-label {
    font-size: 14px;
    color: ${c.foreground};
}

.slider-row {
    padding: 8px;
    border-radius: 8px;
}

.slider-row:hover {
    background-color: alpha(${c.colors[4]}, 0.1);
}

.slider-label {
    font-size: 14px;
    color: ${c.foreground};
}

.slider-value {
    font-size: 13px;
    font-family: monospace;
    color: ${c.colors[6]};
}

.settings-scale trough {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 4px;
    min-height: 6px;
}

.settings-scale highlight {
    background-color: ${c.colors[4]};
    border-radius: 4px;
}

.settings-scale slider {
    background-color: ${c.colors[6]};
    border-radius: 50%;
    min-width: 16px;
    min-height: 16px;
}

.app-row {
    padding: 8px;
    border-radius: 8px;
}

.app-row:hover {
    background-color: alpha(${c.colors[4]}, 0.1);
}

.app-label {
    font-size: 14px;
    color: ${c.foreground};
}

.app-entry {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 6px;
    padding: 6px 10px;
    font-size: 13px;
}

.app-entry:focus {
    border-color: ${c.colors[4]};
}

switch {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 12px;
    min-width: 48px;
    min-height: 24px;
}

switch:checked {
    background-color: ${c.colors[4]};
}

switch slider {
    background-color: ${c.foreground};
    border-radius: 50%;
    min-width: 20px;
    min-height: 20px;
    margin: 2px;
}

.dropdown-row {
    padding: 10px 8px;
    border-radius: 8px;
}

.dropdown-row:hover {
    background-color: alpha(${c.colors[4]}, 0.1);
}

.dropdown-label {
    font-size: 14px;
    color: ${c.foreground};
}

.settings-dropdown {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 6px;
    padding: 4px 8px;
    font-size: 13px;
    min-width: 140px;
}

.settings-dropdown:hover {
    border-color: alpha(${c.colors[4]}, 0.5);
}

.settings-dropdown popover contents {
    background-color: alpha(${c.background}, 0.95);
    border: 1px solid alpha(${c.colors[4]}, 0.3);
    border-radius: 8px;
    padding: 4px;
}
`

app.start({
    instanceName: "settings-panel",
    css,
    main() {
        SettingsPanel()
        const win = app.get_window("settings-panel")
        if (win) win.visible = false
    },
})
