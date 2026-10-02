import QtQuick
import QtQuick.Effects

Item {
    id: avatar
    required property var theme
    property string source: ""
    readonly property url fileSource: source ? "file://" + source.split("/").map(encodeURIComponent).join("/") : ""
    property string name: ""
    property int size: 34
    readonly property bool imageReady: !!source && picture.status === Image.Ready
    implicitWidth: size
    implicitHeight: size
    Rectangle {
        anchors.fill: parent
        visible: !avatar.imageReady
        radius: avatar.size / 2
        rotation: 45
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: avatar.theme.accent }
            GradientStop { position: 1; color: Qt.darker(avatar.theme.accent, 1.5) }
        }
    }
    Text {
        objectName: "avatarInitial"
        anchors.centerIn: parent
        visible: !avatar.imageReady
        text: avatar.name.trim().charAt(0).toLocaleUpperCase()
        color: avatar.theme.accentText
        font.pixelSize: Math.round(avatar.size * 0.44)
        font.weight: Font.DemiBold
        Accessible.ignored: true
    }
    Image {
        id: picture
        anchors.fill: parent
        source: avatar.fileSource
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.ceil(avatar.size * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(avatar.size * Screen.devicePixelRatio)
        asynchronous: true
        visible: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: avatar.size / 2
        color: "white"
        layer.enabled: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        visible: avatar.imageReady
        source: picture
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
