import GLib from "gi://GLib"
import Gio from "gi://Gio"
import NM from "gi://NM"
import { failureMessage } from "./network.mjs"

// The only libnm user. It returns plain objects so everything else is testable
// without NetworkManager, and it waits for real activation, not just the D-Bus reply.
for (const [method, finish] of [["add_and_activate_connection_async", "add_and_activate_connection_finish"],
    ["activate_connection_async", "activate_connection_finish"], ["deactivate_connection_async", "deactivate_connection_finish"],
    ["dbus_set_property", "dbus_set_property_finish"]]) Gio._promisify(NM.Client.prototype, method, finish)
Gio._promisify(NM.RemoteConnection.prototype, "delete_async", "delete_finish")
Gio._promisify(NM.DeviceWifi.prototype, "request_scan_async", "request_scan_finish")

let client = null
function nm() {
    if (!client) client = NM.Client.new(null) // 7.5 ms, synchronous; the helper lives for one request.
    return client
}
const ssidText = bytes => bytes ? NM.utils_ssid_to_utf8(bytes.get_data()) : ""
const wifiDevices = () => nm().get_devices().filter(d => d instanceof NM.DeviceWifi)
function stateName(state) {
    if (state === NM.ActiveConnectionState.ACTIVATED) return "activated"
    if (state === NM.ActiveConnectionState.ACTIVATING) return "activating"
    return null
}

export function nmSnapshot() {
    let c
    try { c = nm() } catch (_) { return { running: false } }
    if (!c.get_nm_running()) return { running: false }
    const devices = c.get_devices()
    const wifi = devices.filter(d => d instanceof NM.DeviceWifi)
    const active = new Map(c.get_active_connections().map(a => [a.get_uuid(), a]))
    return {
        running: true,
        wifiEnabled: c.wireless_get_enabled(),
        wifiDevices: wifi.map(d => ({ iface: d.get_iface() })),
        accessPoints: wifi.flatMap(d => d.get_access_points().map(ap => ({
            ssid: ssidText(ap.get_ssid()), strength: ap.get_strength(),
            flags: ap.get_flags(), wpaFlags: ap.get_wpa_flags(), rsnFlags: ap.get_rsn_flags(),
        }))),
        wired: devices.filter(d => d instanceof NM.DeviceEthernet).map(d => {
            const ip = d.get_ip4_config()
            const address = ip?.get_addresses()[0]
            return { iface: d.get_iface(), carrier: d.get_carrier(), speed: d.get_speed(),
                ip4: address ? `${address.get_address()}/${address.get_prefix()}` : null, gateway: ip?.get_gateway() || null }
        }),
        connections: c.get_connections().map(r => {
            const a = active.get(r.get_uuid())
            const wireless = r.get_setting_wireless()
            return { uuid: r.get_uuid(), id: r.get_id(), type: r.get_connection_type(),
                ssid: wireless ? ssidText(wireless.get_ssid()) : null,
                state: a ? stateName(a.get_state()) : null, iface: a?.get_devices()[0]?.get_iface() || null }
        }),
    }
}

const reasonName = reason => Object.keys(NM.ActiveConnectionStateReason).find(key => NM.ActiveConnectionStateReason[key] === reason) || "UNKNOWN"
// Resolves once the connection is really up; rejects with a readable reason.
function settled(active, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
        let handler = 0, timer = 0
        const finish = error => {
            if (handler) active.disconnect(handler)
            if (timer) GLib.source_remove(timer)
            handler = timer = 0
            if (error) reject(error); else resolve()
        }
        const check = (state, reason) => {
            if (state === NM.ActiveConnectionState.ACTIVATED) finish()
            else if (state === NM.ActiveConnectionState.DEACTIVATED) finish(new Error(failureMessage(reasonName(reason))))
        }
        handler = active.connect("state-changed", (_active, state, reason) => check(state, reason))
        timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, timeoutMs, () => { timer = 0; finish(new Error(failureMessage("CONNECT_TIMEOUT"))); return GLib.SOURCE_REMOVE })
        check(active.get_state(), active.get_state_reason())
    })
}
function remote(uuid) {
    const connection = nm().get_connection_by_uuid(uuid)
    if (!connection) throw new Error("That connection no longer exists")
    return connection
}

export async function setWifiEnabled(on) {
    await nm().dbus_set_property(NM.DBUS_PATH, NM.DBUS_INTERFACE, "WirelessEnabled", GLib.Variant.new_boolean(on), -1, null)
}
export async function requestScan() {
    // NM refuses scans that come too soon after the last one; that is not a failure.
    await Promise.all(wifiDevices().map(d => d.request_scan_async(null).catch(error => {
        if (!/not allowed|already|too/i.test(error.message)) throw error
    })))
}
export async function activate(uuid) {
    const active = await nm().activate_connection_async(remote(uuid), null, null, null)
    try { await settled(active) }
    catch (error) { await deactivate(uuid).catch(() => {}); throw error }
}
export async function addAndActivate({ ssid, psk, keyMgmt }) {
    const device = wifiDevices()[0]
    if (!device) throw new Error("No Wi-Fi device")
    const ap = device.get_access_points().filter(a => ssidText(a.get_ssid()) === ssid).sort((a, b) => b.get_strength() - a.get_strength())[0]
    if (!ap) throw new Error("That network is no longer in range")
    const connection = NM.SimpleConnection.new()
    connection.add_setting(new NM.SettingConnection({ id: ssid, uuid: NM.utils_uuid_generate(), type: "802-11-wireless", autoconnect: true }))
    connection.add_setting(new NM.SettingWireless({ ssid: new GLib.Bytes(new TextEncoder().encode(ssid)), mode: "infrastructure" }))
    // keyMgmt is "wpa-psk", "sae" or "owe" (network.mjs); a truly open network has none.
    if (keyMgmt) connection.add_setting(new NM.SettingWirelessSecurity(psk !== null ? { key_mgmt: keyMgmt, psk } : { key_mgmt: keyMgmt }))
    const active = await nm().add_and_activate_connection_async(connection, device, ap.get_path(), null)
    try { await settled(active) }
    catch (error) {
        // A wrong password must not leave a "Saved" network behind.
        await active.get_connection()?.delete_async(null).catch(() => {})
        throw error
    }
}
export async function deactivate(uuid) {
    const active = nm().get_active_connections().find(a => a.get_uuid() === uuid)
    if (active) await nm().deactivate_connection_async(active, null)
}
export async function removeConnections(uuids) {
    for (const uuid of uuids) await remote(uuid).delete_async(null)
}
