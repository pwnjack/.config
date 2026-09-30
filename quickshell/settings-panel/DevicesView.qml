pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wireless peripherals from scripts/devices/devices.sh — the same reader the
// Waybar battery module and the low-battery toast use. shell.qml re-reads it
// every 10 s while this page is on screen, and never otherwise.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    objectName: "devicesView"
    readonly property var model: controller.devices
    readonly property bool ready: Array.isArray(model)
    spacing: 8
    readonly property var glyphs: ({gamepad: 0xF0297, mouse: 0xF037D, keyboard: 0xF030C, other: 0xF0FB0})
    function value(d) {
        if (d.percent !== null && d.percent !== undefined) return d.percent + "%";
        if (d.level) return d.level.charAt(0).toUpperCase() + d.level.slice(1);
        return "No battery info";
    }
    function stateText(d) {
        if (d.state === "asleep") return d.percent !== null && d.percent !== undefined ? "Asleep · last " + d.percent + "%" : "Asleep";
        if (d.state === "receiver") return "Receiver connected";
        return d.charging ? "Charging" : "Connected";
    }

    Label { visible: !page.model; text: "Reading devices…"; color: page.theme.foreground; opacity: 0.75 }
    Label {
        objectName: "devicesError"
        visible: !!page.model && !page.ready
        text: page.model && page.model.error ? "Could not read devices: " + page.model.error : ""
        color: page.theme.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Label { objectName: "noDevices"; visible: page.ready && !page.model.length; text: "No wireless devices found."; color: page.theme.foreground; opacity: 0.75 }
    Repeater {
        model: page.ready ? page.model : []
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool alerting: modelData.alert === "low" || modelData.alert === "critical"
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 10
            color: page.theme.plate
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 14
                Text {
                    objectName: "device-" + card.modelData.id + "-icon"
                    text: String.fromCodePoint(page.glyphs[card.modelData.kind] || page.glyphs.other)
                    font.family: page.theme.iconFont; font.pixelSize: 24
                    color: page.theme.foreground
                    Accessible.ignored: true
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: card.modelData.name; color: page.theme.foreground; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { objectName: "device-" + card.modelData.id + "-state"; text: page.stateText(card.modelData); color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
                }
                Label {
                    objectName: "device-" + card.modelData.id + "-value"
                    text: page.value(card.modelData)
                    color: card.alerting ? page.theme.accent : page.theme.foreground
                    font.pixelSize: 15; font.bold: card.alerting
                    opacity: card.modelData.state === "asleep" ? 0.6 : 1
                }
            }
        }
    }
}
