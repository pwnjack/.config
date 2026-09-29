pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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
    property string filter: ""
    property int filterIndex: -1
    readonly property bool filterable: combo.choices.length > 20
    readonly property var shown: {
        const words = combo.filter.toLocaleLowerCase().trim();
        return words ? combo.choices.filter(item => String(item.label).toLocaleLowerCase().includes(words)) : combo.choices;
    }
    model: combo.shown
    textRole: "label"
    currentIndex: combo.shown.findIndex(item => String(item.value) === String(combo.value))
    displayText: currentIndex < 0 ? (combo.choices.find(item => String(item.value) === String(combo.value))?.label ?? String(combo.value ?? "")) : currentText
    onActivated: index => { combo.picked(combo.shown[index].value); combo.filter = ""; }
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
        highlighted: combo.filterable ? combo.filterIndex === index : combo.highlightedIndex === index
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
        onOpened: { combo.filter = ""; combo.filterIndex = -1; if (combo.filterable) filterField.forceActiveFocus(); }
        background: Rectangle {
            radius: 10
            color: combo.theme.plate
            border.color: Qt.rgba(combo.theme.foreground.r, combo.theme.foreground.g, combo.theme.foreground.b, 0.25)
        }
        contentItem: ColumnLayout {
            spacing: 4
            TextField {
                id: filterField
                objectName: "filter-" + combo.key
                visible: combo.filterable
                Layout.fillWidth: true
                placeholderText: "Type to filter"
                text: combo.filter
                onTextEdited: { combo.filter = text; combo.filterIndex = -1; }
                color: combo.theme.foreground
                Keys.onDownPressed: combo.filterIndex = Math.min(combo.filterIndex + 1, combo.shown.length - 1)
                Keys.onUpPressed: combo.filterIndex = Math.max(combo.filterIndex - 1, 0)
                Keys.onReturnPressed: { if (combo.filterIndex >= 0) { combo.activated(combo.filterIndex); combo.popup.close(); } }
                Keys.onEscapePressed: combo.popup.close()
            }
            ListView {
                clip: true
                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, combo.filterable ? 272 : 312)
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.filterable ? combo.filterIndex : combo.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
            }
        }
    }
    background: Rectangle { color: combo.theme.background; radius: 8; border.width: combo.activeFocus ? 2 : 1; border.color: combo.activeFocus ? combo.theme.accent : Qt.rgba(combo.theme.foreground.r, combo.theme.foreground.g, combo.theme.foreground.b, 0.25) }
}
