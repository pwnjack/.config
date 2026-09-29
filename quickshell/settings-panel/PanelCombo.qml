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
    property bool commitOnArrows: true
    readonly property bool open: popup.visible
    signal picked(var value)
    objectName: "select-" + key
    implicitHeight: 40
    property string filter: ""
    property int filterIndex: -1
    readonly property bool filterable: combo.choices.length > 20
    readonly property var shown: {
        const words = combo.filter.toLocaleLowerCase().trim();
        return words ? combo.choices.filter(item => String(item.label).toLocaleLowerCase().includes(words) || String(item.value).toLocaleLowerCase().includes(words)) : combo.choices;
    }
    model: combo.shown
    textRole: "label"
    currentIndex: combo.shown.findIndex(item => String(item.value) === String(combo.value))
    displayText: currentIndex < 0 ? (combo.choices.find(item => String(item.value) === String(combo.value))?.label ?? String(combo.value ?? "")) : currentText
    onActivated: index => { if (index >= 0 && index < combo.shown.length) combo.picked(combo.shown[index].value); combo.filter = ""; }
    // A closed ComboBox commits on arrows, Home/End/PageUp/PageDown and type-ahead
    // letters. For rows whose write asks for a password, every such key opens the
    // list instead (a typed letter seeds the filter), so no stray key changes a system setting.
    Keys.onPressed: event => {
        if (combo.open || combo.commitOnArrows) return;
        const navigation = [Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown].includes(event.key);
        const typed = !navigation && event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (!navigation && !typed) return;
        combo.popup.open();
        if (typed && combo.filterable) { combo.filter = event.text; combo.filterIndex = combo.shown.length ? 0 : -1; }
        event.accepted = true;
    }
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
        hoverEnabled: true
        highlighted: combo.filterable ? combo.filterIndex === index : combo.highlightedIndex === index
        onHoveredChanged: { if (hovered && combo.filterable) combo.filterIndex = index; }
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
        onClosed: { combo.filter = ""; combo.filterIndex = -1; }
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
                onTextEdited: { combo.filter = text; combo.filterIndex = combo.shown.length && combo.filter ? 0 : -1; }
                color: combo.theme.foreground
                // With no matches there is nothing to highlight: the index stays -1.
                Keys.onDownPressed: combo.filterIndex = combo.shown.length ? Math.min(combo.filterIndex + 1, combo.shown.length - 1) : -1
                Keys.onUpPressed: combo.filterIndex = combo.shown.length ? Math.max(combo.filterIndex - 1, 0) : -1
                Keys.onReturnPressed: { if (combo.filterIndex >= 0 && combo.filterIndex < combo.shown.length) { combo.activated(combo.filterIndex); combo.popup.close(); } }
                Keys.onEnterPressed: { if (combo.filterIndex >= 0 && combo.filterIndex < combo.shown.length) { combo.activated(combo.filterIndex); combo.popup.close(); } }
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
