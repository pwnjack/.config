pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// The panel's dropdown: themed, in-scene popup capped at 320 px, and a value
// missing from its choices is displayed instead of going blank.
ComboBox {
    id: combo
    required property var theme
    property var choices: []
    property var value
    property string key: ""
    readonly property bool open: popup.visible
    signal picked(var value)
    objectName: "select-" + key
    implicitHeight: 40
    model: combo.choices
    textRole: "label"
    currentIndex: combo.choices.findIndex(item => String(item.value) === String(combo.value))
    displayText: currentIndex < 0 ? String(combo.value ?? "") : currentText
    onActivated: index => combo.picked(combo.choices[index].value)
    palette.button: combo.theme.background
    palette.buttonText: combo.theme.foreground
    palette.base: combo.theme.background
    palette.text: combo.theme.foreground
    palette.highlight: combo.theme.accent
    palette.highlightedText: combo.theme.accentText
    contentItem: Text {
        text: combo.displayText
        color: combo.theme.foreground
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
        color: combo.theme.foreground
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
            color: choice.highlighted ? combo.theme.accentText : combo.theme.foreground
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            leftPadding: 8
        }
        background: Rectangle { radius: 6; color: choice.highlighted ? combo.theme.accent : combo.theme.plate }
    }
    popup: Popup {
        objectName: "choices-" + combo.key
        // Keep the popup in the panel scene, independent of platform menus.
        popupType: Popup.Item
        y: combo.height + 4
        width: combo.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        background: Rectangle {
            radius: 10
            color: combo.theme.plate
            border.color: Qt.rgba(combo.theme.foreground.r, combo.theme.foreground.g, combo.theme.foreground.b, 0.25)
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }
    }
    background: Rectangle { color: combo.theme.background; radius: 8; border.width: combo.activeFocus ? 2 : 1; border.color: combo.activeFocus ? combo.theme.accent : Qt.rgba(combo.theme.foreground.r, combo.theme.foreground.g, combo.theme.foreground.b, 0.25) }
}
