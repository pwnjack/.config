import { execAsync } from "./process.js"

// Four reads describe every sound row. The backend's once() cache shares one
// result per request; each read is ~4 ms and they run in parallel.
export async function pulseState() {
    const [info, sinks, sources, cards] = await Promise.all([["info"], ["list", "sinks"], ["list", "sources"], ["list", "cards"]]
        .map(async args => JSON.parse(await execAsync(["pactl", "-f", "json", ...args]))))
    return { info, sinks, sources, cards }
}
// Sink monitors are sources too; only real inputs have no monitor_source.
const inputs = state => state.sources.filter(source => !source.monitor_source)
function defaultOf(list, name, what) {
    const device = list.find(device => device.name === name)
    if (!device) throw new Error(`No ${what} device`)
    return device
}
const output = state => defaultOf(state.sinks, state.info.default_sink_name, "output")
const input = state => defaultOf(inputs(state), state.info.default_source_name, "input")
// PipeWire's pulse server reports `card: null`; the card is named in properties.
function cardOf(state, sink) {
    const card = state.cards.find(card => card.name === sink.properties?.["device.name"])
    if (!card) throw new Error("The output device has no card profiles")
    return card
}
const devices = list => list.map(device => ({ label: device.description, value: device.name }))
// A "not available" port has nothing plugged in. The active one is always kept.
function ports(device) {
    if (!device.ports.length) throw new Error("This device has no ports")
    return device.ports.filter(port => port.availability !== "not available" || port.name === device.active_port)
        .map(port => ({ label: port.description, value: port.name }))
}
// "off" would remove the very device these rows describe.
const profiles = card => Object.entries(card.profiles)
    .filter(([name, profile]) => name === card.active_profile || (profile.available && name !== "off"))
    .map(([name, profile]) => ({ label: profile.description, value: name }))

const shared = once => once("pulse", pulseState)
export const pulseEnumerators = {
    "audio-outputs": async (_row, _current, once) => devices((await shared(once)).sinks),
    "audio-inputs": async (_row, _current, once) => devices(inputs(await shared(once))),
    "output-ports": async (_row, _current, once) => ports(output(await shared(once))),
    "input-ports": async (_row, _current, once) => ports(input(await shared(once))),
    "output-profiles": async (_row, _current, once) => { const state = await shared(once); return profiles(cardOf(state, output(state))) },
}
export function pulseValue(key, state) {
    switch (key) {
    case "output": return output(state).name
    case "output-port": return output(state).active_port
    case "output-profile": return cardOf(state, output(state)).active_profile
    case "input": return input(state).name
    case "input-port": return input(state).active_port
    case "mic-level": {
        const channels = Object.values(input(state).volume)
        return Math.round(channels.reduce((sum, channel) => sum + parseFloat(channel.value_percent), 0) / channels.length)
    }
    }
    throw new Error("Unknown sound setting")
}
export async function setPulse(key, value, state) {
    const command = {
        output: () => ["set-default-sink", value],
        "output-port": () => ["set-sink-port", output(state).name, value],
        "output-profile": () => ["set-card-profile", cardOf(state, output(state)).name, value],
        input: () => ["set-default-source", value],
        "input-port": () => ["set-source-port", input(state).name, value],
        "mic-level": () => ["set-source-volume", input(state).name, `${value}%`],
    }[key]
    if (!command) throw new Error("Unknown sound setting")
    await execAsync(["pactl", ...command()])
}
