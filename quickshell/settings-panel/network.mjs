// Pure Network page logic: plain objects in, plain objects out. nm.js is the
// only file that touches libnm; everything decidable lives here and is tested
// under Node.

// Decided by the round-3 Task 1 probe (docs/settings-panel.md): "nm" lets the
// panel switch Proton's WireGuard profile like any VPN, "app" hands it to the
// Proton app because switching behind its back desyncs it.
export const PROTON_MODE = "app"

const WIFI = "802-11-wireless"
const VPN_TYPES = new Set(["vpn", "wireguard"])
// libnm NM80211ApFlags / NM80211ApSecurityFlags.
const PRIVACY = 0x1, PSK = 0x100, EAP = 0x200, SAE = 0x400, OWE = 0x800

export function securityOf(ap) {
    const all = ap.wpaFlags | ap.rsnFlags
    if (all & PSK) return "psk"
    if (all & SAE) return "sae"
    if (all & EAP) return "unsupported"
    if (all & OWE) return "owe"
    // PRIVACY without WPA/RSN is WEP, which the page does not offer.
    return ap.flags & PRIVACY ? "unsupported" : "open"
}
const savedWifi = snap => snap.connections.filter(c => c.type === WIFI && c.ssid)
const securityRank = {unsupported: 0, owe: 1, open: 2, sae: 3, psk: 4}

export function wifiNetworks(snap) {
    const saved = savedWifi(snap)
    const known = new Set(saved.map(c => c.ssid))
    const active = new Set(saved.filter(c => c.state === "activated").map(c => c.ssid))
    const activating = new Set(saved.filter(c => c.state === "activating").map(c => c.ssid))
    const grouped = new Map()
    for (const ap of snap.accessPoints) {
        if (!ap.ssid) continue
        const security = securityOf(ap)
        const prev = grouped.get(ap.ssid)
        if (!prev) grouped.set(ap.ssid, {best: ap, security})
        else {
            if (ap.strength > prev.best.strength) prev.best = ap
            if (securityRank[security] > securityRank[prev.security]) prev.security = security
        }
    }
    return [...grouped.values()].map(({best, security}) => ({
        ssid: best.ssid, signal: best.strength, bars: Math.max(1, Math.min(4, Math.ceil(best.strength / 25))),
        security, known: known.has(best.ssid), active: active.has(best.ssid), activating: activating.has(best.ssid),
    })).sort((a, b) => b.active - a.active || b.activating - a.activating || b.known - a.known || b.signal - a.signal || a.ssid.localeCompare(b.ssid))
}

export const isProton = connection => connection.id.startsWith("ProtonVPN ")
export function vpnConnections(snap, mode = PROTON_MODE) {
    return snap.connections.filter(c => VPN_TYPES.has(c.type)).map(c => ({
        uuid: c.uuid, name: c.id, state: c.state || "off", iface: c.iface, proton: isProton(c),
        control: isProton(c) && mode === "app" ? "app" : "switch",
    })).sort((a, b) => (b.state === "activated") - (a.state === "activated")
        || (b.state === "activating") - (a.state === "activating") || a.name.localeCompare(b.name))
}

export function networkView(snap, { protonApp = false, mode = PROTON_MODE } = {}) {
    if (!snap.running) return { running: false }
    const vpn = vpnConnections(snap, mode)
    return {
        running: true,
        wifi: { enabled: snap.wifiEnabled, available: snap.wifiDevices.length > 0, networks: snap.wifiDevices.length ? wifiNetworks(snap) : [] },
        wired: snap.wired,
        vpn,
        proton: protonApp ? { mode, active: vpn.some(v => v.proton && v.state === "activated") } : null,
    }
}

function validSsid(ssid) {
    if (typeof ssid !== "string" || !ssid || /[\0\r\n]/.test(ssid) || new TextEncoder().encode(ssid).length > 32) throw new Error("Invalid network name")
    return ssid
}
function validPsk(psk) {
    if (typeof psk !== "string" || !(/^[\x20-\x7e]{8,63}$/.test(psk) || /^[0-9a-fA-F]{64}$/.test(psk)))
        throw new Error("The password must be 8–63 characters, or 64 hexadecimal digits")
    return psk
}
function validSae(psk) {
    if (typeof psk !== "string" || !psk || /[\0\r\n]/.test(psk) || new TextEncoder().encode(psk).length > 256)
        throw new Error("The password must not be empty or contain line breaks")
    return psk
}
export function connectPlan(snap, request) {
    const ssid = validSsid(request.ssid)
    const net = wifiNetworks(snap).find(n => n.ssid === ssid)
    if (!net) throw new Error("That network is no longer in range")
    if (net.security === "unsupported") throw new Error("Enterprise and WEP networks are not supported here; use Advanced…")
    const supplied = request.psk === "" || request.psk === undefined || request.psk === null ? null : request.psk
    const saved = savedWifi(snap).filter(c => c.ssid === ssid).map(c => c.uuid)
    if (saved.length && supplied === null) return { kind: "activate", uuid: saved[0] }
    if (net.security === "open" || net.security === "owe")
        return { kind: "add", ssid, psk: null, keyMgmt: net.security === "owe" ? "owe" : null, replace: saved }
    if (supplied === null) throw new Error("Enter the network password")
    const psk = net.security === "sae" ? validSae(supplied) : validPsk(supplied)
    return { kind: "add", ssid, psk, keyMgmt: net.security === "sae" ? "sae" : "wpa-psk", replace: saved }
}
export function forgetPlan(snap, ssid) {
    const name = validSsid(ssid)
    const uuids = savedWifi(snap).filter(c => c.ssid === name).map(c => c.uuid)
    if (!uuids.length) throw new Error("That network is not saved")
    return uuids
}
export function vpnPlan(snap, request, mode = PROTON_MODE) {
    if (typeof request.active !== "boolean") throw new Error("Expected an on/off value")
    const connection = snap.connections.find(c => c.uuid === request.uuid)
    if (!connection) throw new Error("That connection no longer exists")
    if (!VPN_TYPES.has(connection.type)) throw new Error("That connection is not a VPN")
    if (isProton(connection) && mode === "app") throw new Error("Use the Proton VPN app for this connection")
    return { uuid: connection.uuid, active: request.active }
}

const reasons = {
    NO_SECRETS: "Wrong password", LOGIN_FAILED: "Wrong password",
    CONNECT_TIMEOUT: "The network did not answer in time", SERVICE_START_TIMEOUT: "The VPN service did not start in time",
    DEVICE_DISCONNECTED: "The Wi-Fi device disconnected", CONNECTION_REMOVED: "The connection was removed",
    DEPENDENCY_FAILED: "A connection this one depends on failed",
}
export const failureMessage = name => {
    if (Object.hasOwn(reasons, name)) return reasons[name]
    return name === undefined ? "Connection failed" : `Connection failed (${String(name).toLowerCase().replace(/_/g, " ")})`
}
