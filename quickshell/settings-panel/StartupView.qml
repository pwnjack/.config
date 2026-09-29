pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Hyprland's own session (read-only, parsed from autostart.lua) and the XDG
// autostart set that uwsm's systemd generator launches at login.
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
    spacing: 8
    onModelChanged: confirming = ""
    Timer { id: confirmTimer; interval: page.confirmMs; onTriggered: page.confirming = "" }

    Label { visible: !page.model; text: "Reading startup apps…"; color: page.theme.foreground; opacity: 0.75 }
    Label {
        objectName: "startupError"
        visible: !!page.model && !!page.model.error
        text: page.model && page.model.error ? "Could not read startup apps: " + page.model.error : ""
        color: page.theme.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    RowLayout {
        visible: page.ready
        Layout.fillWidth: true
        Label { text: "Started by Hyprland's config"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        PanelButton { objectName: "editAutostartLua"; theme: page.theme; text: "Edit file"; onClicked: page.controller.action("autostart-file") }
    }
    Repeater {
        model: page.ready ? page.model.session : []
        delegate: Label {
            required property var modelData
            required property int index
            objectName: "session-" + index
            text: modelData
            color: page.theme.foreground; opacity: 0.85; font.family: "monospace"; font.pixelSize: 12
            Layout.fillWidth: true; elide: Text.ElideRight
        }
    }

    RowLayout {
        visible: page.ready
        Layout.fillWidth: true; Layout.topMargin: 12
        Label { text: "Apps"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Label { text: "Takes effect at next login"; color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
    }
    Repeater {
        model: page.ready ? page.model.apps : []
        delegate: Rectangle {
            id: app
            required property var modelData
            objectName: "startup-" + modelData.id
            Layout.fillWidth: true
            implicitHeight: appRow.implicitHeight + 16
            radius: 10; color: page.theme.plate
            RowLayout {
                id: appRow
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: app.modelData.name; color: page.theme.foreground; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label {
                        objectName: "startupStatus-" + app.modelData.id
                        text: [app.modelData.scope, app.modelData.status.label,
                            app.modelData.ignoredGnomeFlag ? "X-GNOME-Autostart-enabled has no effect under systemd" : "",
                            app.modelData.link ? "A link; edit it by hand" : "",
                            app.modelData.origin === "user" ? "In ~/.config/autostart" : app.modelData.origin === "override" && !app.modelData.staleOverride && app.modelData.enabled ? "Your version in ~/.config/autostart" : ""].filter(Boolean).join(" · ")
                        color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Loader {
                    active: !!app.modelData.removable && !app.modelData.link
                    sourceComponent: PanelButton {
                        objectName: "startupRemove-" + app.modelData.id
                        theme: page.theme; text: page.confirming === app.modelData.id ? (app.modelData.origin === "override" ? "Confirm: starts again at login" : "Confirm remove") : "Remove"
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
                    sourceComponent: Switch {
                        objectName: "startupSwitch-" + app.modelData.id
                        checked: app.modelData.enabled
                        enabled: !page.controller.busy
                        Accessible.name: app.modelData.name
                        onToggled: { page.confirming = ""; page.controller.submit({op: "autostart", action: checked ? "enable" : "disable", id: app.modelData.id}) }
                    }
                }
            }
        }
    }
    PanelCombo {
        visible: page.ready && page.model.available.length > 0
        Layout.fillWidth: true
        theme: page.theme
        key: "startupAdd"
        choices: page.ready ? page.model.available.map(item => ({label: item.name, value: item.id})) : []
        value: ""
        displayText: "Add an app…"
        Accessible.name: "Add a startup app"
        onPicked: value => { page.confirming = ""; page.controller.submit({op: "autostartAdd", app: value}) }
    }
}
