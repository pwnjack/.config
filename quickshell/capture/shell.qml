pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "model.mjs" as Model

// The capture strip (spec: docs/superpowers/specs/2026-10-09-capture-bar-design.md).
// Started by scripts/hyprland/capture-bar.sh; the process exits on close. It
// writes only options/capture-* (each change at once, so what is shown is
// what is saved, even after Esc). screenshot.sh and record.sh do the
// capturing: the action hides the window, waits for Hyprland to report the
// layer closed, then starts the command detached and exits, so the strip is
// never in a capture.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property var scripts: ({
        screenshot: configDir + "/scripts/hyprland/screenshot.sh",
        record: configDir + "/scripts/capture/record.sh"
    })
    readonly property color background: Quickshell.env("CAPTURE_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("CAPTURE_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("CAPTURE_ACCENT") || "#6097a1"
    // Text on the accent. Not "onAccent": QML reads on<Name> as a change handler.
    readonly property color accentInk: Quickshell.env("CAPTURE_ON_ACCENT") || "#05090c"
    readonly property string monoFont: Quickshell.env("CAPTURE_FONT") || "monospace"
    // A popover keeps the bar's own pixel sizes: scaled to the output, the
    // update card was oversized at 1440p.
    readonly property real uiScale: 1

    property var state: Model.initialState({}, "screenshot")
    property var status: Model.parseStatus("")
    property bool opened: false
    property bool closing: false
    property var pending: []            // argv to start once the layer is gone

    function readOptions() {
        const texts = {};
        for (let i = 0; i < optionFiles.count; i++) {
            const file = optionFiles.objectAt(i);
            file.reload();
            texts[file.name] = file.text();
        }
        return texts;
    }
    function write(change) {
        if (!change) return;
        for (let i = 0; i < optionFiles.count; i++) {
            const file = optionFiles.objectAt(i);
            if (file.name === change[0]) file.setText(change[1] + "\n");
        }
    }
    function apply(result) { state = result.state; write(result.write); }
    function setMode(mode) { state = Model.withMode(state, mode); }
    function setTarget(target) { apply(Model.setOption(state, Model.targetKey(state.mode), target)); }
    function toggleOption(key) { apply(Model.setOption(state, key, !state[key])); }
    function cycleDelay() { apply(Model.setOption(state, "delay", Model.nextDelay(state.delay))); }
    function key(name) {
        const result = Model.reduceKey(state, name);
        apply(result);
        if (result.effect === "close") close();
        else if (result.effect === "run") run();
    }

    function open(mode) {
        if (pending.length) return;     // a capture is about to start
        if (!opened && !closing) {
            const focused = Hyprland.focusedMonitor;
            window.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        }
        state = Model.initialState(readOptions(), mode);
        closing = false;
        opened = true;
        statusProbe.running = true;
        strip.appear();
    }
    function close() {
        if (!opened) return;
        opened = false;
        closing = true;
        strip.disappear();
    }
    function run() {
        if (!opened || pending.length) return;     // a second run does nothing
        pending = Model.command(state, status, scripts);
        opened = false;
        closing = true;
        layerFallback.start();
    }
    function launch() {
        if (!pending.length || launcher.running) return;
        layerFallback.stop();
        launcher.command = ["setsid", "-f"].concat(pending);
        launcher.running = true;
    }
    Component.onCompleted: open(Quickshell.env("CAPTURE_MODE") || "screenshot")

    Instantiator {
        id: optionFiles
        model: Object.values(Model.FILES)
        delegate: FileView {
            required property string modelData
            readonly property string name: modelData
            path: root.configDir + "/options/" + modelData
            blockLoading: true
            printErrors: false
            atomicWrites: true
        }
    }

    // While open, the Record tab's Stop timer follows record.sh, once a second.
    Process {
        id: statusProbe
        command: [root.scripts.record, "status", "--json"]
        stdout: StdioCollector { id: statusOut; onStreamFinished: root.status = Model.parseStatus(statusOut.text) }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.opened
        onTriggered: statusProbe.running = true
    }

    // The capture starts only once Hyprland has unmapped the strip's layer;
    // the timer covers a missed event.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.pending.length && event.name === "closelayer" && event.data === "capture-bar") root.launch();
        }
    }
    Timer { id: layerFallback; interval: 400; onTriggered: root.launch() }
    Process { id: launcher; onExited: Qt.quit() }

    IpcHandler {
        target: "capture"
        function ping(): string { return "ready"; }
        // The keybinds: the same mode again closes, the other mode switches tab.
        function toggle(mode: string): void {
            if (root.opened && root.state.mode === mode) root.close();
            else if (root.opened) root.setMode(mode);
            else root.open(mode);
        }
        function open(mode: string): void {
            if (root.opened) root.setMode(mode);
            else root.open(mode);
        }
        function close(): void { root.close(); }
        // Press the action button (Return); used by the live checks, which have no pointer.
        function run(): void { root.run(); }
        function status(): string {
            return JSON.stringify({ opened: root.opened, closing: root.closing, state: root.state,
                phase: root.status.phase, pending: root.pending });
        }
    }

    PanelWindow {
        id: window
        visible: root.opened || (root.closing && !root.pending.length)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        // Normal: a bottom Waybar's exclusive zone is respected, so the strip
        // sits 28 px above the bar rather than over it.
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "capture-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Strip {
            id: strip
            controller: root
            focus: true
            enabled: root.opened
            x: Math.round((window.width - width) / 2)
            y: window.height - height - Math.round(28 * root.uiScale)
            onGone: if (root.closing && !root.pending.length) Qt.quit()
        }
    }
}
