pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The XDG autostart set that uwsm's systemd generator launches at login, and
// Hyprland's own session (read-only, parsed from autostart.lua).
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    objectName: "startupView"
    readonly property var model: controller.startup
    // A read that failed leaves {error}; the page then has nothing to list.
    readonly property bool ready: !!model && !model.error
    // Remove asks twice: the row waiting for its second click, until anything else happens.
    property string confirming: ""
    property int confirmMs: 5000
    spacing: 22
    onModelChanged: confirming = ""
    Timer { id: confirmTimer; interval: page.confirmMs; onTriggered: page.confirming = "" }

    Label { visible: !page.model; text: "Reading startup apps…"; color: page.theme.dim; font.pixelSize: 13 }
    Label {
        objectName: "startupError"
        visible: !!page.model && !!page.model.error
        text: page.model && page.model.error ? "Could not read startup apps: " + page.model.error : ""
        color: page.theme.warn; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsSection {
        visible: page.ready
        theme: page.theme
        title: "Apps"
        footer: "Changes take effect at next login."
        Repeater {
            model: page.ready ? page.model.apps : []
            delegate: PanelRow {
                id: app
                required property var modelData
                required property int index
                objectName: "startup-" + modelData.id
                theme: page.theme
                divider: index > 0
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: app.modelData.name; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label {
                        objectName: "startupStatus-" + app.modelData.id
                        text: [app.modelData.scope, app.modelData.status.label,
                            app.modelData.ignoredGnomeFlag ? "X-GNOME-Autostart-enabled has no effect under systemd" : "",
                            app.modelData.link ? "A link; edit it by hand" : "",
                            app.modelData.origin === "user" ? "In ~/.config/autostart" : app.modelData.origin === "override" && !app.modelData.staleOverride && app.modelData.enabled ? "Your version in ~/.config/autostart" : ""].filter(Boolean).join(" · ")
                        color: page.theme.dim; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Loader {
                    active: !!app.modelData.removable && !app.modelData.link
                    sourceComponent: PanelButton {
                        objectName: "startupRemove-" + app.modelData.id
                        theme: page.theme
                        text: page.confirming === app.modelData.id ? (app.modelData.origin === "override" ? "Confirm: starts again at login" : "Confirm remove") : "Remove"
                        enabled: !page.controller.busy
                        onClicked: {
                            if (page.confirming !== app.modelData.id) { page.confirming = app.modelData.id; confirmTimer.restart(); return }
                            page.confirming = ""; confirmTimer.stop()
                            page.controller.submit({op: "autostart", action: "remove", id: app.modelData.id})
                        }
                    }
                }
                // Entries systemd skips (wrong desktop, no command, unparseable) have nothing to switch,
                // and a link is never written through.
                Loader {
                    active: !app.modelData.scope && !app.modelData.link
                    sourceComponent: PanelSwitch {
                        theme: page.theme
                        objectName: "startupSwitch-" + app.modelData.id
                        checked: app.modelData.enabled
                        enabled: !page.controller.busy
                        Accessible.name: app.modelData.name
                        onToggled: { page.confirming = ""; page.controller.submit({op: "autostart", action: checked ? "enable" : "disable", id: app.modelData.id}) }
                    }
                }
            }
        }
        PanelRow {
            visible: page.ready && page.model.available.length > 0
            theme: page.theme
            divider: page.ready && page.model.apps.length > 0
            Label { text: "Start another app at login"; color: page.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
            PanelCombo {
                theme: page.theme
                key: "startupAdd"
                choices: page.ready ? page.model.available.map(item => ({label: item.name, value: item.id})) : []
                value: ""
                displayText: "Add an app…"
                Accessible.name: "Add a startup app"
                onPicked: value => { page.confirming = ""; page.controller.submit({op: "autostartAdd", app: value}) }
            }
        }
    }

    SettingsSection {
        visible: page.ready
        theme: page.theme
        title: "Started by Hyprland"
        footer: "Read from autostart.lua."
        Repeater {
            model: page.ready ? page.model.session : []
            delegate: PanelRow {
                id: command
                required property var modelData
                required property int index
                theme: page.theme
                divider: index > 0
                Label {
                    objectName: "session-" + command.index
                    text: command.modelData
                    color: page.theme.foreground; font.family: "monospace"; font.pixelSize: 12
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
            }
        }
        PanelRow {
            theme: page.theme
            divider: true
            Item { Layout.fillWidth: true }
            PanelButton { objectName: "editAutostartLua"; theme: page.theme; text: "Edit file"; onClicked: page.controller.action("autostart-file") }
        }
    }
}
