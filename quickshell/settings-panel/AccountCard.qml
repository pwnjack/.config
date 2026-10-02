pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: card
    required property var controller
    required property var theme
    readonly property var account: controller.about || ({})
    readonly property string displayName: account.realName || account.user || "Account"
    readonly property bool selected: controller.category === "about" && !controller.query.trim()
    objectName: "accountCard"
    implicitHeight: 56
    padding: 10
    hoverEnabled: true
    Accessible.name: displayName + ", About this machine"
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    onClicked: controller.select("about")
    background: Rectangle {
        radius: 10
        color: card.selected ? card.theme.accent : card.down ? card.theme.pressed : card.hovered ? card.theme.hover : card.theme.plate
        border.width: card.activeFocus ? 2 : 1
        border.color: card.activeFocus ? (card.selected ? card.theme.accentText : card.theme.accent) : card.theme.line
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    contentItem: RowLayout {
        spacing: 10
        Avatar { theme: card.theme; source: card.account.avatar || ""; name: card.displayName; size: 34 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Label {
                objectName: "accountName"
                text: card.displayName
                font.pixelSize: 13; font.weight: Font.DemiBold
                color: card.selected ? card.theme.accentText : card.theme.foreground
                elide: Text.ElideRight; Layout.fillWidth: true
            }
            Label {
                objectName: "accountHost"
                visible: !!card.account.host
                text: card.account.host ? "Signed in on " + card.account.host : ""
                font.pixelSize: 12
                color: card.selected ? card.theme.accentText : card.theme.dim
                elide: Text.ElideRight; Layout.fillWidth: true
            }
        }
    }
}
