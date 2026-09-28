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
function fakeAp(ssid, strength, path, { flags = 0, wpaFlags = 0, rsnFlags = 0 } = {}) {
    const ap = Object.create(NM.AccessPoint.prototype)
    ap.get_ssid = () => new GLib.Bytes(new TextEncoder().encode(ssid))
    ap.get_strength = () => strength
    ap.get_path = () => path
    ap.get_flags = () => flags
    ap.get_wpa_flags = () => wpaFlags
    ap.get_rsn_flags = () => rsnFlags
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
    client.devices = [fakeWifiDevice("wlan0", [fakeAp("Home", 80, "/ap/1", { rsnFlags: 0x100 })])]
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

{
    // NM can save the profile as part of handling add_and_activate_connection_async
    // even when that call's own promise rejects (never reaching settled()); the
    // generated uuid must still be cleaned up in that case.
    client.connections = new Map()
    let addedUuid = null, deletedUuid = null
    client.addAndActivateImpl = async connection => {
        addedUuid = connection.get_uuid()
        client.connections.set(addedUuid, fakeConnection(addedUuid, { deleteImpl: async () => { deletedUuid = addedUuid } }))
        throw new Error("D-Bus call failed")
    }
    await assertRejects(nm.addAndActivate({ ssid: "Home", psk: "hunter2222", keyMgmt: "wpa-psk" }), /D-Bus call failed/)
    assert(addedUuid && deletedUuid === addedUuid, "a rejection from add_and_activate_connection_async itself must still delete the generated uuid")
}
console.log("ok: a rejection from add_and_activate_connection_async itself still cleans up the generated uuid")

// --- addAndActivate: AP compatibility with the requested security --------
{
    const strongIncompatible = fakeAp("Mix", 90, "/ap/strong-sae", { rsnFlags: 0x400 })
    const weakCompatible = fakeAp("Mix", 20, "/ap/weak-psk", { rsnFlags: 0x100 })
    client.devices = [fakeWifiDevice("wlan0", [strongIncompatible, weakCompatible])]
    client.connections = new Map()
    let chosenPath = null
    client.addAndActivateImpl = async (connection, device, apPath) => { chosenPath = apPath; return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }) }
    await nm.addAndActivate({ ssid: "Mix", psk: "hunter2222", keyMgmt: "wpa-psk" })
    assertEqual(chosenPath, "/ap/weak-psk", "must skip the incompatible stronger AP and pick the weaker compatible one")
}
console.log("ok: addAndActivate picks the strongest AP that is compatible with the requested security, not the strongest overall")

{
    client.devices = [fakeWifiDevice("wlan0", [fakeAp("SaeOnly", 90, "/ap/sae", { rsnFlags: 0x400 })])]
    client.connections = new Map()
    await assertRejects(nm.addAndActivate({ ssid: "SaeOnly", psk: "hunter2222", keyMgmt: "wpa-psk" }), /no longer in range/)
}
console.log("ok: addAndActivate rejects when no AP for the SSID is compatible with the requested security")

{
    // A transition-mode AP sets both the PSK bit (securityOf ranks it "psk")
    // and the SAE bit; it must still be treated as SAE-compatible.
    client.devices = [fakeWifiDevice("wlan0", [fakeAp("Transition", 90, "/ap/trans", { rsnFlags: 0x500 })])]
    client.connections = new Map()
    let chosenPath = null
    client.addAndActivateImpl = async (connection, device, apPath) => { chosenPath = apPath; return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }) }
    await nm.addAndActivate({ ssid: "Transition", psk: "hunter2222", keyMgmt: "sae" })
    assertEqual(chosenPath, "/ap/trans", "a PSK+SAE transition-mode AP must be accepted for an sae request")
}
console.log("ok: addAndActivate treats a PSK+SAE transition-mode AP as SAE-compatible")

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
    // Latin-1 "Café" (0x43 0x61 0x66 0xe9) is not valid UTF-8. Its display form
    // (from NM.utils_ssid_to_utf8, the same conversion nm.js uses to match a
    // request's ssid against an AP) is a lossy/escaped string that does not
    // re-encode back to these exact bytes — so using it here, instead of a
    // plain UTF-8 string like "Café", catches the AP's own bytes being
    // discarded in favor of a re-encoding of the display string.
    const rawBytes = new Uint8Array([0x43, 0x61, 0x66, 0xe9])
    const ssidBytes = new GLib.Bytes(rawBytes)
    const displaySsid = NM.utils_ssid_to_utf8(rawBytes)
    assert(!ssidBytes.equal(new GLib.Bytes(new TextEncoder().encode(displaySsid))),
        "the display form of a non-UTF-8 SSID must not round-trip back to the same bytes (test fixture is not exercising what it claims to)")
    const ap = Object.create(NM.AccessPoint.prototype)
    ap.get_ssid = () => ssidBytes
    ap.get_strength = () => 50
    ap.get_path = () => "/ap/cafe"
    ap.get_flags = () => 0; ap.get_wpa_flags = () => 0; ap.get_rsn_flags = () => 0
    client.devices = [fakeWifiDevice("wlan0", [ap])]
    client.connections = new Map()
    let capturedConnection = null
    client.addAndActivateImpl = async connection => { capturedConnection = connection; return fakeActive({ state: NM.ActiveConnectionState.ACTIVATED }) }
    await nm.addAndActivate({ ssid: displaySsid, psk: null, keyMgmt: null })
    assert(capturedConnection.get_setting_wireless().get_ssid().equal(ssidBytes), "SettingWireless ssid must be the AP's own bytes, not a re-encoding")
}
console.log("ok: addAndActivate builds SettingWireless ssid from the access point's own bytes, even when they are not valid UTF-8")

// --- requestScan ----------------------------------------------------------
{
    // The message deliberately contains none of "not allowed"/"already"/"too":
    // tolerance must come from the error's type (NM.DeviceError, NOTALLOWED),
    // not from matching words in its message.
    const device = fakeWifiDevice("wlan0", [])
    device.request_scan_async = async () => { throw new GLib.Error(NM.DeviceError, NM.DeviceError.NOTALLOWED, "scan request declined") }
    client.devices = [device]
    await nm.requestScan()
}
console.log("ok: requestScan tolerates NM's not-allowed/too-frequent scan error, judged by error type, not by its message")

{
    // The message deliberately mimics the tolerated wording: rethrowing must
    // still happen because this is a plain Error, not an NM.DeviceError NOTALLOWED.
    const device = fakeWifiDevice("wlan0", [])
    device.request_scan_async = async () => { throw new Error("not allowed right now, already scanning, too soon") }
    client.devices = [device]
    await assertRejects(nm.requestScan(), /not allowed right now/)
}
console.log("ok: requestScan rethrows a same-wording error that is not actually a NM.DeviceError NOTALLOWED")

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
    assertEqual(captured[0], NM.DBUS_PATH, "must target the NM D-Bus object path")
    assertEqual(captured[1], NM.DBUS_INTERFACE, "must target the NM D-Bus interface")
    assertEqual(captured[2], "WirelessEnabled", "setWifiEnabled must set the WirelessEnabled dbus property")
    assert(captured[3] instanceof GLib.Variant, "the value must be a GLib.Variant")
    assertEqual(captured[3].get_boolean(), false, "the variant must carry the requested boolean")
    assertEqual(captured[4], -1, "must pass the default timeout")
    assertEqual(captured[5], null, "must pass no cancellable")
}
console.log("ok: setWifiEnabled reaches the client's dbus property setter with every argument correct")
