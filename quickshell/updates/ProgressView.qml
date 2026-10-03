pragma ComponentBehavior: Bound
import QtQuick
import "model.mjs" as Model

// ② The run. The bar follows card.shown (eased in Card.qml); the status line
// crossfades only when the phase key changes and updates in place otherwise.
Column {
    id: view
    required property var card
    required property var controller
    readonly property var run: controller.run
    spacing: card.px(14)

    function focusPrimary() {
        view.card.forceActiveFocus();
    }

    Header {
        width: parent.width
        card: view.card
        title: "Updating…"
        subtitle: Model.runningSubtitle(view.run)
    }

    Rectangle {
        id: track
        width: parent.width
        height: view.card.px(6)
        radius: height / 2
        color: Qt.rgba(view.card.foreground.r, view.card.foreground.g, view.card.foreground.b, 0.1)
        clip: true
        Rectangle {
            id: fill
            width: track.width * view.card.shown
            height: parent.height
            radius: parent.radius
            color: view.card.accent
            clip: true
            // The mockup's sheen: a 120 px highlight that sweeps across the
            // fill every 1.6 s and stops once the bar is full.
            Rectangle {
                id: sheen
                property real phase: 0
                visible: view.card.shown < 1 && view.visible
                x: -view.card.px(120) + phase * (fill.width + view.card.px(120))
                width: view.card.px(120)
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
                    GradientStop { position: 1; color: "transparent" }
                }
                NumberAnimation on phase {
                    from: 0
                    to: 1
                    duration: 1600
                    loops: Animation.Infinite
                    running: sheen.visible
                }
            }
        }
    }

    Item {
        width: parent.width
        height: view.card.px(18)
        Item {
            id: status
            anchors.left: parent.left
            anchors.right: pct.left
            anchors.rightMargin: view.card.px(12)
            height: parent.height
            clip: true
            readonly property string key: Model.runningKey(view.run) || ""
            readonly property string line: Model.runningLine(view.run) || ""
            property string shownKey: ""
            property Item current: a
            // A new phase slides the old line up and out and the new one up
            // and in (the mockup's .out / .in); same phase, text in place.
            function sync() {
                if (shownKey === "" || key === shownKey) {
                    current.text = line;
                    shownKey = key;
                    return;
                }
                swap.complete();
                const next = current === a ? b : a;
                next.text = line;
                swap.leave = current;
                swap.enter = next;
                current = next;
                shownKey = key;
                swap.restart();
            }
            onKeyChanged: sync()
            onLineChanged: sync()
            Component.onCompleted: sync()
            ParallelAnimation {
                id: swap
                property Item enter: b
                property Item leave: a
                NumberAnimation { target: swap.enter; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutQuad }
                NumberAnimation { target: swap.enter; property: "y"; from: view.card.px(5); to: 0; duration: 220; easing.type: Easing.OutQuad }
                NumberAnimation { target: swap.leave; property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutQuad }
                NumberAnimation { target: swap.leave; property: "y"; to: -view.card.px(5); duration: 220; easing.type: Easing.OutQuad }
            }
            Text {
                id: a
                width: parent.width
                elide: Text.ElideRight
                color: view.card.dim
                font.family: view.card.monoFont
                font.pixelSize: view.card.px(12.5)
            }
            Text {
                id: b
                width: parent.width
                opacity: 0
                elide: Text.ElideRight
                color: view.card.dim
                font.family: view.card.monoFont
                font.pixelSize: view.card.px(12.5)
            }
        }
        Text {
            id: pct
            anchors.right: parent.right
            text: Math.floor(view.card.shown * 100) + "%"
            color: view.card.foreground
            font.family: view.card.monoFont
            font.pixelSize: view.card.px(12.5)
            font.features: ({ "tnum": 1 })
        }
    }
}
