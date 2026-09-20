pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("HOME") + "/.config"
    property bool opened: true
    property bool closing: false
    property bool busy: false
    property bool loading: true
    property bool loaded: false
    property string problem: ""
    property var catalog: ({ categories: [], rows: [] })
    property string category: "appearance"
    property string query: ""
    property var values: ({})
    property var monitors: []
    property string mainMonitor: ""
    property var queue: []
    property string readReply: ""
    property string writeReply: ""
    property string readError: ""
    property string writeError: ""
    readonly property double startedAt: Number(Quickshell.env("SETTINGS_STARTED_MS")) || Date.now()
    property int frameMs: -1
    property int readyMs: -1
    readonly property color background: Quickshell.env("SETTINGS_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("SETTINGS_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("SETTINGS_ACCENT") || "#6097a1"
    readonly property color accentText: Quickshell.env("SETTINGS_ON_ACCENT") || "#05090c"
    readonly property var visibleRows: {
        const words = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
        return catalog.rows.filter(row => {
            if (!words.length) return row.category === category;
            const title = catalog.categories.find(c => c.id === row.category)?.title || "";
            const hay = [row.title, row.description, title].concat(row.keywords || []).join(" ").toLocaleLowerCase();
            return words.every(word => hay.includes(word));
        });
    }
    function refresh() {
        if (!opened || busy || !catalog.rows.length) return;
        if (reader.running) return;
        // One small value snapshot per opening/edit. Tabs only rebuild widgets;
        // they never start a helper or briefly display unchecked/default values.
        const ids = catalog.rows.map(row => row.id);
        readReply = "";
        readError = "";
        loading = true;
        reader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: true})];
        reader.running = true;
    }
    function select(id) { query = ""; category = id; }
    function change(id, value) { submit({op: "set", id: id, value: value}); }
    function reset(id) { submit({op: "reset", id: id}); }
    function action(id) { submit({op: "action", id: id}); }
    function submit(request) {
        if (closing) return;
        problem = "";
        queue = queue.concat([request]);
        busy = true;
        drain();
    }
    function drain() {
        if (writer.running || reader.running) return;
        if (!queue.length) {
            busy = false;
            if (closing) Qt.quit();
            else refresh();
            return;
        }
        busy = true;
        const request = queue[0];
        queue = queue.slice(1);
        writeReply = "";
        writeError = "";
        writer.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify(request)];
        writer.running = true;
    }
    function close() {
        closing = true;
        opened = false;
        if (!writer.running && !queue.length) Qt.quit();
    }
    FileView {
        preload: true
        path: root.configDir + "/quickshell/settings-panel/catalog.json"
        onLoaded: {
            try { root.catalog = JSON.parse(text()); root.refresh(); }
            catch (error) { root.problem = "Could not load settings: " + error; root.loading = false; }
        }
        onLoadFailed: { root.problem = "Could not read the settings catalog."; root.loading = false; }
    }
    IpcHandler {
        target: "settings"
        function toggle(): void {
            if (root.opened) root.close();
            else { root.closing = false; root.opened = true; }
        }
        function close(): void { root.close(); }
        function status(): string {
            return JSON.stringify({opened: root.opened, loading: root.loading, busy: root.busy,
                category: root.category, rows: root.visibleRows.length, error: root.problem,
                frameMs: root.frameMs, readyMs: root.readyMs,
                rowErrors: root.visibleRows.filter(row => root.values[row.id]?.error).map(row => ({id:row.id,error:root.values[row.id].error}))});
        }
    }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: root.readReply = text }
        stderr: StdioCollector { onStreamFinished: root.readError = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.readReply);
                if (!result.ok) throw new Error(result.error);
                root.values = Object.assign({}, root.values, result.values);
                if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; }
                root.readyMs = Date.now() - root.startedAt;
                console.info("Settings ready in " + root.readyMs + " ms");
            } catch (error) { root.problem = root.readError.trim() || "Could not read settings: " + error; }
            root.loading = false;
            root.loaded = true;
            if (root.queue.length || root.closing) root.drain();
        }
    }
    Process {
        id: writer
        stdout: StdioCollector { onStreamFinished: root.writeReply = text }
        stderr: StdioCollector { onStreamFinished: root.writeError = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.writeReply);
                if (code !== 0 || !result.ok) throw new Error(result.error || "Settings helper failed");
            } catch (error) {
                root.problem = String(error);
                if (!root.writeReply.trim()) root.problem = root.writeError.trim() || "The settings helper stopped before confirming the change.";
                root.queue = [];
                root.closing = false;
                root.opened = true;
            }
            root.drain();
        }
    }
    PanelWindow {
        id: overlay
        visible: root.opened
        color: "transparent"
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "settings-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        SettingsView {
            anchors.fill: parent
            controller: root
            onFramePresented: {
                root.frameMs = Date.now() - root.startedAt;
                console.info("Settings first frame in " + root.frameMs + " ms");
            }
        }
        Component.onCompleted: console.info("Settings window created in " + (Date.now() - Number(Quickshell.env("SETTINGS_STARTED_MS"))) + " ms")
    }
}
