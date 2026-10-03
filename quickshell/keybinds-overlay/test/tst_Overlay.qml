import QtQuick
import QtTest
import ".."

Item {
    id: host
    width: 1600
    height: 900

    QtObject {
        id: controller
        property bool loading: false
        property string problem: ""
        property string query: ""
        property bool closed: false
        property var sheet: []
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property string monoFont: "monospace"
        function close() {
            closed = true;
        }
    }
    Overlay {
        id: overlay
        anchors.fill: parent
        controller: controller
    }
    TestCase {
        name: "Overlay"
        when: windowShown

        function rows(name, n) {
            const out = [];
            for (let i = 0; i < n; i++)
                out.push({ keys: ["Super", "Shift", String(i)], label: name + " row " + i });
            return { name: name, rows: out };
        }
        function find(name) {
            return findChild(overlay, name);
        }
        function init() {
            host.width = 1600;
            host.height = 900;
            controller.loading = false;
            controller.monoFont = "monospace";
            controller.problem = "";
            controller.query = "";
            controller.closed = false;
            controller.sheet = [rows("Applications", 4), rows("Windows", 3), {
                    name: "Media",
                    rows: [{ keys: ["Volume Up"], label: "Volume up" }]
                }];
            overlay.forceActiveFocus();
        }
        function test_typing_filters_and_counts() {
            keyClick("v");
            keyClick("o");
            compare(controller.query, "vo");
            compare(find("count").text, "1 of 8");
            keyClick(Qt.Key_Backspace);
            compare(controller.query, "v");
            keyClick(Qt.Key_U, Qt.ControlModifier);
            compare(controller.query, "");
            keyClick("w");
            keyClick(Qt.Key_Backspace, Qt.ControlModifier);
            compare(controller.query, "");
        }
        function test_modified_keys_do_not_type() {
            keyClick("h", Qt.MetaModifier);
            keyClick("x", Qt.AltModifier);
            compare(controller.query, "");
        }
        function test_escape_closes() {
            keyClick(Qt.Key_Escape);
            verify(controller.closed);
        }
        function test_click_closes() {
            mouseClick(overlay, 20, 20);
            verify(controller.closed);
        }
        function test_no_match_state() {
            controller.query = "zzz";
            const empty = find("empty");
            verify(empty.visible);
            verify(empty.text.indexOf("zzz") !== -1);
        }
        function test_problem_state() {
            controller.problem = "Could not read keybinds.lua";
            verify(find("problem").visible);
            verify(!find("grid").visible);
        }
        function test_prompt_stays_put_while_filtering() {
            const prompt = find("prompt");
            const before = prompt.mapToItem(overlay, 0, 0).y;
            verify(before > 100, "a short sheet is centred with its prompt, not pinned to the top");
            keyClick("v");
            compare(prompt.mapToItem(overlay, 0, 0).y, before);
            compare(find("grid").y, 0);
        }
        function test_sizes_scale_with_the_screen() {
            compare(overlay.uiScale, 1);
            compare(overlay.rowHeight, 26);
            host.width = 2560;
            host.height = 1440;
            compare(overlay.uiScale, 1.44);
            compare(overlay.rowHeight, 37);
            compare(find("prompt").font.pixelSize, 37);
            host.width = 4000;
            host.height = 2400;
            compare(overlay.uiScale, 1.6);
            // A portrait output scales by its width, not its height.
            host.width = 1080;
            host.height = 1920;
            compare(overlay.uiScale, 1);
        }
        function labels(item, out) {
            for (const child of item.children) {
                if (child.objectName === "label")
                    out.push(child);
                labels(child, out);
            }
            return out;
        }
        // Every label in the real keybinds.lua must fit, at the sizes this
        // desktop is used on. An elided label in a read-only sheet is lost.
        function test_no_real_label_is_elided() {
            const request = new XMLHttpRequest();
            let body = "";
            request.onreadystatechange = () => {
                if (request.readyState === XMLHttpRequest.DONE)
                    body = request.responseText || "-";
            };
            request.open("GET", Qt.resolvedUrl("real-sheet.json"));
            request.send();
            tryVerify(() => body !== "", 2000);
            // A missing file must fail, not skip: qmltestrunner counts a skip
            // as a pass, and test-docs.sh relies on this test on every commit.
            verify(body !== "-", "real-sheet.json is written by run-tests.sh; run the suite through it");
            const real = JSON.parse(body);
            controller.sheet = real.sections;
            // Keycap widths decide a label's room, so measure in the live font.
            controller.monoFont = real.font || "monospace";
            for (const [w, h] of [[1366, 768], [1920, 1080], [2560, 1440], [1080, 1920]]) {
                host.width = w;
                host.height = h;
                waitForRendering(overlay);
                const cut = labels(overlay, []).filter(l => l.truncated).map(l => l.text);
                compare(cut.join(" | "), "", "labels elided at " + w + "x" + h);
            }
        }
        function test_columns_follow_width() {
            compare(overlay.columns, 4);
            host.width = 700;
            compare(overlay.columns, 2);
        }
        function test_wheel_scrolls_only_on_overflow() {
            const flick = find("flick");
            mouseWheel(overlay, 400, 400, 0, -120);
            compare(flick.scrollTarget, 0, "nothing overflows, so the wheel does nothing");
            wait(200);
            compare(flick.contentY, 0);
            controller.sheet = [rows("A", 30), rows("B", 30), rows("C", 30), rows("D", 30)];
            host.height = 400;
            waitForRendering(overlay);
            mouseWheel(overlay, 400, 200, 0, -120);
            mouseWheel(overlay, 400, 200, 0, -120);
            mouseWheel(overlay, 400, 200, 0, -120);
            // Back-to-back steps add up instead of restarting from the
            // half-animated position.
            tryVerify(() => flick.contentY >= 360);
            keyClick("a");
            compare(flick.scrollTarget, 0, "a new filter starts at the top");
            tryCompare(flick, "contentY", 0);
        }
    }
}
