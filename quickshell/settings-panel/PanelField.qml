import QtQuick
import QtQuick.Controls

// The panel's text entry: a dark 28 px box with an accent focus ring. `pending` keeps
// the ring while the text differs from what is saved, so an unapplied edit stays
// visible after focus moves on. Every field uses it, so none falls back to the light
// platform style (a bare TextField does).
TextField {
    id: field
    required property var theme
    property bool pending: false
    implicitHeight: 28
    leftPadding: 9
    rightPadding: 9
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: 13
    selectByMouse: true
    color: field.theme.foreground
    placeholderTextColor: field.theme.dim
    selectionColor: field.theme.accent
    selectedTextColor: field.theme.accentText
    background: Rectangle {
        color: field.theme.background
        radius: 7
        border.width: field.activeFocus || field.pending ? 2 : 1
        border.color: field.activeFocus || field.pending ? field.theme.accent
            : Qt.rgba(field.theme.foreground.r, field.theme.foreground.g, field.theme.foreground.b, 0.16)
    }
}
