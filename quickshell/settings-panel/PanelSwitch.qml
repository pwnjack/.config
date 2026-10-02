import QtQuick
import QtQuick.Controls

// The panel's toggle: a 38×22 track whose knob slides. Optional text sits to the
// right of the track. Every on/off control draws through this, so a switch looks the
// same on every page instead of falling back to the platform style.
Switch {
    id: toggle
    required property var theme
    implicitHeight: 28
    implicitWidth: text ? leftPadding + contentItem.implicitWidth + rightPadding : 38
    leftPadding: 0
    rightPadding: 0
    spacing: 8
    opacity: enabled ? 1 : 0.42
    indicator: Rectangle {
        x: toggle.leftPadding; y: (toggle.height - height) / 2
        width: 38; height: 22; radius: 11
        color: toggle.checked ? toggle.theme.accent
            : Qt.rgba(toggle.theme.foreground.r, toggle.theme.foreground.g, toggle.theme.foreground.b, 0.18)
        border.width: toggle.activeFocus ? 2 : 0
        border.color: toggle.theme.foreground
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 18; height: 18; radius: 9; y: 2
            x: toggle.checked ? 18 : 2
            color: toggle.checked ? toggle.theme.accentText : toggle.theme.foreground
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Text {
        text: toggle.text
        visible: !!toggle.text
        leftPadding: toggle.indicator.width + toggle.spacing
        color: toggle.theme.foreground
        font.pixelSize: 13
        verticalAlignment: Text.AlignVCenter
    }
}
