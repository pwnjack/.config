pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wireless peripherals from scripts/devices/devices.sh — the same reader the Waybar
// battery module and the low-battery toast use. shell.qml re-reads it every 10 s
// while this page is on screen, and never otherwise.
SettingsSection {
    id: page
    required property var controller
    objectName: "devicesView"
    readonly property var model: controller.devices
    readonly property bool ready: Array.isArray(model)
    readonly property var glyphs: ({gamepad: 0xF0297, mouse: 0xF037D, keyboard: 0xF030C, other: 0xF0FB0})
    function value(d) {
        if (d.percent !== null && d.percent !== undefined) return d.percent + "%";
        if (d.level) return d.level.charAt(0).toUpperCase() + d.level.slice(1);
        return "No battery info";
    }
    function stateText(d) {
        if (d.state === "asleep") return d.percent !== null && d.percent !== undefined ? "Asleep · last " + d.percent + "%" : "Asleep";
        return d.charging ? "Charging" : "Connected";
    }
    title: "Wireless devices"
    footer: "Battery levels refresh every 10 seconds while this page is open."
    PanelRow {
        visible: !page.model
        theme: page.theme
        Label { text: "Reading devices…"; color: page.theme.dim; font.pixelSize: 13 }
    }
    PanelRow {
        visible: !!page.model && !page.ready
        theme: page.theme
        Label {
            objectName: "devicesError"
            text: page.model && page.model.error ? "Could not read devices: " + page.model.error : ""
            color: page.theme.warn; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }
    PanelRow {
        visible: page.ready && !page.model.length
        theme: page.theme
        Label { objectName: "noDevices"; text: "No wireless devices found."; color: page.theme.dim; font.pixelSize: 13 }
    }
    Repeater {
        model: page.ready ? page.model : []
        delegate: PanelRow {
            id: device
            required property var modelData
            required property int index
            readonly property bool alerting: modelData.alert === "low" || modelData.alert === "critical"
            theme: page.theme
            divider: index > 0
            Rectangle {
                implicitWidth: 30; implicitHeight: 30; radius: 8
                color: Qt.rgba(page.theme.accent.r, page.theme.accent.g, page.theme.accent.b, 0.22)
                Text {
                    objectName: "device-" + device.modelData.id + "-icon"
                    anchors.centerIn: parent
                    text: String.fromCodePoint(page.glyphs[device.modelData.kind] || page.glyphs.other)
                    font.family: page.theme.iconFont; font.pixelSize: 18
                    color: page.theme.accent
                    Accessible.ignored: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: device.modelData.name; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { objectName: "device-" + device.modelData.id + "-state"; text: page.stateText(device.modelData); color: page.theme.dim; font.pixelSize: 12 }
            }
            Label {
                objectName: "device-" + device.modelData.id + "-value"
                text: page.value(device.modelData)
                color: device.alerting ? page.theme.warn : page.theme.foreground
                font.pixelSize: 13; font.weight: device.alerting ? Font.DemiBold : Font.Normal
                opacity: device.modelData.state === "asleep" ? 0.6 : 1
            }
        }
    }
}
