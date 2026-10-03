pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Super+H keybindings overlay. Started by scripts/hyprland/keybinds-overlay.sh;
// the process exits on close, so nothing stays resident between visits.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string failure: "Could not read keybinds.lua — see ~/.cache/keybinds-overlay/session.log"
    property bool opened: false
    property bool loading: false
    property string problem: ""
    property var sheet: []
    property string query: ""
    property double openedAt: 0
    readonly property color background: Quickshell.env("KEYBINDS_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("KEYBINDS_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("KEYBINDS_ACCENT") || "#6097a1"
    readonly property string monoFont: Quickshell.env("KEYBINDS_FONT") || "monospace"

    function close() {
        opened = false;
        Qt.quit();
    }
    function open() {
        if (opened)
            return;
        const focused = Hyprland.focusedMonitor;
        overlay.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        openedAt = Date.now();
        problem = "";
        query = "";
        opened = true;
        loading = true;
        reader.running = true;
    }
    Component.onCompleted: open()

    IpcHandler {
        target: "keybinds"
        function ping(): string {
            return "ready";
        }
        function toggle(): void {
            if (root.opened)
                root.close();
            else
                root.open();
        }
        function close(): void {
            root.close();
        }
        function status(): string {
            const view = loader.item;
            return JSON.stringify({
                opened: root.opened,
                loading: root.loading,
                query: root.query,
                shown: view ? view.shownCount : 0,
                total: view ? view.total : 0,
                columns: view ? view.columns : 0,
                error: root.problem
            });
        }
    }
    Process {
        id: reader
        command: [root.configDir + "/scripts/keybinds/keybinds-sheet.sh", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const sections = JSON.parse(text).sections;
                    if (!Array.isArray(sections))
                        throw new Error("no sections array");
                    root.sheet = sections;
                    console.info("Keybinds ready in " + (Date.now() - root.openedAt) + " ms; " + root.sheet.length + " sections");
                } catch (error) {
                    root.problem = root.failure;
                }
                root.loading = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text)
                console.warn(text)
        }
        onExited: code => {
            if (code !== 0) {
                root.loading = false;
                root.problem = root.failure;
            }
        }
    }
    PanelWindow {
        id: overlay
        visible: root.opened
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "keybinds-overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Loader {
            id: loader
            anchors.fill: parent
            active: root.opened
            focus: true
            sourceComponent: Overlay {
                controller: root
            }
        }
    }
}
