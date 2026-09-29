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
    property var network: null
    readonly property string initialPage: Quickshell.env("SETTINGS_PAGE") || ""
    property string mainMonitor: ""
    property var pendingDisplay: null
    property var stagedDisplays: ({})
    property bool displaysSkipped: false
    // A network snapshot that arrived while a password was being typed was held
    // back so the list stayed still; replay it once the field closes.
    property bool networkSkipped: false
    // Whether the full read in flight asked for the network view.
    property bool readerNetwork: false
    onInteractingChanged: {
        if (interacting !== "network.psk" && networkSkipped) {
            networkSkipped = false;
            liveDirty = Object.assign({}, liveDirty, {network: true});
            liveTimer.restart();
        }
        if (interacting.startsWith("display:") || !displaysSkipped) return;
        displaysSkipped = false;
        markLive("displays");
    }
    property string interacting: ""
    property var liveDirty: ({})
    property string liveReply: ""
    property int liveReads: 0
    // Only what is on screen is watched: no page, no subscription. A row marked
    // inView (the network.wifi toggle, drawn by NetworkView itself) contributes
    // no live tag on its own — otherwise a search that merely matches its title
    // would start the network poller even while looking at an unrelated page.
    readonly property var liveTags: {
        const tags = new Set(visibleRows.filter(row => !row.inView).map(row => row.live).filter(Boolean));
        if (category === "monitors" && !query.trim()) tags.add("displays");
        if (category === "network" && !query.trim()) tags.add("network");
        return [...tags];
    }
    property var shownTags: []
    onLiveTagsChanged: {
        const previous = shownTags;
        const added = liveTags.filter(tag => !previous.includes(tag));
        const removed = previous.filter(tag => !liveTags.includes(tag));
        shownTags = liveTags;
        // Before the first full read (loaded false) that read already asks for the
        // network view. A full read already in flight may not (it was started on
        // another page), so the live read is deferred behind it, never dropped.
        // A full read in flight that already asks for the network view makes a live
        // read redundant; one started on another page does not, so the live read is
        // deferred behind it. Before any read has started, refresh() is about to run
        // with the network flag set.
        if (added.includes("network") && opened && !busy && (reader.running || loaded) && !(reader.running && readerNetwork)) {
            liveDirty = Object.assign({}, liveDirty, {network: true});
            if (reader.running) liveTimer.restart();
            else readLive();
        }
        if (removed.includes("network")) { scanner.running = false; scanSettle.stop(); }
    }
    // Covers the third way the network tag "goes away": closing the panel while
    // still on the network page, which changes no category/query and so never
    // fires onLiveTagsChanged above.
    onOpenedChanged: { if (!opened) { scanner.running = false; scanSettle.stop(); } }
    property var queue: []
    property string readReply: ""
    property string writeReply: ""
    property string writeRequest: ""
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
            if (!words.length) return row.category === category && !row.inView;
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
        readerNetwork = category === "network";
        reader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: true, network: category === "network"})];
        reader.running = true;
        // A full read supersedes any live read still waiting on its debounce.
        liveDirty = ({});
        liveTimer.stop();
    }
    function markLive(tag) {
        // A write refreshes everything afterwards, so its own echoes are not news.
        if (busy || reader.running || !liveTags.includes(tag)) return;
        liveDirty = Object.assign({}, liveDirty, {[tag]: true});
        liveTimer.restart();
    }
    function readLive() {
        const tags = Object.keys(liveDirty).filter(tag => liveTags.includes(tag));
        if (!tags.length || busy || closing) { liveDirty = ({}); return; }
        if (reader.running || liveReader.running) { liveTimer.restart(); return; }
        liveDirty = ({});
        liveReads += 1;
        const ids = catalog.rows.filter(row => tags.includes(row.live)).map(row => row.id);
        liveReply = "";
        liveReader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: tags.includes("displays"), network: tags.includes("network")})];
        liveReader.running = true;
    }
    function select(id) { query = ""; category = id; }
    function change(id, value) { submit({op: "set", id: id, value: value}); }
    function reset(id) { submit({op: "reset", id: id}); }
    function action(id) { submit({op: "action", id: id}); }
    function keepDisplay() { submit({op: "displayKeep"}); }
    function revertDisplay() {
        // Cleared first so the countdown cannot submit twice; the next read restores it if still pending.
        pendingDisplay = null;
        submit({op: "displayRevert"});
    }
    function submit(request) {
        if (closing) return;
        problem = "";
        queue = queue.concat([request]);
        busy = true;
        drain();
    }
    function drain() {
        if (writer.running || reader.running || liveReader.running) return;
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
        writeRequest = JSON.stringify(request);
        writer.command = ["bash", configDir + "/scripts/settings/panel-request.sh", "-"];
        writer.running = true;
    }
    function close() {
        // A layout nobody confirmed is never left behind.
        if (pendingDisplay && !closing) revertDisplay();
        closing = true;
        opened = false;
        if (!writer.running && !queue.length) Qt.quit();
    }
    FileView {
        preload: true
        path: root.configDir + "/quickshell/settings-panel/catalog.json"
        onLoaded: {
            try {
                root.catalog = JSON.parse(text());
                if (root.catalog.categories.some(c => c.id === root.initialPage)) root.category = root.initialPage;
                root.refresh();
            }
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
        // Not `show`: qs parses that word as its own `ipc show` subcommand even inside `ipc call`.
        function page(category: string): void { root.select(category); }
        function open(category: string): void {
            root.closing = false; root.opened = true;
            if (root.catalog.categories.some(c => c.id === category)) root.select(category);
        }
        function status(): string {
            return JSON.stringify({opened: root.opened, loading: root.loading, busy: root.busy,
                category: root.category, rows: root.visibleRows.length, error: root.problem,
                frameMs: root.frameMs, readyMs: root.readyMs,
                liveTags: root.liveTags, liveReads: root.liveReads,
                network: root.network ? (root.network.running ? "up" : "down") : "none",
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
                // A password mid-edit keeps its own network snapshot: replacing it here
                // would recreate the Wi-Fi list's delegates under the user's hands.
                if (result.network) { if (root.interacting !== "network.psk") root.network = result.network; else root.networkSkipped = true; }
                // An open display dropdown keeps its card (the read is replayed when it
                // closes); a queued Keep/Revert is about to change pendingDisplay.
                if (result.monitors && root.interacting.startsWith("display:")) root.displaysSkipped = true;
                else if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; if (!root.busy) root.pendingDisplay = result.displayPending; }
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
        stdinEnabled: true
        // The request travels on stdin, never argv: it may carry a Wi-Fi password.
        onStarted: { writer.write(root.writeRequest + "\n"); root.writeRequest = ""; }
        stdout: StdioCollector { onStreamFinished: root.writeReply = text }
        stderr: StdioCollector { onStreamFinished: root.writeError = text }
        onExited: code => {
            root.writeRequest = "";
            try {
                const result = JSON.parse(root.writeReply);
                if (code !== 0 || !result.ok) throw new Error(result.error || "Settings helper failed");
                if (result.pending !== undefined) root.pendingDisplay = result.pending;
                // Closed while this Apply was in flight: close() saw no pending change
                // yet, and submit() ignores requests once closing, so queue it directly.
                if (root.closing && result.pending) { root.pendingDisplay = null; root.queue = root.queue.concat([{op: "displayRevert"}]); }
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
    Timer { id: liveTimer; interval: 300; onTriggered: root.readLive() }
    Process {
        id: audioEvents
        running: root.opened && root.liveTags.includes("audio")
        command: ["pactl", "subscribe"]
        // `sink-input #3` must not count as `sink`; clients and streams are noise.
        stdout: SplitParser { onRead: line => { if (/ on (sink|source|card|server)( #|$)/.test(line)) root.markLive("audio"); } }
    }
    Process {
        id: networkEvents
        running: root.opened && root.liveTags.includes("network")
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: _line => root.markLive("network") }
    }
    // Scans only while the page is on screen; NM's own background scanning is untouched.
    Timer {
        interval: 20000; repeat: true; triggeredOnStart: true
        running: root.opened && root.liveTags.includes("network")
        onTriggered: { if (!root.busy && !scanner.running) scanner.running = true; }
    }
    Process {
        id: scanner
        command: ["bash", root.configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "networkScan"})]
        // Only restarts the settle timer if the panel is open and the page (or a
        // matching search) is still up; otherwise a scan that outlives either would relight it.
        onExited: { if (root.opened && root.liveTags.includes("network")) scanSettle.restart(); }
    }
    // A scan completes a few seconds later, and `nmcli monitor` may not report it (Task 1).
    Timer { id: scanSettle; interval: 5000; onTriggered: root.markLive("network") }
    Connections {
        target: Hyprland
        enabled: root.opened && root.liveTags.includes("displays")
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name)) root.markLive("displays");
        }
    }
    Process {
        id: liveReader
        stdout: StdioCollector { onStreamFinished: root.liveReply = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.liveReply);
                if (!result.ok) throw new Error(result.error);
                const values = Object.assign({}, result.values);
                // Never move a control under the user's hand.
                delete values[root.interacting];
                root.values = Object.assign({}, root.values, values);
                if (result.network) { if (root.interacting !== "network.psk") root.network = result.network; else root.networkSkipped = true; }
                // An open display dropdown keeps its card (the read is replayed when it
                // closes); a queued Keep/Revert is about to change pendingDisplay.
                if (result.monitors && root.interacting.startsWith("display:")) root.displaysSkipped = true;
                else if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; if (!root.busy) root.pendingDisplay = result.displayPending; }
            } catch (error) { console.warn("Live refresh failed: " + error); }
            if (Object.keys(root.liveDirty).length) liveTimer.restart();
            if (root.busy || root.closing) root.drain();
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
