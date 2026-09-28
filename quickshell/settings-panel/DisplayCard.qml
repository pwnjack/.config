pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "displays.mjs" as Displays

// One output. Edits are staged here and applied together: one Apply, one countdown.
Rectangle {
    id: card
    required property var monitor
    required property var theme
    required property var controller
    readonly property var saved: monitor.saved || (monitor.disabled ? {disabled: true} : Displays.AUTOMATIC)
    readonly property string savedKey: JSON.stringify(saved)
    property var staged: ({})
    readonly property var config: Object.assign({}, saved.disabled ? Displays.AUTOMATIC : saved, {disabled: !!saved.disabled}, staged)
    readonly property var scales: Displays.scaleChoices(...Displays.modeSize(config.mode, monitor))
    readonly property bool changed: Object.keys(staged).some(key => staged[key] !== (key === "disabled" ? !!saved.disabled : saved[key]))
    readonly property bool locked: monitor.handEdited || !!controller.pendingDisplay || controller.busy
    onSavedKeyChanged: staged = ({})
    function stage(key, value) {
        const next = Object.assign({}, staged, {[key]: value});
        // Scale 1 divides every mode; a scale that no longer divides the new mode falls back to it.
        if (key === "mode" && !Displays.scaleChoices(...Displays.modeSize(value, monitor)).some(c => c.value === config.scale)) next.scale = 1;
        staged = next;
    }
    function apply() {
        const c = config;
        controller.submit(c.disabled ? {op: "displayApply", output: monitor.name, disabled: true}
            : {op: "displayApply", output: monitor.name, mode: c.mode, position: c.position, scale: c.scale, transform: c.transform});
    }
    implicitHeight: body.implicitHeight + 28
    radius: 12
    color: theme.plate
    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                Label { text: card.monitor.name + " · " + (card.monitor.model || "Display"); color: card.theme.foreground; font.bold: true }
                Label { text: card.monitor.disabled ? "Off" : card.monitor.width + " × " + card.monitor.height + " · " + Number(card.monitor.refreshRate).toFixed(1) + " Hz · scale " + Number(card.monitor.scale).toFixed(2); color: card.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
            }
            PanelButton {
                theme: card.theme
                text: card.controller.mainMonitor === card.monitor.name ? "Main display" : "Set as main"
                enabled: !card.controller.busy && card.controller.mainMonitor !== card.monitor.name && !card.monitor.disabled
                onClicked: card.controller.submit({op: "mainMonitor", value: card.monitor.name})
            }
        }
        Label {
            objectName: "handEdited-" + card.monitor.name
            visible: !!card.monitor.handEdited
            text: "This display was edited by hand in monitors.lua. Use Edit file to change it."
            color: card.theme.foreground; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 12
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 4; columnSpacing: 10; rowSpacing: 8
            enabled: !card.locked && !card.config.disabled
            Label { text: "Mode"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-mode"; choices: card.monitor.choices.modes; value: card.config.mode; onPicked: value => card.stage("mode", value) }
            Label { text: "Scale"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-scale"; choices: card.scales; value: card.config.scale; onPicked: value => card.stage("scale", value) }
            Label { text: "Position"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-position"; choices: card.monitor.choices.positions; value: card.config.position; onPicked: value => card.stage("position", value) }
            Label { text: "Rotation"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-rotation"; choices: card.monitor.choices.transforms; value: card.config.transform; onPicked: value => card.stage("transform", value) }
        }
        RowLayout {
            Layout.fillWidth: true
            Switch {
                objectName: "enableDisplay-" + card.monitor.name
                text: "On"
                enabled: !card.locked
                checked: !card.config.disabled
                onToggled: card.stage("disabled", !checked)
                palette.windowText: card.theme.foreground
            }
            Item { Layout.fillWidth: true }
            PanelButton { objectName: "automaticDisplay-" + card.monitor.name; theme: card.theme; text: "Automatic"; enabled: !card.locked && card.monitor.saved !== null; onClicked: card.controller.submit({op: "displayApply", output: card.monitor.name, automatic: true}) }
            PanelButton { objectName: "applyDisplay-" + card.monitor.name; theme: card.theme; text: "Apply"; enabled: !card.locked && card.changed; onClicked: card.apply() }
        }
    }
}
