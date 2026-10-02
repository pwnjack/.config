pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "pages.mjs" as Pages

// One catalog row: title and secondary line on the left, then the reset button, then
// the control. Controls sit right-aligned at fixed widths, so they line up down a page
// the way a macOS settings pane does.
PanelRow {
    id: control
    required property var row
    required property var settingState
    required property var controller
    readonly property bool ready: settingState.value !== undefined && !settingState.error
    // Shown but not editable while the toggle it depends on is off (blur size without blur).
    readonly property bool dependencyOff: Pages.dependencyOff(row, controller.values)
    readonly property bool idle: !controller.busy && !controller.authPending && !controller.pendingDisplay
    readonly property bool editable: ready && idle && !dependencyOff
    readonly property string secondary: settingState.error || settingState.note || row.description || ""
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
        Layout.fillWidth: true
        spacing: 2
        opacity: control.dependencyOff ? 0.42 : 1
        Label {
            text: control.row.title
            color: control.theme.foreground
            font.pixelSize: 13; font.weight: Font.Medium
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        RowLayout {
            visible: !!control.secondary
            Layout.fillWidth: true
            spacing: 5
            Text {
                visible: !!control.settingState.error
                // md-alert_outline: an error is marked by shape, not by colour alone.
                text: control.theme.glyph("f002a")
                font.family: control.theme.iconFont; font.pixelSize: 12
                color: control.theme.warn
                Accessible.ignored: true
            }
            Label {
                objectName: control.settingState.note ? "note-" + control.row.id : control.settingState.error ? "error-" + control.row.id : ""
                text: control.secondary
                color: control.settingState.error ? control.theme.warn : control.theme.dim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
    IconButton {
        objectName: "reset-" + control.row.id
        theme: control.theme
        visible: !!control.settingState.reset
        flat: true
        size: 24
        // md-restore
        glyph: control.theme.glyph("f099b")
        label: "Reset " + control.row.title
        tip: "Reset to default"
        enabled: control.ready && control.idle
        onClicked: control.controller.reset(control.row.id)
    }
    PanelSwitch {
        objectName: "toggle-" + control.row.id
        theme: control.theme
        visible: control.row.kind === "toggle"
        enabled: control.editable
        checked: control.settingState.value === true
        Accessible.name: control.row.title
        onToggled: control.controller.change(control.row.id, checked)
    }
    Loader {
        active: control.row.kind !== "toggle"
        visible: active
        enabled: control.editable
        Layout.preferredWidth: control.row.kind === "slider" ? 290 : item ? item.implicitWidth : 0
        sourceComponent: control.row.kind === "slider" ? sliderComponent : control.row.kind === "select" ? selectComponent : textComponent
    }
    Component {
        id: sliderComponent
        RowLayout {
            spacing: 10
            Label { visible: !!control.row.ends; text: control.row.ends ? control.row.ends[0] : ""; color: control.theme.dim; font.pixelSize: 11 }
            Slider {
                id: slider
                objectName: "slider-" + control.row.id
                Layout.fillWidth: true
                implicitHeight: 28
                from: control.row.min; to: control.row.max; stepSize: control.row.step
                // An inverted row (a duration shown as a speed) draws mirrored; `stored` is what is written.
                value: control.ready ? Pages.mirror(control.row, Number(control.settingState.value)) : from
                readonly property real stored: Pages.mirror(control.row, value)
                Accessible.name: control.row.title
                onMoved: { if (!pressed) control.controller.change(control.row.id, Number(stored.toFixed(4))); }
                onPressedChanged: {
                    control.controller.interacting = pressed ? control.row.id : "";
                    if (!pressed && control.ready && Math.abs(stored - Number(control.settingState.value)) > 0.00001)
                        control.controller.change(control.row.id, Number(stored.toFixed(4)));
                }
                background: Rectangle {
                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth; height: 4; radius: 2
                    color: Qt.rgba(control.theme.foreground.r, control.theme.foreground.g, control.theme.foreground.b, 0.16)
                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: control.theme.accent }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 16; height: 16; radius: 8
                    color: control.theme.foreground
                    border.width: slider.activeFocus ? 2 : 0
                    border.color: control.theme.accent
                }
            }
            Label { visible: !!control.row.ends; text: control.row.ends ? control.row.ends[1] : ""; color: control.theme.dim; font.pixelSize: 11 }
            Label {
                objectName: "value-" + control.row.id
                visible: !control.row.ends
                text: control.ready ? control.formatted(slider.stored) : "…"
                color: control.theme.foreground
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 12
                font.features: { "tnum": 1 }
                Layout.preferredWidth: 52
            }
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
            id: textRow
            spacing: 8
            readonly property bool changed: control.ready && entry.text !== String(control.settingState.value)
            // Apply sits left of the field, so the field's edge stays aligned with every other control.
            PanelButton {
                objectName: "apply-" + control.row.id
                theme: control.theme
                primary: true
                text: "Apply"
                visible: textRow.changed
                enabled: entry.text.trim() !== "" || !!control.row.optional
                onClicked: control.controller.change(control.row.id, entry.text)
            }
            PanelField {
                id: entry
                theme: control.theme
                objectName: "entry-" + control.row.id
                Layout.preferredWidth: 200
                pending: textRow.changed
                text: control.ready ? String(control.settingState.value) : ""
                Accessible.name: control.row.title
                onAccepted: { if ((text.trim() || control.row.optional) && text !== String(control.settingState.value)) control.controller.change(control.row.id, text); }
            }
        }
    }
}
