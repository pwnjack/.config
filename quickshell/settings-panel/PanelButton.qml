import QtQuick
import QtQuick.Controls

// The panel's push button. `primary` fills it with the accent, for the one action a
// row or group is waiting on (Apply); everything else is the quiet raised style.
Button {
    id: button
    required property var theme
    property bool primary: false
    implicitHeight: 28
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    opacity: enabled ? 1 : 0.42
    contentItem: Text {
        text: button.text
        color: button.primary ? button.theme.accentText : button.theme.foreground
        font.pixelSize: 12
        font.weight: button.primary ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 7
        color: button.primary
            ? (button.down ? Qt.darker(button.theme.accent, 1.15) : button.hovered ? Qt.lighter(button.theme.accent, 1.08) : button.theme.accent)
            : (button.down ? button.theme.pressed : button.hovered ? button.theme.hover : button.theme.raised)
        border.width: button.activeFocus ? 2 : 1
        border.color: button.activeFocus ? (button.primary ? button.theme.foreground : button.theme.accent) : button.theme.line
        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
