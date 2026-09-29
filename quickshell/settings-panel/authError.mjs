export const CANCELLED = "Authentication was cancelled; nothing changed."
export const NO_AGENT = "No authentication agent is running; nothing changed."
export const TIMED_OUT = "Authentication timed out. The panel stepped aside; the setting may still change if you finish the dialog. Reopen the panel to check."

const cancelledNames = [
    "org.freedesktop.PolicyKit1.Error.NotAuthorized",
    "org.freedesktop.PolicyKit1.Error.Cancelled",
    "org.freedesktop.DBus.Error.AccessDenied",
]

function hasErrorName(message, name) {
    const index = message.indexOf(name)
    if (index < 0) return false
    const before = index === 0 ? "" : message[index - 1]
    const after = message[index + name.length] || ""
    return !/[A-Za-z0-9_.]/.test(before) && !/[A-Za-z0-9_.]/.test(after)
}

export function authErrorMessage(message) {
    const text = String(message)
    if (hasErrorName(text, "org.freedesktop.DBus.Error.InteractiveAuthorizationRequired")) return NO_AGENT
    if (cancelledNames.some(name => hasErrorName(text, name))) return CANCELLED
    return null
}

export function interactiveErrorMessage(message, timedOut = false) {
    return timedOut ? TIMED_OUT : authErrorMessage(message)
}
