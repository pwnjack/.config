import GLib from "gi://GLib"

export interface PywalColors {
    background: string
    foreground: string
    cursor: string
    colors: string[]
}

const COLORS_PATH = GLib.get_home_dir() + "/.cache/wal/colors.json"

export function loadColors(): PywalColors {
    try {
        const [ok, contents] = GLib.file_get_contents(COLORS_PATH)
        if (!ok || !contents) throw new Error("Failed to read colors.json")

        const json = JSON.parse(new TextDecoder().decode(contents))
        const colors: string[] = []
        for (let i = 0; i <= 15; i++) {
            colors.push(json.colors[`color${i}`])
        }

        return {
            background: json.special.background,
            foreground: json.special.foreground,
            cursor: json.special.cursor,
            colors,
        }
    } catch (e) {
        console.error("Failed to load pywal colors:", e)
        return {
            background: "#1a1b26",
            foreground: "#c0caf5",
            cursor: "#c0caf5",
            colors: [
                "#1a1b26", "#f7768e", "#9ece6a", "#e0af68",
                "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
                "#414868", "#f7768e", "#9ece6a", "#e0af68",
                "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
            ],
        }
    }
}
