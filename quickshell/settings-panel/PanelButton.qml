import QtQuick
import QtQuick.Controls

Button {
    id: button
    required property var theme
    implicitHeight: 40
    leftPadding: 12
    rightPadding: 12
    opacity: enabled ? 1 : 0.5
    contentItem: Text { text: button.text; color: button.theme.foreground; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    background: Rectangle {
        radius: 10
        color: button.down ? button.theme.accent : button.hovered ? Qt.tint(button.theme.plate, "#15808080") : button.theme.plate
        border.width: button.activeFocus ? 2 : 1
        border.color: button.activeFocus ? button.theme.accent : Qt.rgba(button.theme.foreground.r, button.theme.foreground.g, button.theme.foreground.b, 0.15)
    }
}
