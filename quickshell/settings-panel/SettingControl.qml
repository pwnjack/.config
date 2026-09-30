pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: control
    required property var row
    required property var settingState
    required property var theme
    required property var controller
    readonly property bool ready: settingState.value !== undefined && !settingState.error
    implicitHeight: body.implicitHeight + 24
    radius: 12
    color: theme.plate
    function formatted(value) {
        if (row.zeroLabel && Number(value) === 0) return row.zeroLabel;
        if (row.format === "seconds") return Math.round(value) + " s";
        if (row.format === "percent") return Math.round(value) + " %";
        if (row.format === "clock") return Math.floor(value / 60).toString().padStart(2, "0") + ":" + Math.round(value % 60).toString().padStart(2, "0");
        if (row.format === "duration") return Math.floor(value / 60) + "m" + (value % 60 ? " " + Math.round(value % 60) + "s" : "");
        if (row.format === "temperature") return Math.round(value) + " K";
        return Number(value).toFixed(row.step < 1 ? 2 : 0);
    }
    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 12
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: control.row.title; color: control.theme.foreground; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Label { objectName: control.settingState.note ? "note-" + control.row.id : ""; text: control.settingState.error || control.settingState.note || control.row.description; color: control.theme.foreground; opacity: 0.75; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
            PanelButton {
                theme: control.theme
                visible: !!control.settingState.reset
                text: "Reset"
                enabled: control.ready && !control.controller.busy && !control.controller.authPending && !control.controller.pendingDisplay
                Accessible.name: "Reset " + control.row.title
                onClicked: control.controller.reset(control.row.id)
            }
            PanelSwitch {
                id: toggle
                theme: control.theme
                objectName: "toggle-" + control.row.id
                visible: control.row.kind === "toggle"
                enabled: control.ready && !control.controller.busy && !control.controller.authPending && !control.controller.pendingDisplay
                checked: control.settingState.value === true
                Accessible.name: control.row.title
                onToggled: control.controller.change(control.row.id, checked)
            }
        }
        Loader {
            Layout.fillWidth: true
            active: control.row.kind !== "toggle"
            enabled: control.ready && !control.controller.busy && !control.controller.authPending && !control.controller.pendingDisplay
            sourceComponent: control.row.kind === "slider" ? sliderComponent : control.row.kind === "select" ? selectComponent : textComponent
        }
    }
    Component {
        id: sliderComponent
        RowLayout {
            Slider {
                id: slider
                objectName: "slider-" + control.row.id
                Layout.fillWidth: true
                implicitHeight: 40
                from: control.row.min; to: control.row.max; stepSize: control.row.step
                value: control.ready ? Number(control.settingState.value) : from
                Accessible.name: control.row.title
                onMoved: { if (!pressed) control.controller.change(control.row.id, Number(value.toFixed(4))); }
                onPressedChanged: {
                    control.controller.interacting = pressed ? control.row.id : "";
                    if (!pressed && control.ready && Math.abs(value - Number(control.settingState.value)) > 0.00001) control.controller.change(control.row.id, Number(value.toFixed(4)));
                }
                background: Rectangle {
                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth; height: 4; radius: 2; color: control.theme.background
                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: control.theme.accent }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 20; height: 20; radius: 10; color: control.theme.accent
                    border.width: slider.activeFocus ? 2 : 0; border.color: control.theme.foreground
                }
            }
            Label { text: control.ready ? control.formatted(slider.value) : "…"; color: control.theme.foreground; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70; font.pixelSize: 13 }
        }
    }
    Component {
        id: selectComponent
        PanelCombo {
            theme: control.theme
            key: control.row.id
            choices: control.row.items || control.settingState.choices || []
            value: control.settingState.value
            commitOnArrows: !control.row.auth
            Accessible.name: control.row.title
            onPicked: value => control.controller.change(control.row.id, value)
            onOpenChanged: control.controller.interacting = open ? control.row.id : ""
        }
    }
    Component {
        id: textComponent
        RowLayout {
            PanelField {
                id: entry
                theme: control.theme
                objectName: "entry-" + control.row.id
                Layout.fillWidth: true
                text: control.ready ? String(control.settingState.value) : ""
                Accessible.name: control.row.title
                onAccepted: { if ((text.trim() || control.row.optional) && text !== String(control.settingState.value)) control.controller.change(control.row.id, text); }
            }
            PanelButton { theme: control.theme; text: "Save"; enabled: (entry.text.trim() !== "" || !!control.row.optional) && entry.text !== String(control.settingState.value); onClicked: control.controller.change(control.row.id, entry.text) }
        }
    }
}
