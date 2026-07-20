import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwSlider, optionEntry, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { readOption } from "../../lib/options"
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

function applyFonts() {
    execAsync(["bash", GLib.get_home_dir() + "/.config/scripts/fonts/apply-font.sh"]).catch(console.error)
}

function getCursorSize(): number {
    try {
        const [ok, out] = GLib.spawn_command_line_sync("gsettings get org.gnome.desktop.interface cursor-size")
        if (ok && out) return parseInt(new TextDecoder().decode(out).trim()) || 24
    } catch (e) { console.error(e) }
    return 24
}

// Cursor theme/size are not Hyprland keywords; they live in gsettings (persistent
// by itself) and are applied live via hyprctl setcursor.
function applyCursor(theme: string, size: number) {
    execAsync(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme]).catch(console.error)
    execAsync(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", String(size)]).catch(console.error)
    execAsync(["hyprctl", "setcursor", theme, String(size)]).catch(console.error)
}

function applyCursorTheme(theme: string) {
    try {
        Gio.File.new_for_path(GLib.get_home_dir() + "/.config/hypr/config/cursortheme.conf")
            .replace_contents(new TextEncoder().encode(`$cursortheme = ${theme}\n`),
                null, false, Gio.FileCreateFlags.NONE, null)
    } catch (e) { console.error(e) }
    applyCursor(theme, getCursorSize())
}

const Appearance: CategoryDef = {
    id: "appearance", label: "Appearance", group: "Look & Feel",
    icon: "preferences-desktop-display-symbolic",
    description: "Borders, blur, gaps, opacity, fonts and cursor",
    rows: () => [
        kwToggle({ id: "appearance.blur", title: "Blur", icon: "weather-fog-symbolic",
            description: "Frosted-glass effect behind windows", keyword: "decoration:blur:enabled" }),
        kwSlider({ id: "appearance.blur-size", title: "Blur Size", icon: "zoom-fit-best-symbolic",
            description: "Blur kernel radius", keyword: "decoration:blur:size", min: 1, max: 20, step: 1 }),
        kwSlider({ id: "appearance.blur-passes", title: "Blur Passes", icon: "view-continuous-symbolic",
            description: "More passes, smoother and costlier blur", keyword: "decoration:blur:passes", min: 1, max: 6, step: 1 }),
        kwToggle({ id: "appearance.shadows", title: "Shadows", icon: "weather-clear-night-symbolic",
            description: "Drop shadow under windows", keyword: "decoration:shadow:enabled" }),
        kwSlider({ id: "appearance.rounding", title: "Corner Rounding", icon: "object-select-symbolic",
            description: "Window corner radius in pixels", keyword: "decoration:rounding", min: 0, max: 30, step: 1 }),
        kwSlider({ id: "appearance.border", title: "Border Width", icon: "view-frame-symbolic",
            description: "Window border thickness", keyword: "general:border_size", min: 0, max: 5, step: 1 }),
        kwSlider({ id: "appearance.gaps-in", title: "Gaps Inner", icon: "view-grid-symbolic",
            description: "Space between tiled windows", keyword: "general:gaps_in", min: 0, max: 20, step: 1 }),
        kwSlider({ id: "appearance.gaps-out", title: "Gaps Outer", icon: "view-fullscreen-symbolic",
            description: "Space between windows and screen edge", keyword: "general:gaps_out", min: 0, max: 30, step: 1 }),
        kwSlider({ id: "appearance.opacity-active", title: "Active Opacity", icon: "view-reveal-symbolic",
            description: "Opacity of the focused window", keyword: "decoration:active_opacity",
            min: 0.1, max: 1.0, step: 0.05, float: true }),
        kwSlider({ id: "appearance.opacity-inactive", title: "Inactive Opacity", icon: "view-conceal-symbolic",
            description: "Opacity of unfocused windows", keyword: "decoration:inactive_opacity",
            min: 0.1, max: 1.0, step: 0.05, float: true }),
        optionEntry({ id: "appearance.font", title: "Main Font", icon: "font-x-generic-symbolic",
            description: "Applied to rofi, waybar, terminals via apply-font.sh", option: "font",
            keywords: ["typeface"], onCommit: applyFonts }),
        optionEntry({ id: "appearance.font-gtk", title: "GTK Font", icon: "font-x-generic-symbolic",
            description: "Font for GTK applications", option: "font-gtk", onCommit: applyFonts }),
        optionEntry({ id: "appearance.cursor-theme", title: "Cursor Theme", icon: "input-mouse-symbolic",
            description: "Cursor theme name (fully applies after restart)", option: "cursortheme",
            onCommit: applyCursorTheme }),
        customRow({ id: "appearance.cursor-size", title: "Cursor Size", icon: "input-mouse-symbolic",
            description: "Pointer size in pixels (via gsettings)",
            control: () => SliderControl({ value: getCursorSize(), min: 16, max: 48, step: 2,
                onChanged: v => applyCursor(readOption("cursortheme") || "Bibata-Modern-Classic", Math.round(v)) }) }),
    ],
}
export default Appearance
