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
        property string interacting: ""
        property var pendingDisplay: null
        property var stagedDisplays: ({})
        property bool keepPendingOnRevert: false
        function keepDisplay() { calls = calls.concat([{op:"displayKeep"}]); }
        function revertDisplay() { if (!keepPendingOnRevert) pendingDisplay = null; calls = calls.concat([{op:"displayRevert"}]); }
        property var catalog: ({categories: [{id:"appearance",title:"Appearance",description:"Look and feel"}, {id:"input",title:"Input",description:"Mouse and keyboard"}, {id:"monitors",title:"Displays",description:"Screens"}], rows: [
            {id:"blur",category:"appearance",title:"Blur",description:"Frosted glass",kind:"toggle"},
            {id:"size",category:"appearance",title:"Size",description:"Radius",kind:"slider",min:1,max:20,step:1},
            {id:"font",category:"appearance",title:"Font",description:"Main font",kind:"text"},
            {id:"nickname",category:"appearance",title:"Nickname",description:"Optional label",kind:"text",optional:true},
            {id:"theme",category:"appearance",title:"Theme",description:"GTK",kind:"select",choices:"gtk-themes"},
            {id:"focus",category:"input",title:"Focus",description:"Pointer focus",kind:"select",items:[{label:"Off",value:"0"},{label:"On",value:"1"}]},
            {id:"idle",category:"input",title:"Idle",description:"Hide",kind:"slider",min:0,max:30,step:1,format:"seconds",zeroLabel:"Never"},
            {id:"mic",category:"input",title:"Mic",description:"Level",kind:"slider",min:0,max:100,step:1,format:"percent"}
        ]})
        property var values: ({blur:{value:true,reset:true},size:{value:4},font:{value:"Sans"},nickname:{value:"Bob"},theme:{value:"B",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]},focus:{value:"1"},idle:{value:0},mic:{value:62}})
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
            controller.calls = []; controller.busy = false; controller.interacting = "";
            controller.loaded = true; controller.loading = false;
            controller.pendingDisplay = null; controller.monitors = []; controller.stagedDisplays = ({}); controller.keepPendingOnRevert = false;
            controller.values = ({blur:{value:true,reset:true},size:{value:4},font:{value:"Sans"},nickname:{value:"Bob"},theme:{value:"B",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]},focus:{value:"1"},idle:{value:0},mic:{value:62}});
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
        function test_optional_text_can_be_cleared() {
            const entry = findChild(view,"entry-nickname");
            entry.forceActiveFocus();
            keyClick(Qt.Key_A,Qt.ControlModifier);
            keyClick(Qt.Key_Delete);
            keyClick(Qt.Key_Return);
            compare(controller.calls.length,1);
            compare(controller.calls[0].id,"nickname");
            compare(controller.calls[0].value,"");
        }
        function test_non_optional_text_empty_submits_nothing() {
            const entry = findChild(view,"entry-font");
            entry.forceActiveFocus();
            keyClick(Qt.Key_A,Qt.ControlModifier);
            keyClick(Qt.Key_Delete);
            keyClick(Qt.Key_Return);
            compare(controller.calls.length,0);
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
        function test_zero_label() {
            controller.select("input"); wait(20);
            const slider = findChild(view,"slider-idle");
            verify(slider);
            compare(slider.parent.children[1].text,"Never");
        }
        function test_percent_format() {
            controller.select("input"); wait(20);
            const slider = findChild(view,"slider-mic");
            verify(slider);
            compare(slider.parent.children[1].text,"62 %");
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
        function test_dynamic_choices() {
            const combo = findChild(view,"select-theme");
            compare(combo.currentIndex,1);
            combo.forceActiveFocus();
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            keyClick(Qt.Key_Up); keyClick(Qt.Key_Return);
            tryCompare(combo.popup,"visible",false);
            compare(controller.calls[0].value,"A");
        }
        function test_unknown_select_value_is_displayed() {
            controller.values = Object.assign({},controller.values,{theme:{value:"Custom",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]}});
            wait(20);
            const combo = findChild(view,"select-theme");
            compare(combo.currentIndex,-1);
            compare(combo.displayText,"Custom");
        }
        function test_long_select_popup_height_is_capped() {
            const choices = [];
            for (let index = 0; index < 40; ++index)
                choices.push({label:"Theme " + index,value:"theme-" + index});
            controller.values = Object.assign({},controller.values,{theme:{value:"theme-0",choices:choices}});
            wait(20);
            const combo = findChild(view,"select-theme");
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            verify(combo.popup.height <= 320);
            keyClick(Qt.Key_Escape);
            tryCompare(combo.popup,"visible",false);
        }
        function test_slider_and_popup_report_interaction() {
            const slider = findChild(view,"slider-size");
            mousePress(slider, slider.width / 2, slider.height / 2);
            compare(controller.interacting,"size");
            mouseRelease(slider, slider.width / 2, slider.height / 2);
            compare(controller.interacting,"");
            const combo = findChild(view,"select-theme");
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            compare(controller.interacting,"theme");
            keyClick(Qt.Key_Escape);
            tryCompare(controller,"interacting","");
        }
        function test_destroyed_control_releases_interaction() {
            const combo = findChild(view,"select-theme");
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            compare(controller.interacting,"theme");
            // Switching page destroys the row while its popup is still open.
            controller.select("input"); wait(50);
            compare(controller.interacting,"");
        }
        function pg279q(extra) {
            return Object.assign({name:"DP-1",make:"Ancor",model:"PG279Q",width:2560,height:1440,refreshRate:144,scale:1,disabled:false,saved:null,handEdited:false,
                availableModes:["2560x1440@144.00Hz","2560x1440@120.00Hz"],
                choices:{modes:[{label:"Automatic",value:"highres@highrr"},{label:"2560 × 1440 · 144 Hz",value:"2560x1440@144.00"},{label:"2560 × 1440 · 120 Hz",value:"2560x1440@120.00"}],
                         positions:[{label:"Automatic",value:"auto"},{label:"Left of the others",value:"auto-left"}],
                         transforms:[{label:"Normal",value:0},{label:"90°",value:1}]}}, extra || {});
        }
        function pick(name, downs) {
            const combo = findChild(view,name);
            mouseClick(combo); tryCompare(combo.popup,"visible",true);
            for (let i = 0; i < downs; ++i) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return); tryCompare(combo.popup,"visible",false);
        }
        function test_display_card_stages_one_apply() {
            controller.monitors = [pg279q()]; controller.select("monitors"); wait(20);
            const apply = findChild(view,"applyDisplay-DP-1");
            verify(!apply.enabled);
            pick("select-DP-1-mode", 2);   // Automatic → 120 Hz
            pick("select-DP-1-scale", 2);  // 100 % → 107 % → 125 %
            compare(controller.calls.length,0);
            verify(apply.enabled);
            mouseClick(apply);
            compare(controller.calls.length,1);
            compare(JSON.stringify(controller.calls[0]),JSON.stringify({op:"displayApply",output:"DP-1",mode:"2560x1440@120.00",position:"auto",scale:1.25,transform:0}));
        }
        function test_hand_edited_display_is_locked() {
            controller.monitors = [pg279q({handEdited:true})]; controller.select("monitors"); wait(20);
            verify(!findChild(view,"applyDisplay-DP-1").enabled);
            verify(findChild(view,"handEdited-DP-1").visible);
        }
        function test_staged_mode_resets_an_invalid_scale() {
            const monitor = pg279q({availableModes:["2560x1440@144.00Hz","2560x1440@120.00Hz","1024x768@60.00Hz"]});
            monitor.choices.modes = monitor.choices.modes.concat([{label:"1024 × 768 · 60 Hz",value:"1024x768@60.00"}]);
            controller.monitors = [monitor]; controller.select("monitors"); wait(20);
            pick("select-DP-1-scale", 2);  // 125 % divides 2560×1440
            pick("select-DP-1-mode", 3);   // 1024×768: 125 % does not divide it
            const scale = findChild(view,"select-DP-1-scale");
            verify(!scale.choices.some(c => c.value === 1.25));
            compare(scale.value,1);
            mouseClick(findChild(view,"applyDisplay-DP-1"));
            compare(controller.calls[0].mode,"1024x768@60.00");
            compare(controller.calls[0].scale,1);
        }
        function test_everything_else_waits_while_a_display_change_is_pending() {
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() + 60000}; wait(20);
            verify(!findChild(view,"toggle-blur").enabled);
            verify(!findChild(view,"reloadHyprland").enabled);
            controller.monitors = [pg279q()]; controller.select("monitors"); wait(20);
            for (const name of ["mainDisplay-DP-1","editDisplaysFile","automaticMainDisplay","applyDisplay-DP-1","automaticDisplay-DP-1","restartWaybar","updateSystem"])
                verify(!findChild(view,name).enabled, name + " waits");
            controller.pendingDisplay = null; controller.select("appearance"); wait(20);
            verify(findChild(view,"toggle-blur").enabled);
            verify(findChild(view,"reloadHyprland").enabled);
        }
        function test_staged_edits_survive_a_refresh() {
            controller.monitors = [pg279q()]; controller.select("monitors"); wait(20);
            const mode = findChild(view,"select-DP-1-mode");
            mouseClick(mode); tryCompare(mode.popup,"visible",true);
            compare(controller.interacting,"display:DP-1");
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            tryCompare(mode.popup,"visible",false);
            compare(controller.interacting,"");
            controller.monitors = [pg279q()]; wait(50);   // a live read replaces the array
            const apply = findChild(view,"applyDisplay-DP-1");
            verify(apply.enabled);
            mouseClick(apply);
            compare(controller.calls[0].mode,"2560x1440@120.00");
            compare(JSON.stringify(controller.stagedDisplays),"{}");
        }
        function test_changing_back_leaves_nothing_staged() {
            controller.monitors = [pg279q()]; controller.select("monitors"); wait(20);
            pick("select-DP-1-mode", 2);
            verify(findChild(view,"applyDisplay-DP-1").enabled);
            pick("select-DP-1-mode", 0);   // back to Automatic, the saved value
            // the popup opens on the current item: Up twice returns to Automatic
            const mode = findChild(view,"select-DP-1-mode");
            mouseClick(mode); tryCompare(mode.popup,"visible",true);
            keyClick(Qt.Key_Up); keyClick(Qt.Key_Up); keyClick(Qt.Key_Return);
            tryCompare(mode.popup,"visible",false);
            verify(!findChild(view,"applyDisplay-DP-1").enabled);
            compare(JSON.stringify(controller.stagedDisplays),"{}");
        }
        function test_countdown_reverts_once_per_deadline() {
            controller.keepPendingOnRevert = true;
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() - 1};
            wait(1200);
            compare(controller.calls.filter(c => c.op === "displayRevert").length,1);
            controller.keepPendingOnRevert = false; controller.pendingDisplay = null;
        }
        function test_pending_banner_keep_and_timeout() {
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() + 60000}; wait(20);
            verify(findChild(view,"displayPending").visible);
            verify(findChild(view,"displayCountdown").text.indexOf("Reverting in") >= 0);
            mouseClick(findChild(view,"keepDisplay"));
            compare(controller.calls[0].op,"displayKeep");
            controller.calls = [];
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() + 300};
            tryVerify(() => controller.calls.length === 1 && controller.calls[0].op === "displayRevert", 3000);
            wait(600);
            compare(controller.calls.length,1);
        }
        function test_many_categories_stay_inside_the_panel() {
            const saved = controller.catalog;
            const categories = [];
            for (let index = 0; index < 20; ++index) categories.push({id:"c" + index,title:"Category " + index,description:""});
            controller.catalog = ({categories: categories, rows: saved.rows});
            wait(50);
            const panel = findChild(view,"settingsPanel");
            const close = findChild(view,"closeSettings");
            const bottom = close.mapToItem(panel,0,close.height).y;
            verify(bottom <= panel.height, "Close ends at " + bottom + " inside a " + panel.height + " px panel");
            controller.catalog = saved;
            wait(20);
        }
    }
}
