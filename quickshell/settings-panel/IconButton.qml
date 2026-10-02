import QtQuick
import QtQuick.Controls

// A round, icon-only button: ⋯, ✕ and the per-row reset. The glyph is Nerd Font
// text, so it follows the palette; `label` is its accessible name, `tip` its tooltip.
Button {
    id: button
    required property var theme
    property string glyph: ""
    property string label: ""
    property string tip: label
    property bool active: false
    property int size: 28
    implicitWidth: size
    implicitHeight: size
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : 0.42
    Accessible.name: label
    // Space activates a Button natively; Return should too.
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    contentItem: Text {
        text: button.glyph
        font.family: button.theme.iconFont
        font.pixelSize: Math.round(button.size * 0.55)
        color: button.active ? button.theme.accentText : button.flat && !button.hovered ? button.theme.dim : button.theme.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: width / 2
        color: button.active ? button.theme.accent : button.down ? button.theme.pressed : button.hovered ? button.theme.hover
            : button.flat ? "transparent" : button.theme.raised
        border.width: button.activeFocus ? 2 : 0
        border.color: button.theme.accent
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    ToolTip {
        popupType: Popup.Item
        visible: button.hovered && !!button.tip
        delay: 600
        text: button.tip
        contentItem: Text { text: button.tip; color: button.theme.foreground; font.pixelSize: 12 }
        background: Rectangle { color: button.theme.raised; radius: 6; border.color: button.theme.line }
    }
}
