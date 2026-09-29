pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi, wired and VPN in one view. Every write goes through controller.submit,
// so the queue, the stdin path and the post-write refresh are the ones every row uses.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    readonly property var model: controller.network
    readonly property var radio: controller.values["network.wifi"] || ({})
    property string expanded: ""
    spacing: 8
    // Nerd Font glyphs by code point: pasted private-use characters vanish. Index = bars (1-4).
    readonly property var bars: ["", String.fromCodePoint(0xF091F), String.fromCodePoint(0xF0922), String.fromCodePoint(0xF0925), String.fromCodePoint(0xF0928)]
    readonly property string lock: String.fromCodePoint(0xF033E)

    Label { objectName: "networkDown"; visible: !!page.model && !page.model.running; text: "NetworkManager is not running."; color: page.theme.foreground }
    Label { visible: !page.model; text: "Reading connections…"; color: page.theme.foreground; opacity: 0.75 }

    RowLayout {
        visible: !!page.model?.running
        Layout.fillWidth: true
        Label { text: "Wi-Fi"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Label { visible: !!page.radio.error; text: page.radio.error || ""; color: page.theme.foreground; opacity: 0.75 }
        PanelButton { objectName: "networkEditor"; theme: page.theme; text: "Advanced…"; onClicked: page.controller.action("networkEditor") }
        Switch {
            objectName: "wifiRadio"
            visible: page.radio.value !== undefined
            checked: page.radio.value === true
            enabled: !page.controller.busy
            Accessible.name: "Wi-Fi"
            onToggled: page.controller.change("network.wifi", checked)
        }
    }
    Repeater {
        model: page.model?.running && page.model.wifi.enabled ? page.model.wifi.networks : []
        delegate: Rectangle {
            id: entry
            required property var modelData
            readonly property bool secured: modelData.security === "psk" || modelData.security === "sae"
            readonly property bool askPassword: page.expanded === modelData.ssid
            objectName: "wifi-" + modelData.ssid
            Layout.fillWidth: true
            implicitHeight: entryColumn.implicitHeight + 16
            radius: 10
            color: page.theme.plate
            border.color: modelData.active ? page.theme.accent : "transparent"
            MouseArea {
                anchors.fill: parent
                enabled: !page.controller.busy && entry.modelData.security !== "unsupported" && !entry.modelData.activating
                onClicked: {
                    if (entry.modelData.known || !entry.secured) {
                        page.expanded = "";
                        page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid});
                    } else page.expanded = entry.askPassword ? "" : entry.modelData.ssid;
                }
            }
            ColumnLayout {
                id: entryColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                RowLayout {
                    Label { text: page.bars[entry.modelData.bars]; color: page.theme.foreground; font.pixelSize: 18 }
                    Label { text: entry.modelData.ssid; color: page.theme.foreground; font.bold: entry.modelData.active; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { visible: entry.modelData.security !== "open" && entry.modelData.security !== "owe"; text: page.lock; color: page.theme.foreground; opacity: 0.75 }
                    Label { text: entry.modelData.active ? "Connected" : entry.modelData.activating ? "Connecting…" : entry.modelData.known ? "Saved" : ""; color: page.theme.foreground; opacity: 0.75 }
                    Loader {
                        active: entry.modelData.known
                        sourceComponent: PanelButton {
                            objectName: "forget-" + entry.modelData.ssid
                            theme: page.theme; text: "Forget"
                            enabled: !page.controller.busy
                            onClicked: page.controller.submit({op: "wifiForget", ssid: entry.modelData.ssid})
                        }
                    }
                    Loader {
                        active: entry.modelData.security === "unsupported"
                        sourceComponent: PanelButton {
                            objectName: "advanced-" + entry.modelData.ssid
                            theme: page.theme; text: "Advanced…"
                            onClicked: page.controller.action("networkEditor")
                        }
                    }
                }
                RowLayout {
                    visible: entry.askPassword
                    TextField {
                        id: psk
                        objectName: "psk-" + entry.modelData.ssid
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: "Password"
                        color: page.theme.foreground
                        Accessible.name: "Password for " + entry.modelData.ssid
                        onAccepted: { if (connectButton.enabled) connectButton.clicked(); }
                    }
                    PanelButton {
                        id: connectButton
                        objectName: "connect-" + entry.modelData.ssid
                        theme: page.theme; text: "Connect"
                        // WPA2 needs 8–63 characters; WPA3-SAE accepts any non-empty password (network.mjs validates both).
                        enabled: (entry.modelData.security === "sae" ? psk.text.length > 0 : psk.text.length >= 8) && !page.controller.busy
                        onClicked: {
                            page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid, psk: psk.text});
                            psk.text = "";
                            page.expanded = "";
                        }
                    }
                }
            }
        }
    }

    Label { visible: !!page.model?.running && page.model.wired.length > 0; text: "Wired"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.topMargin: 8 }
    Repeater {
        model: page.model?.running ? page.model.wired : []
        delegate: Label {
            required property var modelData
            Layout.fillWidth: true
            color: page.theme.foreground
            text: modelData.carrier
                ? modelData.iface + " · " + modelData.speed + " Mb/s · " + (modelData.ip4 || "no address") + (modelData.gateway ? " via " + modelData.gateway : "")
                : modelData.iface + " · Cable unplugged"
        }
    }

    RowLayout {
        visible: !!page.model?.running && (page.model.vpn.length > 0 || !!page.model.proton)
        Layout.fillWidth: true; Layout.topMargin: 8
        Label { text: "VPN"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        PanelButton {
            objectName: "protonApp"
            visible: !!page.model?.proton
            theme: page.theme; text: "Open Proton VPN"
            onClicked: page.controller.action("protonApp")
        }
    }
    Repeater {
        model: page.model?.running ? page.model.vpn : []
        delegate: RowLayout {
            id: vpnRow
            required property var modelData
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                color: page.theme.foreground
                text: vpnRow.modelData.name + " · " + (vpnRow.modelData.state === "activated" ? "Connected" + (vpnRow.modelData.iface ? " on " + vpnRow.modelData.iface : "")
                    : vpnRow.modelData.state === "activating" ? "Connecting…" : "Off")
            }
            Loader {
                active: vpnRow.modelData.control === "switch"
                sourceComponent: Switch {
                    objectName: "vpn-" + vpnRow.modelData.uuid
                    checked: vpnRow.modelData.state !== "off"
                    enabled: !page.controller.busy
                    Accessible.name: vpnRow.modelData.name
                    onToggled: page.controller.submit({op: "vpn", uuid: vpnRow.modelData.uuid, active: checked})
                }
            }
        }
    }
}
