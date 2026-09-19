import QtQuick
import QtQuick.Controls

Button {
    id: control
    property color ink: "#ffffff"
    property color plate: "#20252b"
    property color accent: "#8dafb4"
    implicitHeight: 46
    implicitWidth: Math.max(46, contentItem.implicitWidth + 32)
    hoverEnabled: true
    Accessible.name: text
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        font.family: "sans-serif"
        font.pixelSize: 14
        font.weight: Font.Medium
        color: control.ink
        opacity: control.enabled ? 1 : 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 23
        color: control.plate
        opacity: control.down ? 0.65 : control.hovered ? 1 : 0.85
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.accent : Qt.alpha(control.ink, 0.2)
    }
}
