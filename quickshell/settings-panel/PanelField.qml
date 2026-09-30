import QtQuick
import QtQuick.Controls

// The panel's text entry: dark box, accent focus ring. Every field uses it, so
// none falls back to the light platform style (a bare TextField does).
TextField {
    id: field
    required property var theme
    implicitHeight: 40
    leftPadding: 10
    rightPadding: 10
    selectByMouse: true
    color: field.theme.foreground
    placeholderTextColor: Qt.rgba(field.theme.foreground.r, field.theme.foreground.g, field.theme.foreground.b, 0.6)
    selectionColor: field.theme.accent
    selectedTextColor: field.theme.accentText
    background: Rectangle {
        color: field.theme.background
        radius: 8
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? field.theme.accent : Qt.rgba(field.theme.foreground.r, field.theme.foreground.g, field.theme.foreground.b, 0.25)
    }
}
