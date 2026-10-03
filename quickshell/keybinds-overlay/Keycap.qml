import QtQuick

// One key of a combo. Modifiers are dim so the final key stands out.
Rectangle {
    id: cap
    required property string keyName
    property bool modifier: false
    property bool lit: false
    // The overlay view, for colours, font and scale. It is briefly null while a
    // re-flowing column destroys its delegates, so every use below tolerates that.
    property var theme: null
    readonly property real uiScale: theme ? theme.uiScale : 1

    implicitWidth: label.implicitWidth + Math.round(12 * uiScale)
    implicitHeight: Math.round(20 * uiScale)
    radius: Math.round(5 * uiScale)
    color: theme ? theme.raised : "transparent"
    border.width: lit ? 1 : 0
    border.color: theme ? theme.accent : "transparent"
    Accessible.ignored: true

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 1
        radius: 1
        color: cap.theme ? Qt.rgba(cap.theme.foreground.r, cap.theme.foreground.g, cap.theme.foreground.b, 0.14) : "transparent"
    }
    Text {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: cap.keyName
        font.family: cap.theme ? cap.theme.monoFont : "monospace"
        font.pixelSize: Math.round(11 * cap.uiScale)
        color: !cap.theme ? "transparent" : cap.modifier ? cap.theme.dim : cap.theme.foreground
    }
}
