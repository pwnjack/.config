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
    readonly property var model: controller.startup
    spacing: 8

    Label { visible: !page.model; text: "Reading startup apps…"; color: page.theme.foreground; opacity: 0.75 }

    RowLayout {
        visible: !!page.model
        Layout.fillWidth: true
        Label { text: "Started by Hyprland's config"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        PanelButton { objectName: "editAutostartLua"; theme: page.theme; text: "Edit file"; onClicked: page.controller.action("autostart-file") }
    }
    Repeater {
        model: page.model ? page.model.session : []
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
        visible: !!page.model
        Layout.fillWidth: true; Layout.topMargin: 12
        Label { text: "Apps"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Label { text: "Takes effect at next login"; color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
    }
    Repeater {
        model: page.model ? page.model.apps : []
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
                            app.modelData.origin === "user" ? "Added by you" : ""].filter(Boolean).join(" · ")
                        color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Loader {
                    active: app.modelData.origin === "user"
                    sourceComponent: PanelButton {
                        objectName: "startupRemove-" + app.modelData.id
                        theme: page.theme; text: "Remove"
                        enabled: !page.controller.busy
                        onClicked: page.controller.submit({op: "autostart", action: "remove", id: app.modelData.id})
                    }
                }
                // Entries systemd skips (wrong desktop, no command, unparseable) have nothing to switch.
                Loader {
                    active: !app.modelData.scope
                    sourceComponent: Switch {
                        objectName: "startupSwitch-" + app.modelData.id
                        checked: app.modelData.enabled
                        enabled: !page.controller.busy
                        Accessible.name: app.modelData.name
                        onToggled: page.controller.submit({op: "autostart", action: checked ? "enable" : "disable", id: app.modelData.id})
                    }
                }
            }
        }
    }
    PanelCombo {
        visible: !!page.model && page.model.available.length > 0
        Layout.fillWidth: true
        theme: page.theme
        key: "startupAdd"
        choices: page.model ? page.model.available.map(item => ({label: item.name, value: item.id})) : []
        value: ""
        displayText: "Add an app…"
        Accessible.name: "Add a startup app"
        onPicked: value => page.controller.submit({op: "autostartAdd", app: value})
    }
}
