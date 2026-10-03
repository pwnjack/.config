pragma ComponentBehavior: Bound
import QtQuick

// ③ Done (closes itself after 3 s), ③′ restart, ③″ needs attention / failed.
Item {
    id: view
    required property var card
    required property var controller
    readonly property var result: card.result
    readonly property string kind: result ? result.kind : ""
    readonly property bool active: card.mode === "result"
    readonly property bool hasPrimary: kind === "restart" || (result !== null && result.terminal !== "")
    // Done ends in the mockup's timer line, which sits 8 px under the header
    // and runs along the card's bottom edge instead of above the padding.
    implicitHeight: kind === "done" ? header.height + card.px(10) - card.px(16) : content.implicitHeight

    function focusPrimary() {
        if (kind === "done") view.card.forceActiveFocus();
        else (hasPrimary ? primary : secondary).forceActiveFocus();
    }
    function sync() {
        if (active && kind === "done") drain.restart();
        else drain.stop();
    }
    onActiveChanged: sync()
    onKindChanged: sync()

    Column {
        id: content
        width: parent.width
        spacing: view.card.px(14)

        Header {
            id: header
            width: parent.width
            card: view.card
            check: view.kind === "done"
            glyph: view.kind === "restart" ? 0xf0709 : 0xf0026
            tint: view.result && view.result.tone === "warn" ? view.card.warn : view.card.accent
            badgeAlpha: view.kind === "done" ? 0.26 : view.result && view.result.tone === "warn" ? 0.18 : 0.22
            title: view.result ? view.result.title : ""
            subtitle: view.result ? view.result.subtitle : ""
        }

        Rectangle {
            visible: view.result !== null && view.result.reason !== ""
            width: parent.width
            height: reason.implicitHeight + view.card.px(18)
            radius: view.card.px(10)
            color: Qt.rgba(view.card.warn.r, view.card.warn.g, view.card.warn.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(view.card.warn.r, view.card.warn.g, view.card.warn.b, 0.22)
            Text {
                id: reason
                objectName: "reason"
                x: view.card.px(11)
                y: view.card.px(9)
                width: parent.width - view.card.px(22)
                text: view.result ? view.result.reason : ""
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: view.card.foreground
                font.family: view.card.monoFont
                font.pixelSize: view.card.px(12)
                lineHeight: 1.2
            }
        }

        Row {
            visible: view.kind !== "done"
            anchors.right: parent.right
            spacing: view.card.px(8)
            CardButton {
                id: secondary
                card: view.card
                text: view.kind === "restart" ? "Later" : "Close"
                onClicked: view.controller.close()
            }
            CardButton {
                id: primary
                card: view.card
                visible: view.hasPrimary
                kind: view.kind === "restart" ? "primary" : "warn"
                text: view.kind === "restart" ? "Restart" : "Open in terminal"
                hint: "↵"
                onClicked: view.kind === "restart" ? view.controller.reboot() : view.controller.terminal(view.result.terminal)
            }
        }
    }

    // Full card width in the mockup, cut by the rounded corners; inset to
    // where an 18 px corner leaves the bottom 2 px row.
    Rectangle {
        id: timerLine
        readonly property real full: view.width + 2 * view.card.px(8)
        visible: view.kind === "done"
        x: -view.card.px(8)
        y: header.height + view.card.px(8)
        height: 2
        width: full
        color: Qt.rgba(view.card.accent.r, view.card.accent.g, view.card.accent.b, 0.6)
        NumberAnimation {
            id: drain
            target: timerLine
            property: "width"
            from: timerLine.full
            to: 0
            duration: 3000
            onFinished: if (view.active && view.kind === "done") view.controller.close()
        }
    }
}
