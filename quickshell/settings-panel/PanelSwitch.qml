import QtQuick
import QtQuick.Controls

// The panel's toggle. Every on/off control draws through this, so a switch looks
// the same on every page instead of falling back to the platform style. Optional
// text sits to the right of the track.
Switch {
    id: toggle
    required property var theme
    implicitHeight: 40
    implicitWidth: text ? leftPadding + contentItem.implicitWidth + rightPadding : 54
    leftPadding: 3
    rightPadding: 3
    spacing: 8
    indicator: Rectangle {
        x: toggle.leftPadding; y: (toggle.height - height) / 2
        width: 48; height: 26; radius: 13
        color: toggle.checked ? toggle.theme.accent : toggle.theme.background
        border.width: toggle.activeFocus ? 2 : 1
        border.color: toggle.activeFocus ? toggle.theme.accent : toggle.theme.foreground
        Rectangle { width: 18; height: 18; radius: 9; y: 4; x: toggle.checked ? 26 : 4; color: toggle.checked ? toggle.theme.accentText : toggle.theme.foreground }
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
