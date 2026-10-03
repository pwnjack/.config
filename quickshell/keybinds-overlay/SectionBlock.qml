pragma ComponentBehavior: Bound
import QtQuick
import "sheet.mjs" as Sheet

// One section of the sheet: an accent heading over label/keycap rows.
Column {
    id: block
    required property var section
    required property var theme
    required property string query
    spacing: 0

    Item {
        width: block.width
        height: block.theme.headingHeight - spacer.height
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: block.section.name
            font.capitalization: Font.AllUppercase
            font.pixelSize: block.theme.px(12)
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6 * block.theme.uiScale
            color: block.theme.accent
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: block.section.rows.length
            font.pixelSize: block.theme.px(11)
            color: block.theme.dim
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: block.theme.line
        }
    }
    Item {
        id: spacer
        width: 1
        height: block.theme.px(4)
    }
    Repeater {
        model: block.section.rows
        delegate: Item {
            id: row
            required property var modelData
            width: block.width
            height: block.theme.rowHeight
            Accessible.role: Accessible.StaticText
            Accessible.name: row.modelData.label + ": " + Sheet.keyText(row.modelData)

            Text {
                objectName: "label"
                anchors.left: parent.left
                anchors.right: caps.left
                anchors.rightMargin: block.theme.px(12)
                anchors.verticalCenter: parent.verticalCenter
                text: Sheet.highlight(row.modelData.label, block.query, block.theme.accent)
                textFormat: Text.StyledText
                elide: Text.ElideRight
                font.pixelSize: block.theme.px(13)
                color: block.theme.foreground
            }
            Row {
                id: caps
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: block.theme.px(3)
                Repeater {
                    model: row.modelData.keys
                    delegate: Keycap {
                        required property string modelData
                        required property int index
                        keyName: modelData
                        modifier: index < row.modelData.keys.length - 1
                        // Delegates outlive their block briefly while columns re-flow.
                        lit: block ? Sheet.capMatches(modelData, block.query) : false
                        theme: block ? block.theme : null
                    }
                }
            }
        }
    }
}
