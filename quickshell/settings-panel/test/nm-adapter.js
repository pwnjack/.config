// Adapter-level tests for nm.js, run under real gjs against the real NM
// typelib for enums/constants (no NetworkManager daemon needed). nm.js swaps
// its lazily-created NM.Client for a fake through useClientForTests().
import NM from "gi://NM"
import GLib from "gi://GLib"
import * as nm from "../nm.js"

function assert(cond, msg) { if (!cond) throw new Error(msg || "assertion failed") }
function assertEqual(actual, expected, msg) {
    if (actual !== expected) throw new Error(`${msg || "not equal"}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
}
async function assertRejects(promise, pattern, msg) {
    try { await promise }
    catch (error) {
        if (!pattern.test(error.message)) throw new Error(`${msg || "wrong rejection"}: got "${error.message}"`)
        return error
    }
    throw new Error(msg || "expected a rejection")
}

// A plain-object GObject-signal stand-in: real GI classes need a live C
// instance to call .connect() on, so fakes bring their own.
function signalable(base = {}) {
    const handlers = new Map()
    let nextId = 0
    base.connect = (name, cb) => { const id = ++nextId; handlers.set(id, [name, cb]); return id }
    base.disconnect = id => { handlers.delete(id) }
    base.emit = (name, ...args) => { for (const [n, cb] of [...handlers.values()]) if (n === name) cb(base, ...args) }
    base._handlerCount = () => handlers.size
    return base
}
function fakeActive({ uuid = NM.utils_uuid_generate(), state = NM.ActiveConnectionState.ACTIVATING, reason = NM.ActiveConnectionStateReason.NONE } = {}) {
    const active = signalable({
        get_uuid: () => uuid,
        get_state: () => state,
        get_state_reason: () => reason,
        setState(newState, newReason = NM.ActiveConnectionStateReason.NONE) {
            state = newState; reason = newReason
            active.emit("state-changed", state, reason)
        },
    })
    return active
}
// Instanceof matters only for wifiDevices()'s NM.DeviceWifi filter; borrowing
// the real prototype satisfies that without a live C object.
function fakeWifiDevice(iface, accessPoints = []) {
    const device = Object.create(NM.DeviceWifi.prototype)
    device.get_iface = () => iface
    device.get_access_points = () => accessPoints
    device.request_scan_async = async () => {}
    return device
}
function fakeAp(ssid, strength, path) {
    const ap = Object.create(NM.AccessPoint.prototype)
    ap.get_ssid = () => new GLib.Bytes(new TextEncoder().encode(ssid))
    ap.get_strength = () => strength
    ap.get_path = () => path
    return ap
}
function fakeConnection(uuid, { deleteImpl = async () => {} } = {}) {
    return { get_uuid: () => uuid, delete_async: deleteImpl }
}
function fakeClient() {
    const calls = []
    const client = signalable({
        calls,
        running: true,
        devices: [],
        activeConnections: [],
        connections: new Map(),
        addAndActivateImpl: async () => fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }),
        activateImpl: async () => fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }),
        deactivateImpl: async () => {},
        dbusSetImpl: async () => {},
        get_nm_running() { return client.running },
        wireless_get_enabled() { return true },
        get_devices() { return client.devices },
        get_active_connections() { return client.activeConnections },
        get_connections() { return [...client.connections.values()] },
        get_connection_by_uuid(uuid) { return client.connections.get(uuid) || null },
        async add_and_activate_connection_async(connection, device, apPath) {
            calls.push(["add_and_activate", connection, device, apPath])
            return client.addAndActivateImpl(connection, device, apPath)
        },
        async activate_connection_async(connection, device, specificObject) {
            calls.push(["activate", connection])
            return client.activateImpl(connection, device, specificObject)
        },
        async deactivate_connection_async(active) {
            calls.push(["deactivate", active])
            return client.deactivateImpl(active)
        },
        async dbus_set_property(...args) {
            calls.push(["dbus_set_property", ...args])
            return client.dbusSetImpl(...args)
        },
    })
    return client
}
// Fires a state change (or a removal) shortly after settled() has had a
// chance to register its handlers — mirrors a real async D-Bus notification.
function soon(fn) { GLib.timeout_add(GLib.PRIORITY_DEFAULT, 15, () => { fn(); return GLib.SOURCE_REMOVE }) }

const client = fakeClient()
nm.useClientForTests(client)

// --- settled() ---------------------------------------------------------
async function checkedSettled(active, timeoutMs) {
    const before = client._handlerCount()
    let error
    try { await nm.settled(active, timeoutMs) } catch (e) { error = e }
    assertEqual(active._handlerCount(), 0, "the state-changed handler was not disconnected")
    assertEqual(client._handlerCount(), before, "the active-connection-removed handler was not disconnected")
    if (error) throw error
}

await checkedSettled(fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }), 1000)
console.log("ok: settled resolves immediately when already activated")

await assertRejects(checkedSettled(fakeActive({ state: NM.ActiveConnectionState.DEACTIVATED, reason: NM.ActiveConnectionStateReason.NO_SECRETS }), 1000), /Wrong password/)
console.log("ok: settled rejects immediately when already deactivated, mapping the reason")

{
    const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
    soon(() => active.setState(NM.ActiveConnectionState.ACTIVATED))
    await checkedSettled(active, 1000)
}
console.log("ok: settled resolves on a later ACTIVATED state-changed event")

await assertRejects(checkedSettled(fakeActive({ state: NM.ActiveConnectionState.ACTIVATING }), 40), /did not answer in time/)
console.log("ok: settled rejects on timeout using the given timeout")

{
    const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
    soon(() => client.emit("active-connection-removed", active))
    await assertRejects(checkedSettled(active, 1000), /connection was removed/)
}
console.log("ok: settled rejects when its ActiveConnection is removed from NM.Client")

{
    const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
    const other = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
    soon(() => client.emit("active-connection-removed", other))
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 30, () => { active.setState(NM.ActiveConnectionState.ACTIVATED); return GLib.SOURCE_REMOVE })
    await checkedSettled(active, 1000)
}
console.log("ok: settled ignores a removal signal for a different active connection")

{
    const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
    soon(() => active.setState(NM.ActiveConnectionState.UNKNOWN))
    await assertRejects(checkedSettled(active, 1000), /connection was removed/)
}
console.log("ok: settled treats UNKNOWN after ACTIVATING as a failure")

{
    const active = fakeActive({ state: NM.ActiveConnectionState.UNKNOWN })
    soon(() => active.setState(NM.ActiveConnectionState.ACTIVATING))
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 30, () => { active.setState(NM.ActiveConnectionState.ACTIVATED); return GLib.SOURCE_REMOVE })
    await checkedSettled(active, 1000)
}
console.log("ok: settled does not treat UNKNOWN before any ACTIVATING as a failure")

// --- addAndActivate: no device / out of range ---------------------------
client.devices = []
await assertRejects(nm.addAndActivate({ ssid: "Ghost", psk: null, keyMgmt: null }), /No Wi-Fi device/)
client.devices = [fakeWifiDevice("wlan0", [])]
await assertRejects(nm.addAndActivate({ ssid: "Ghost", psk: null, keyMgmt: null }), /no longer in range/)
console.log("ok: addAndActivate rejects when there is no Wi-Fi device or the network is out of range")

// --- addAndActivate: cleanup on a failed activation ---------------------
{
    client.devices = [fakeWifiDevice("wlan0", [fakeAp("Home", 80, "/ap/1")])]
    client.connections = new Map()
    let addedUuid = null, deletedUuid = null
    client.addAndActivateImpl = async connection => {
        addedUuid = connection.get_uuid()
        client.connections.set(addedUuid, fakeConnection(addedUuid, { deleteImpl: async () => { deletedUuid = addedUuid } }))
        const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
        soon(() => active.setState(NM.ActiveConnectionState.DEACTIVATED, NM.ActiveConnectionStateReason.NO_SECRETS))
        return active
    }
    await assertRejects(nm.addAndActivate({ ssid: "Home", psk: "hunter2222", keyMgmt: "wpa-psk" }), /Wrong password/)
    assert(addedUuid && deletedUuid === addedUuid, "must delete exactly the generated uuid, nothing else")
}
console.log("ok: a failed activation deletes exactly the generated uuid")

{
    client.connections = new Map()
    client.addAndActivateImpl = async connection => {
        const uuid = connection.get_uuid()
        client.connections.set(uuid, fakeConnection(uuid, { deleteImpl: async () => { throw new Error("dbus gone") } }))
        const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
        soon(() => active.setState(NM.ActiveConnectionState.DEACTIVATED, NM.ActiveConnectionStateReason.NO_SECRETS))
        return active
    }
    const error = await assertRejects(nm.addAndActivate({ ssid: "Home", psk: "hunter2222", keyMgmt: "wpa-psk" }), /Wrong password/)
    assert(/dbus gone/.test(error.message), "must also surface the delete failure")
    assert(!/hunter2222/.test(error.message), "must never expose the PSK in an error message")
}
console.log("ok: a delete failure surfaces both the activation and delete errors, never the PSK")

{
    // NM already unexported the profile (or it was never registered): the
    // code never calls active.get_connection() any more, only
    // get_connection_by_uuid(); a miss there is "nothing to delete", not an error.
    client.connections = new Map()
    client.addAndActivateImpl = async () => {
        const active = fakeActive({ state: NM.ActiveConnectionState.ACTIVATING })
        soon(() => active.setState(NM.ActiveConnectionState.DEACTIVATED, NM.ActiveConnectionStateReason.NO_SECRETS))
        return active
    }
    await assertRejects(nm.addAndActivate({ ssid: "Home", psk: "hunter2222", keyMgmt: "wpa-psk" }), /Wrong password/)
}
console.log("ok: a missing saved profile (get_connection_by_uuid misses) still surfaces the original failure")

// --- addAndActivate: device routing and ssid bytes -----------------------
{
    const weak = fakeAp("Roam", 30, "/ap/weak")
    const strong = fakeAp("Roam", 90, "/ap/strong")
    const devA = fakeWifiDevice("wlan0", [weak])
    const devB = fakeWifiDevice("wlan1", [strong])
    client.devices = [devA, devB]
    client.connections = new Map()
    let chosenDevice = null, chosenPath = null
    client.addAndActivateImpl = async (connection, device, apPath) => {
        chosenDevice = device; chosenPath = apPath
        return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED })
    }
    await nm.addAndActivate({ ssid: "Roam", psk: null, keyMgmt: null })
    assert(chosenDevice === devB, "must pick the device that sees the strongest AP")
    assertEqual(chosenPath, "/ap/strong", "must pick the strongest AP's path")
}
console.log("ok: addAndActivate routes through the device that sees the strongest AP for the SSID")

{
    const ssidBytes = new GLib.Bytes(new TextEncoder().encode("Café"))
    const ap = Object.create(NM.AccessPoint.prototype)
    ap.get_ssid = () => ssidBytes
    ap.get_strength = () => 50
    ap.get_path = () => "/ap/cafe"
    client.devices = [fakeWifiDevice("wlan0", [ap])]
    client.connections = new Map()
    let capturedConnection = null
    client.addAndActivateImpl = async connection => { capturedConnection = connection; return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }) }
    await nm.addAndActivate({ ssid: "Café", psk: null, keyMgmt: null })
    assert(capturedConnection.get_setting_wireless().get_ssid().equal(ssidBytes), "SettingWireless ssid must be the AP's own bytes, not a re-encoding")
}
console.log("ok: addAndActivate builds SettingWireless ssid from the access point's own bytes")

// --- requestScan ----------------------------------------------------------
{
    const device = fakeWifiDevice("wlan0", [])
    device.request_scan_async = async () => { throw new GLib.Error(NM.DeviceError, NM.DeviceError.NOTALLOWED, "too soon") }
    client.devices = [device]
    await nm.requestScan()
}
console.log("ok: requestScan tolerates NM's not-allowed/too-frequent scan error")

{
    const device = fakeWifiDevice("wlan0", [])
    device.request_scan_async = async () => { throw new Error("dbus down") }
    client.devices = [device]
    await assertRejects(nm.requestScan(), /dbus down/)
}
console.log("ok: requestScan rethrows any other error")

// --- activate/deactivate reach the client ---------------------------------
{
    client.connections = new Map([["u-vpn", fakeConnection("u-vpn")]])
    let activatedWith = null
    client.activateImpl = async connection => { activatedWith = connection; return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }) }
    await nm.activate("u-vpn")
    assert(activatedWith === client.connections.get("u-vpn"), "activate must pass the remote connection to the client")
}
console.log("ok: activate reaches the client with the remote connection")

{
    const active = fakeActive({ uuid: "u-vpn2", state: NM.ActiveConnectionState.ACTIVATED })
    client.activeConnections = [active]
    let deactivatedWith = null
    client.deactivateImpl = async activeArg => { deactivatedWith = activeArg }
    await nm.deactivate("u-vpn2")
    assert(deactivatedWith === active, "deactivate must pass the matching active connection to the client")
}
console.log("ok: deactivate reaches the client with the matching active connection")

{
    let captured = null
    client.dbusSetImpl = async (...args) => { captured = args }
    await nm.setWifiEnabled(false)
    assertEqual(captured[2], "WirelessEnabled", "setWifiEnabled must set the WirelessEnabled dbus property")
}
console.log("ok: setWifiEnabled reaches the client's dbus property setter")
