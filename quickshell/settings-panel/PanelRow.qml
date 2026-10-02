import QtQuick
import QtQuick.Layouts

// A row inside a SettingsSection: content laid out left to right, at least 46 px
// high, with a hairline above it unless it opens its group.
Item {
    id: row
    required property var theme
    property bool divider: false
    default property alias content: line.data
    Layout.fillWidth: true
    implicitWidth: line.implicitWidth + 28
    implicitHeight: Math.max(46, line.implicitHeight + 18)
    Rectangle {
        visible: row.divider
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.leftMargin: 14
        height: 1
        color: row.theme.line
    }
    RowLayout {
        id: line
        anchors.fill: parent
        anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 9; anchors.bottomMargin: 9
        spacing: 14
    }
}
