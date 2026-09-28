// Display configuration shared by the backend (GJS), the Displays page (QML)
// and the tests (Node). Pure functions only: no I/O, no Hyprland calls.

// The tracked catch-all in hypr/config/hardware/monitor.lua, per output.
export const AUTOMATIC = { mode: "highres@highrr", position: "auto", scale: 1, transform: 0 }
export const STATE_HEADER = "-- Written by the Super+I settings panel (Displays): one hl.monitor() per output.\n" +
    "-- Loaded by hypr/config/hardware/monitor.lua after its host-neutral default.\n"
// Hyprland's auto-* keywords place a display relative to the whole layout, so
// no pixel offset is stored that would go stale when another mode changes.
export const positions = [
    { label: "Automatic", value: "auto" },
    { label: "Left of the others", value: "auto-left" },
    { label: "Right of the others", value: "auto-right" },
    { label: "Above the others", value: "auto-up" },
    { label: "Below the others", value: "auto-down" },
]
export const transforms = ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
    .map((label, value) => ({ label, value }))

const modePattern = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)$/
export function modeChoices(monitor) {
    return [{ label: "Automatic", value: AUTOMATIC.mode }].concat((monitor.availableModes || []).map(mode => {
        const value = mode.replace(/Hz$/, "")
        const [, width, height, hertz] = value.match(modePattern)
        return { label: `${width} × ${height} · ${Math.round(Number(hertz))} Hz`, value }
    }))
}
// highres@highrr picks the largest mode, so Automatic scales against that one.
export function modeSize(mode, monitor) {
    const match = mode.match(modePattern)
    if (match) return [Number(match[1]), Number(match[2])]
    const sizes = (monitor.availableModes || []).map(entry => entry.match(/^(\d+)x(\d+)/)).filter(Boolean)
        .map(([, width, height]) => [Number(width), Number(height)])
    return sizes.length ? sizes.reduce((best, size) => size[0] * size[1] > best[0] * best[1] ? size : best) : [monitor.width, monitor.height]
}
// Fractional scaling is expressed in 1/120 steps, and Hyprland needs a whole
// logical size, so only scales that divide both dimensions are offered.
export function scaleChoices(width, height) {
    const scales = []
    for (let step = 120; step <= 360; step++)
        if ((width * 120) % step === 0 && (height * 120) % step === 0)
            scales.push({ label: `${Math.round(step / 1.2)} %`, value: step / 120 })
    return scales
}

const quoted = text => {
    if (typeof text !== "string" || !/^[\w.@:+-]+$/.test(text)) throw new Error("Invalid display value")
    return `"${text}"`
}
export function monitorLine(output, config) {
    if (config.disabled) return `hl.monitor({ output = ${quoted(output)}, disabled = true })`
    if (!Number.isFinite(config.scale) || !Number.isInteger(config.transform)) throw new Error("Invalid display value")
    return `hl.monitor({ output = ${quoted(output)}, mode = ${quoted(config.mode)}, position = ${quoted(config.position)}, scale = ${config.scale}, transform = ${config.transform} })`
}

const linePattern = /^hl\.monitor\(\{ output = "([\w.@:+-]+)", (?:disabled = true|mode = "([\w.@:+-]+)", position = "([\w-]+)", scale = ([\d.]+), transform = ([0-7])) \}\)$/
// Lines in any other shape were edited by hand; the panel leaves those outputs alone.
export function parseStateFile(text) {
    const outputs = {}
    const handEdited = new Set()
    for (const line of text.split("\n")) {
        if (!line.trim() || line.startsWith("--")) continue
        const match = line.match(linePattern)
        if (match) {
            outputs[match[1]] = match[2] === undefined ? { disabled: true }
                : { mode: match[2], position: match[3], scale: Number(match[4]), transform: Number(match[5]) }
            continue
        }
        const named = line.match(/output\s*=\s*"([^"]+)"/)
        handEdited.add(named ? named[1] : "*")
    }
    return { outputs, handEdited }
}
const escaped = text => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
// Replace, add or (line = null) remove one output's line, keeping every other byte.
export function stateFileWith(text, output, line) {
    const base = text || STATE_HEADER
    const own = new RegExp(`^hl\\.monitor\\(\\{ output = "${escaped(output)}", .*\\n?`, "m")
    if (own.test(base)) return base.replace(own, () => line ? line + "\n" : "")
    return line ? base + line + "\n" : base
}
