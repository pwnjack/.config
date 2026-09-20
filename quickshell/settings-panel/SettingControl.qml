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
                Label { text: control.settingState.error || control.row.description; color: control.theme.foreground; opacity: 0.75; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
            PanelButton {
                theme: control.theme
                visible: !!control.settingState.reset
                text: "Reset"
                enabled: control.ready && !control.controller.busy
                Accessible.name: "Reset " + control.row.title
                onClicked: control.controller.reset(control.row.id)
            }
            Switch {
                id: toggle
                objectName: "toggle-" + control.row.id
                visible: control.row.kind === "toggle"
                enabled: control.ready && !control.controller.busy
                checked: control.settingState.value === true
                Accessible.name: control.row.title
                onToggled: control.controller.change(control.row.id, checked)
                implicitWidth: 54; implicitHeight: 40
                indicator: Rectangle {
                    width: 48; height: 26; x: 3; y: 7; radius: 13
                    color: toggle.checked ? control.theme.accent : control.theme.background
                    border.width: toggle.activeFocus ? 2 : 1
                    border.color: toggle.activeFocus ? control.theme.accent : control.theme.foreground
                    Rectangle { width: 18; height: 18; radius: 9; y: 4; x: toggle.checked ? 26 : 4; color: toggle.checked ? control.theme.accentText : control.theme.foreground }
                }
            }
        }
        Loader {
            Layout.fillWidth: true
            active: control.row.kind !== "toggle"
            enabled: control.ready && !control.controller.busy
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
                onPressedChanged: { if (!pressed && control.ready && Math.abs(value - Number(control.settingState.value)) > 0.00001) control.controller.change(control.row.id, Number(value.toFixed(4))); }
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
        ComboBox {
            id: combo
            objectName: "select-" + control.row.id
            implicitHeight: 40
            model: control.row.items
            textRole: "label"
            currentIndex: control.row.items.findIndex(item => item.value === String(control.settingState.value))
            Accessible.name: control.row.title
            onActivated: index => control.controller.change(control.row.id, control.row.items[index].value)
            palette.button: control.theme.background
            palette.buttonText: control.theme.foreground
            palette.base: control.theme.background
            palette.text: control.theme.foreground
            palette.highlight: control.theme.accent
            palette.highlightedText: control.theme.accentText
            contentItem: Text {
                text: combo.displayText
                color: control.theme.foreground
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                leftPadding: 12
                rightPadding: 32
            }
            indicator: Text {
                x: combo.width - width - 12
                y: (combo.height - height) / 2
                text: "▾"
                color: control.theme.foreground
                font.pixelSize: 16
            }
            delegate: ItemDelegate {
                id: choice
                required property int index
                required property var modelData
                width: combo.width - 8
                height: 40
                highlighted: combo.highlightedIndex === index
                contentItem: Text {
                    text: choice.modelData.label
                    color: choice.highlighted ? control.theme.accentText : control.theme.foreground
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    leftPadding: 8
                }
                background: Rectangle { radius: 6; color: choice.highlighted ? control.theme.accent : control.theme.plate }
            }
            popup: Popup {
                objectName: "choices-" + control.row.id
                // Keep the popup in the panel scene, independent of platform menus.
                popupType: Popup.Item
                y: combo.height + 4
                width: combo.width
                padding: 4
                implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
                background: Rectangle {
                    radius: 10
                    color: control.theme.plate
                    border.color: Qt.rgba(control.theme.foreground.r, control.theme.foreground.g, control.theme.foreground.b, 0.25)
                }
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: combo.popup.visible ? combo.delegateModel : null
                    currentIndex: combo.highlightedIndex
                    boundsBehavior: Flickable.StopAtBounds
                }
            }
            background: Rectangle { color: control.theme.background; radius: 8; border.width: combo.activeFocus ? 2 : 1; border.color: combo.activeFocus ? control.theme.accent : Qt.rgba(control.theme.foreground.r, control.theme.foreground.g, control.theme.foreground.b, 0.25) }
        }
    }
    Component {
        id: textComponent
        RowLayout {
            TextField {
                id: entry
                objectName: "entry-" + control.row.id
                Layout.fillWidth: true
                implicitHeight: 40
                text: control.ready ? String(control.settingState.value) : ""
                selectByMouse: true
                color: control.theme.foreground
                Accessible.name: control.row.title
                onAccepted: { if (text.trim() && text !== String(control.settingState.value)) control.controller.change(control.row.id, text); }
                background: Rectangle { color: control.theme.background; radius: 8; border.width: entry.activeFocus ? 2 : 1; border.color: entry.activeFocus ? control.theme.accent : Qt.rgba(control.theme.foreground.r, control.theme.foreground.g, control.theme.foreground.b, 0.25) }
            }
            PanelButton { theme: control.theme; text: "Save"; enabled: entry.text.trim() !== "" && entry.text !== String(control.settingState.value); onClicked: control.controller.change(control.row.id, entry.text) }
        }
    }
}
