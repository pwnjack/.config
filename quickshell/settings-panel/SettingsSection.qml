pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One subsection of a page: an uppercase caption over a rounded group of PanelRows,
// then an optional footnote. Catalog sections may carry buttons (Restart bar, Update
// now), drawn as a trailing row inside the group.
ColumnLayout {
    id: section
    required property var theme
    property string title: ""
    property string footer: ""
    property var actions: []
    property bool actionsEnabled: true
    signal triggered(string action)
    default property alias rows: body.data
    Layout.fillWidth: true
    spacing: 7
    Label {
        visible: !!section.title
        text: section.title.toLocaleUpperCase()
        color: section.theme.dim
        font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
        Layout.leftMargin: 14
        Accessible.role: Accessible.Heading
        Accessible.name: section.title
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: stack.implicitHeight
        radius: 12
        color: section.theme.plate
        border.color: section.theme.line
        ColumnLayout {
            id: stack
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            spacing: 0
            ColumnLayout { id: body; Layout.fillWidth: true; spacing: 0 }
            PanelRow {
                visible: section.actions.length > 0
                theme: section.theme
                divider: body.implicitHeight > 0
                Item { Layout.fillWidth: true }
                Repeater {
                    model: section.actions
                    delegate: PanelButton {
                        required property var modelData
                        objectName: "sectionAction-" + modelData.action
                        theme: section.theme
                        text: modelData.label
                        enabled: section.actionsEnabled
                        onClicked: section.triggered(modelData.action)
                    }
                }
            }
        }
    }
    Label {
        visible: !!section.footer
        text: section.footer
        color: section.theme.dim
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.leftMargin: 14; Layout.rightMargin: 14
    }
}
