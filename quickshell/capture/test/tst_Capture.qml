import QtQuick
import QtTest
import ".."
import "../model.mjs" as Model

Item {
    id: host
    width: 1600
    height: 900

    // The controller API shell.qml provides, backed by the real model.
    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property color accentInk: "#05090c"
        property string monoFont: "monospace"
        property real uiScale: 1
        property var state: Model.initialState({}, "screenshot")
        property var status: Model.parseStatus("")
        property int runs: 0
        property int closes: 0
        function apply(result) { state = result.state; }
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
        function run() { runs += 1; }
        function close() { closes += 1; }
    }
    Strip {
        id: strip
        controller: controller
        focus: true
    }
    TestCase {
        name: "Capture"
        when: windowShown

        function init() {
            controller.state = Model.initialState({}, "screenshot");
            controller.status = Model.parseStatus("");
            controller.runs = 0;
            controller.closes = 0;
            strip.forceActiveFocus();
            wait(20);
        }
        function labelOf(name) { return findChild(findChild(strip, name), "label"); }

        function test_fixedWidth() {
            const shot = strip.width;
            verify(shot > 0);
            controller.setMode("record");
            wait(20);
            compare(strip.width, shot);
            controller.status = { phase: "recording", seconds: 35999 };
            wait(20);
            compare(strip.width, shot);
        }
        function test_controlsPerMode() {
            verify(findChild(strip, "screenshot-freeze").visible);
            verify(findChild(strip, "screenshot-annotate").visible);
            verify(!findChild(strip, "record-audio").visible);
            controller.setMode("record");
            wait(20);
            verify(findChild(strip, "record-audio").visible);
            verify(findChild(strip, "record-mic").visible);
            verify(!findChild(strip, "screenshot-freeze").visible);
        }
        function test_noElidedLabel() {
            const names = ["target-screen", "target-window", "target-region",
                "screenshot-delay", "screenshot-freeze", "screenshot-annotate",
                "record-delay", "record-audio", "record-mic", "tab-screenshot", "tab-record", "action"];
            for (const name of names) verify(!labelOf(name).truncated, name + " is elided");
            controller.setMode("record");
            controller.status = { phase: "recording", seconds: 35999 };
            wait(20);
            compare(labelOf("action").text, "Stop 9:59:59");
            verify(!labelOf("action").truncated, "Stop 9:59:59 is elided");
        }
        function test_targetClickOnlySelects() {
            mouseClick(findChild(strip, "target-window"));
            compare(controller.state.shotTarget, "window");
            compare(controller.runs, 0);
        }
        function test_delayCycles() {
            mouseClick(findChild(strip, "screenshot-delay"));
            compare(controller.state.delay, 3);
            compare(labelOf("screenshot-delay").text, "3s");
        }
        function test_keys() {
            keyClick(Qt.Key_Tab);
            compare(controller.state.mode, "record");
            keyClick(Qt.Key_Return);
            compare(controller.runs, 1);
            keyClick(Qt.Key_Escape);
            compare(controller.closes, 1);
        }
        function test_tabColour() {
            verify(Qt.colorEqual(findChild(strip, "tab-screenshot").color, controller.accent));
            controller.setMode("record");
            wait(20);
            verify(Qt.colorEqual(findChild(strip, "tab-record").color, "#ff5555"));
        }
    }
}
