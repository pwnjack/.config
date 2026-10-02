pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "displays.mjs" as Displays

// One output as one group of rows. Edits are staged here and applied together:
// one Apply, one countdown.
SettingsSection {
    id: card
    required property var monitor
    required property var controller
    readonly property var saved: monitor.saved || (monitor.disabled ? {disabled: true} : Displays.AUTOMATIC)
    // Staged edits live on the controller: a refresh recreates every card.
    readonly property var staged: controller.stagedDisplays[monitor.name] || ({})
    readonly property var config: Object.assign({}, saved.disabled ? Displays.AUTOMATIC : saved, {disabled: !!saved.disabled}, staged)
    readonly property var scales: Displays.scaleChoices(...Displays.modeSize(config.mode, monitor))
    readonly property bool changed: Object.keys(staged).some(key => staged[key] !== (key === "disabled" ? !!saved.disabled : saved[key]))
    readonly property bool locked: monitor.handEdited || !!controller.pendingDisplay || controller.busy
    function stage(key, value) {
        const next = Object.assign({}, staged, {[key]: value});
        // Scale 1 divides every mode; a scale that no longer divides the new mode falls back to it.
        if (key === "mode" && !Displays.scaleChoices(...Displays.modeSize(value, monitor)).some(c => c.value === config.scale)) next.scale = 1;
        // A field set back to its saved value is no longer an edit.
        for (const field of Object.keys(next))
            if (next[field] === (field === "disabled" ? !!saved.disabled : saved[field])) delete next[field];
        if (!Object.keys(next).length) return unstage();
        controller.stagedDisplays = Object.assign({}, controller.stagedDisplays, {[monitor.name]: next});
    }
    function unstage() {
        const rest = Object.assign({}, controller.stagedDisplays);
        delete rest[monitor.name];
        controller.stagedDisplays = rest;
    }
    // An open dropdown keeps display refreshes from recreating this card under it.
    function interact(open) { controller.interacting = open ? "display:" + monitor.name : ""; }
    function apply() {
        const c = config;
        unstage();
        controller.submit(c.disabled ? {op: "displayApply", output: monitor.name, disabled: true}
            : {op: "displayApply", output: monitor.name, mode: c.mode, position: c.position, scale: c.scale, transform: c.transform});
    }
    title: monitor.name + " · " + (monitor.model || "Display")
    PanelRow {
        theme: card.theme
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: card.monitor.disabled ? "Off" : card.monitor.width + " × " + card.monitor.height + " · " + Number(card.monitor.refreshRate).toFixed(1) + " Hz · scale " + Number(card.monitor.scale).toFixed(2)
                color: card.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium
                Layout.fillWidth: true
            }
            Label {
                objectName: "handEdited-" + card.monitor.name
                visible: !!card.monitor.handEdited
                text: "Edited by hand in monitors.lua. Use Edit file below to change it."
                color: card.theme.dim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
        PanelButton {
            objectName: "mainDisplay-" + card.monitor.name
            theme: card.theme
            text: card.controller.mainMonitor === card.monitor.name ? "Main display" : "Set as main"
            enabled: !card.controller.busy && !card.controller.pendingDisplay && card.controller.mainMonitor !== card.monitor.name && !card.monitor.disabled
            onClicked: card.controller.submit({op: "mainMonitor", value: card.monitor.name})
        }
        PanelSwitch {
            objectName: "enableDisplay-" + card.monitor.name
            theme: card.theme
            text: "On"
            enabled: !card.locked
            checked: !card.config.disabled
            onToggled: card.stage("disabled", !checked)
        }
    }
    PanelRow {
        theme: card.theme; divider: true
        enabled: !card.locked && !card.config.disabled
        Label { text: "Mode"; color: card.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
        PanelCombo { Layout.preferredWidth: 240; theme: card.theme; key: card.monitor.name + "-mode"; choices: card.monitor.choices.modes; value: card.config.mode; onOpenChanged: card.interact(open); onPicked: value => card.stage("mode", value) }
    }
    PanelRow {
        theme: card.theme; divider: true
        enabled: !card.locked && !card.config.disabled
        Label { text: "Scale"; color: card.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
        PanelCombo { Layout.preferredWidth: 240; theme: card.theme; key: card.monitor.name + "-scale"; choices: card.scales; value: card.config.scale; onOpenChanged: card.interact(open); onPicked: value => card.stage("scale", value) }
    }
    PanelRow {
        theme: card.theme; divider: true
        enabled: !card.locked && !card.config.disabled
        Label { text: "Position"; color: card.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
        PanelCombo { Layout.preferredWidth: 240; theme: card.theme; key: card.monitor.name + "-position"; choices: card.monitor.choices.positions; value: card.config.position; onOpenChanged: card.interact(open); onPicked: value => card.stage("position", value) }
    }
    PanelRow {
        theme: card.theme; divider: true
        enabled: !card.locked && !card.config.disabled
        Label { text: "Rotation"; color: card.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
        PanelCombo { Layout.preferredWidth: 240; theme: card.theme; key: card.monitor.name + "-rotation"; choices: card.monitor.choices.transforms; value: card.config.transform; onOpenChanged: card.interact(open); onPicked: value => card.stage("transform", value) }
    }
    PanelRow {
        theme: card.theme; divider: true
        Item { Layout.fillWidth: true }
        PanelButton { objectName: "automaticDisplay-" + card.monitor.name; theme: card.theme; text: "Automatic"; enabled: !card.locked && card.monitor.saved !== null; onClicked: { card.unstage(); card.controller.submit({op: "displayApply", output: card.monitor.name, automatic: true}); } }
        PanelButton { objectName: "applyDisplay-" + card.monitor.name; theme: card.theme; primary: true; text: "Apply"; enabled: !card.locked && card.changed; onClicked: card.apply() }
    }
}
