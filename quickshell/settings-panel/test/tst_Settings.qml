import QtQuick
import QtTest
import ".."

Item {
    width: 1280; height: 900
    QtObject {
        id: controller
        property bool closed: false
        property bool busy: false
        property bool loading: false
        property bool loaded: true
        property string problem: ""
        property string query: ""
        property string category: "appearance"
        property string mainMonitor: ""
        property var monitors: []
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property color accentText: "#05090c"
        property var calls: []
        property var catalog: ({categories: [{id:"appearance",title:"Appearance",description:"Look and feel"}, {id:"input",title:"Input",description:"Mouse and keyboard"}], rows: [
            {id:"blur",category:"appearance",title:"Blur",description:"Frosted glass",kind:"toggle"},
            {id:"size",category:"appearance",title:"Size",description:"Radius",kind:"slider",min:1,max:20,step:1},
            {id:"font",category:"appearance",title:"Font",description:"Main font",kind:"text"},
            {id:"focus",category:"input",title:"Focus",description:"Pointer focus",kind:"select",items:[{label:"Off",value:"0"},{label:"On",value:"1"}]}
        ]})
        property var values: ({blur:{value:true,reset:true},size:{value:4},font:{value:"Sans"},focus:{value:"1"}})
        readonly property var visibleRows: catalog.rows.filter(row => query ? row.title.toLowerCase().includes(query.toLowerCase()) : row.category === category)
        function close() { closed = true; }
        function select(id) { query = ""; category = id; }
        function change(id,value) { calls = calls.concat([{id:id,value:value}]); }
        function reset(id) { calls = calls.concat([{reset:id}]); }
        function action(id) { calls = calls.concat([{action:id}]); }
        function submit(request) { calls = calls.concat([request]); }
    }
    SettingsView { id: view; anchors.fill: parent; controller: controller }
    TestCase {
        name: "Settings"
        when: windowShown
        function init() {
            controller.closed = false; controller.query = ""; controller.category = "appearance";
            controller.calls = []; controller.busy = false;
            controller.loaded = true; controller.loading = false;
            view.forceActiveFocus();
            findChild(view,"settingsScroll").contentItem.contentY = 0;
            waitForRendering(view);
        }
        function test_no_writes_on_build() { wait(50); compare(controller.calls.length,0); }
        function test_search_keyboard() {
            keyClick(Qt.Key_F,Qt.ControlModifier);
            const search = findChild(view,"settingsSearch");
            verify(search.activeFocus);
            keyClick(Qt.Key_F); keyClick(Qt.Key_O); keyClick(Qt.Key_N); keyClick(Qt.Key_T);
            compare(controller.visibleRows.length,1);
            compare(controller.visibleRows[0].id,"font");
            compare(controller.calls.length,0);
        }
        function test_escape_from_search() {
            findChild(view,"settingsSearch").forceActiveFocus();
            keyClick(Qt.Key_Escape); compare(controller.closed,true);
        }
        function test_outside_closes_inside_does_not() {
            mouseClick(view,640,95); compare(controller.closed,false);
            mouseClick(view,5,5); compare(controller.closed,true);
        }
        function test_categories_and_empty_results() {
            controller.select("input"); wait(20);
            compare(controller.visibleRows[0].kind,"select");
            controller.query = "nothing"; wait(20);
            compare(controller.visibleRows.length,0);
            compare(controller.calls.length,0);
        }
        function test_toggle_and_slider_submit_only_on_user_input() {
            const toggle = findChild(view,"toggle-blur");
            mouseClick(toggle);
            compare(controller.calls.length,1);
            compare(controller.calls[0].id,"blur");
            compare(controller.calls[0].value,false);
            controller.calls = [];
            const slider = findChild(view,"slider-size");
            mousePress(slider,slider.width * 0.3,slider.height / 2);
            mouseMove(slider,slider.width * 0.6,slider.height / 2,20);
            compare(controller.calls.length,0);
            mouseRelease(slider,slider.width * 0.6,slider.height / 2);
            compare(controller.calls.length,1);
            compare(controller.calls[0].id,"size");
        }
        function test_text_requires_explicit_save() {
            const entry = findChild(view,"entry-font");
            entry.forceActiveFocus();
            keyClick(Qt.Key_A,Qt.ControlModifier);
            keyClick(Qt.Key_F); keyClick(Qt.Key_O); keyClick(Qt.Key_O);
            compare(controller.calls.length,0);
            keyClick(Qt.Key_Return);
            compare(controller.calls.length,1);
            compare(controller.calls[0].value,"foo");
        }
        function test_busy_prevents_new_edits() {
            controller.busy = true;
            mouseClick(findChild(view,"toggle-blur"));
            compare(controller.calls.length,0);
        }
        function test_loading_does_not_shift_page() {
            const scroll = findChild(view,"settingsScroll");
            const y = scroll.y, height = scroll.height;
            controller.loading = true;
            wait(20);
            compare(scroll.y,y); compare(scroll.height,height);
            compare(scroll.opacity,1);
            controller.loading = false;
            wait(20);
            compare(scroll.y,y); compare(scroll.height,height);
            compare(findChild(view,"closeSettings").text,"Close");
        }
        function test_dropdown_popup_theme_and_keyboard_selection() {
            controller.select("input"); wait(20);
            const combo = findChild(view,"select-focus");
            combo.forceActiveFocus();
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            compare(combo.popup.background.color,view.plate);
            keyClick(Qt.Key_Up); keyClick(Qt.Key_Return);
            tryCompare(combo.popup,"visible",false);
            compare(controller.calls.length,1);
            compare(controller.calls[0].value,"0");
        }
    }
}
