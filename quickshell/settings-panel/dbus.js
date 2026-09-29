import Gio from "gi://Gio"
import GLib from "gi://GLib"

export const CANCELLED = "Authentication was cancelled; nothing changed."
// Polkit refusals as systemd's daemons report them; Task 1 recorded the one a dismissed dialog returns.
const cancelled = /AccessDenied|NotAuthorized|InteractiveAuthorizationRequired|PolicyKit1\.Error/

// Plain JS in, fully unpacked JS out; `interactive` lets polkit show its dialog.
export function callSystem(name, path, iface, method, signature, args, { interactive = false } = {}) {
    return new Promise((resolve, reject) => {
        Gio.DBus.system.call(name, path, iface, method, signature ? new GLib.Variant(signature, args) : null, null,
            interactive ? Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION : Gio.DBusCallFlags.NONE,
            interactive ? 120000 : 5000, null, (connection, result) => {
                try { resolve(connection.call_finish(result).recursiveUnpack()) }
                catch (error) { reject(cancelled.test(error.message) ? new Error(CANCELLED) : error) }
            })
    })
}
export async function getProperty(name, path, iface, property) {
    const [value] = await callSystem(name, path, "org.freedesktop.DBus.Properties", "Get", "(ss)", [iface, property])
    return value
}
