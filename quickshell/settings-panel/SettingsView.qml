pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: view
    required property var controller
    signal framePresented()
    property bool reportedFrame: false
    Connections {
        target: view.Window.window
        function onFrameSwapped() {
            if (!view.reportedFrame) { view.reportedFrame = true; view.framePresented(); }
        }
    }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color accentText: controller.accentText
    readonly property color plate: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055))
    focus: true
    Keys.onEscapePressed: controller.close()
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Escape"; onActivated: view.controller.close() }
    Rectangle { anchors.fill: parent; color: Qt.rgba(view.background.r, view.background.g, view.background.b, 0.24) }
    MouseArea { anchors.fill: parent; onClicked: view.controller.close() }
    Rectangle {
        id: panel
        objectName: "settingsPanel"
        anchors.centerIn: parent
        width: Math.min(1000, parent.width - 48)
        height: Math.min(740, parent.height - 48)
        radius: 24
        color: view.background
        border.color: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.2)
        MouseArea { anchors.fill: parent } // Keep clicks inside the panel from closing it.
        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 24
            ColumnLayout {
                Layout.preferredWidth: 205
                Layout.fillHeight: true
                spacing: 8
                Label { text: "Settings"; color: view.foreground; font.pixelSize: 27; font.bold: true; Layout.bottomMargin: 12 }
                TextField {
                    id: search
                    objectName: "settingsSearch"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: "Search · Ctrl+F"
                    text: view.controller.query
                    onTextEdited: view.controller.query = text
                    color: view.foreground
                    placeholderTextColor: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.7)
                    selectByMouse: true
                    Accessible.name: "Search settings"
                    background: Rectangle { color: view.plate; radius: 10; border.color: search.activeFocus ? view.accent : "transparent"; border.width: 2 }
                }
                Repeater {
                    model: view.controller.catalog.categories
                    delegate: Button {
                        id: nav
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        text: modelData.title
                        readonly property bool selected: view.controller.category === modelData.id && !view.controller.query.trim()
                        onClicked: view.controller.select(modelData.id)
                        contentItem: Text { text: nav.text; color: nav.selected ? view.accentText : view.foreground; font.pixelSize: 14; font.bold: nav.selected; verticalAlignment: Text.AlignVCenter; leftPadding: 12 }
                        background: Rectangle { radius: 10; color: nav.selected ? view.accent : nav.hovered ? view.plate : "transparent"; border.color: nav.activeFocus ? view.foreground : "transparent"; border.width: 2 }
                    }
                }
                Item { Layout.fillHeight: true }
                Label { text: view.controller.busy ? "Saving changes…" : view.controller.loading ? "Reading settings…" : "Text fields: Enter or Save"; color: view.foreground; opacity: 0.75; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                PanelButton { objectName: "closeSettings"; text: "Close"; theme: view; Layout.fillWidth: true; onClicked: view.controller.close() }
            }
            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: view.foreground; opacity: 0.13 }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                Label {
                    text: view.controller.query.trim() ? "Search results" : (view.controller.catalog.categories.find(c => c.id === view.controller.category)?.title || "Settings")
                    color: view.foreground; font.pixelSize: 24; font.bold: true
                }
                Label {
                    text: view.controller.query.trim() ? view.controller.visibleRows.length + " matching settings" : (view.controller.catalog.categories.find(c => c.id === view.controller.category)?.description || "")
                    Layout.fillWidth: true; color: view.foreground; opacity: 0.75; wrapMode: Text.WordWrap; font.pixelSize: 13
                }
                Rectangle {
                    visible: !!view.controller.problem
                    Layout.fillWidth: true
                    implicitHeight: errorLabel.implicitHeight + 24
                    radius: 10; color: view.plate; border.color: view.foreground
                    Label { id: errorLabel; anchors.fill: parent; anchors.margins: 12; text: view.controller.problem; color: view.foreground; wrapMode: Text.Wrap; Accessible.role: Accessible.AlertMessage }
                }
                ScrollView {
                    id: scroll
                    objectName: "settingsScroll"
                    opacity: view.controller.loaded ? 1 : 0
                    enabled: view.controller.loaded
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: scroll.availableWidth
                        spacing: 8
                        Repeater {
                            model: view.controller.category === "monitors" && !view.controller.query.trim() ? view.controller.monitors : []
                            delegate: Rectangle {
                                id: display
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: monitorInfo.implicitHeight + 28
                                radius: 12; color: view.plate
                                RowLayout {
                                    id: monitorInfo
                                    anchors.fill: parent; anchors.margins: 14
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Label { text: display.modelData.name + " · " + (display.modelData.model || "Display"); color: view.foreground; font.bold: true }
                                        Label { text: display.modelData.width + " × " + display.modelData.height + " · " + Number(display.modelData.refreshRate).toFixed(1) + " Hz · scale " + display.modelData.scale; color: view.foreground; opacity: 0.75; font.pixelSize: 12 }
                                    }
                                    PanelButton {
                                        theme: view
                                        text: view.controller.mainMonitor === display.modelData.name ? "Main display" : "Set as main"
                                        enabled: !view.controller.busy && view.controller.mainMonitor !== display.modelData.name
                                        onClicked: view.controller.submit({op: "mainMonitor", value: display.modelData.name})
                                    }
                                }
                            }
                        }
                        Flow {
                            visible: view.controller.category === "monitors" && !view.controller.query.trim()
                            Layout.fillWidth: true; spacing: 8
                            PanelButton { theme: view; text: "Advanced display setup"; onClicked: view.controller.action("monitors") }
                            PanelButton { theme: view; text: "Automatic main display"; enabled: !!view.controller.mainMonitor && !view.controller.busy; onClicked: view.controller.submit({op: "mainMonitor", value: ""}) }
                        }
                        Label { visible: !view.controller.visibleRows.length && !view.controller.loading; text: "No settings match your search."; color: view.foreground; Layout.topMargin: 24 }
                        Repeater {
                            model: view.controller.visibleRows
                            delegate: SettingControl {
                                required property var modelData
                                Layout.fillWidth: true
                                row: modelData
                                theme: view
                                settingState: view.controller.values[modelData.id] || ({})
                                controller: view.controller
                            }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    PanelButton { theme: view; text: "Reload Hyprland"; enabled: !view.controller.busy; onClicked: view.controller.action("reload") }
                    PanelButton { theme: view; text: "Restart Waybar"; onClicked: view.controller.action("waybar") }
                    PanelButton { theme: view; text: "Update system"; onClicked: view.controller.action("update") }
                }
            }
        }
    }
}
