import QtQuick
import QtTest
import ".."
import "../autostart.mjs" as Autostart
import "../network.mjs" as Network

Item {
    width: 1280; height: 900
    // Built, not literal: the doctor's path scan would flag fixture files that do not exist.
    readonly property string userAutostart: "~/.config" + "/autostart"
    QtObject {
        id: controller
        property bool closed: false
        property bool busy: false
        property bool authPending: false
        property bool loading: false
        property bool loaded: true
        property string problem: ""
        property string query: ""
        property string category: "appearance"
        property string mainMonitor: ""
        property var monitors: []
        property var network: null
        property var startup: null
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
        property var catalog: ({categories: [{id:"appearance",title:"Appearance",description:"Look and feel"}, {id:"input",title:"Input",description:"Mouse and keyboard"}, {id:"monitors",title:"Displays",description:"Screens"}, {id:"network",title:"Network",description:"Connections"}, {id:"startup",title:"Startup",description:"Login"}], rows: [
            {id:"blur",category:"appearance",title:"Blur",description:"Frosted glass",kind:"toggle"},
            {id:"size",category:"appearance",title:"Size",description:"Radius",kind:"slider",min:1,max:20,step:1},
            {id:"font",category:"appearance",title:"Font",description:"Main font",kind:"text"},
            {id:"nickname",category:"appearance",title:"Nickname",description:"Optional label",kind:"text",optional:true},
            {id:"theme",category:"appearance",title:"Theme",description:"GTK",kind:"select",choices:"gtk-themes"},
            {id:"focus",category:"input",title:"Focus",description:"Pointer focus",kind:"select",items:[{label:"Off",value:"0"},{label:"On",value:"1"}]},
            {id:"zone",category:"input",title:"Zone",description:"Time zone",kind:"select",choices:"timezones",auth:true},
            {id:"ntp",category:"input",title:"NTP",description:"Sync",kind:"toggle",auth:true},
            {id:"idle",category:"input",title:"Idle",description:"Hide",kind:"slider",min:0,max:30,step:1,format:"seconds",zeroLabel:"Never"},
            {id:"mic",category:"input",title:"Mic",description:"Level",kind:"slider",min:0,max:100,step:1,format:"percent"},
            {id:"network.wifi",category:"network",title:"Wi-Fi",description:"Radio",kind:"toggle",inView:true},
            {id:"opt-lock",category:"startup",title:"Lock",description:"Lock on autologin",kind:"toggle"}
        ]})
        property var values: ({blur:{value:true,reset:true},size:{value:4},font:{value:"Sans"},nickname:{value:"Bob"},theme:{value:"B",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]},focus:{value:"1"},zone:{value:"Europe/Rome",choices:Array.from({length:30},(_,i)=>i===7?{label:"Europe / Rome",value:"Europe/Rome"}:i===8?{label:"New York",value:"America/New_York"}:{label:"Zone "+i,value:"Z"+i})},ntp:{value:true,note:"Synchronized with a time server"},idle:{value:0},mic:{value:62},"network.wifi":{value:true},"opt-lock":{value:false}})
        readonly property var visibleRows: catalog.rows.filter(row => query ? row.title.toLowerCase().includes(query.toLowerCase()) : row.category === category && !row.inView)
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
        function startupFixture() {
            return {session: ["waybar", "systemctl --user start …"],
                apps: [
                    {id: "nm-applet.desktop", name: "Network", origin: "system", enabled: true, scope: "", installed: true, status: {state: "running", label: "Running"}},
                    {id: "mine.desktop", name: "Mine", origin: "user", removable: true, enabled: true, scope: "", installed: true, status: {state: "none", label: "Not started this session"}},
                    {id: "kde.desktop", name: "KDE thing", origin: "system", enabled: true, scope: "Not for Hyprland", installed: true, status: {state: "none", label: ""}},
                    {id: "gnome.desktop", name: "Gnome flag", origin: "system", enabled: true, ignoredGnomeFlag: true, scope: "", installed: true, status: {state: "none", label: ""}},
                    {id: "arch-update-tray.desktop", name: "Arch-Update", origin: "user", removable: true, enabled: true, scope: "", installed: false, status: {state: "missing", label: "Not installed: arch-update"}},
                    {id: "linked.desktop", name: "Linked", origin: "user", removable: true, link: true, enabled: true, scope: "", installed: true, status: {state: "none", label: ""}},
                    {id: "renamed.desktop", name: "Renamed", origin: "override", removable: true, staleOverride: true, enabled: false, scope: "", installed: true, status: {state: "none", label: "Hidden by " + userAutostart + "/renamed.desktop"}}],
                available: [{id: "firefox.desktop", name: "Firefox"}]};
        }
        function test_startup_view() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            compare(findChild(view, "session-0").text, "waybar");
            verify(findChild(view, "startup-nm-applet.desktop"));
            verify(!findChild(view, "startupSwitch-kde.desktop"), "an entry that does not apply to Hyprland has no switch");
            verify(!findChild(view, "startupRemove-nm-applet.desktop"), "system entries cannot be removed");
            verify(findChild(view, "startupStatus-gnome.desktop").text.indexOf("X-GNOME-Autostart-enabled has no effect under systemd") >= 0);
            mouseClick(findChild(view, "startupSwitch-nm-applet.desktop"));
            compare(controller.calls[controller.calls.length - 1], {op: "autostart", action: "disable", id: "nm-applet.desktop"});
            verify(findChild(view, "startupStatus-arch-update-tray.desktop").text.indexOf("arch-update") >= 0);
            compare(findChild(view, "startupStatus-mine.desktop").text.indexOf("Added by you"), -1);
            verify(findChild(view, "startupStatus-mine.desktop").text.indexOf("In ~/.config/autostart") >= 0);
            verify(findChild(view, "toggle-opt-lock"), "the option rows still render below the view");
        }
        function test_startup_remove_asks_twice() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            const remove = findChild(view, "startupRemove-mine.desktop");
            compare(remove.text, "Remove");
            mouseClick(remove);
            compare(remove.text, "Confirm remove");
            compare(controller.calls.length, 0, "the first click deletes nothing");
            mouseClick(remove);
            compare(controller.calls[controller.calls.length - 1], {op: "autostart", action: "remove", id: "mine.desktop"});
            compare(remove.text, "Remove");
            // Any other action cancels the pending confirmation.
            controller.calls = [];
            mouseClick(remove);
            compare(remove.text, "Confirm remove");
            mouseClick(findChild(view, "startupSwitch-nm-applet.desktop"));
            compare(remove.text, "Remove");
            mouseClick(remove);
            compare(controller.calls.length, 1, "the switch was the only call; the next click asks again");
            // Another row's Remove moves the confirmation; 5 s of nothing drops it.
            const other = findChild(view, "startupRemove-arch-update-tray.desktop");
            mouseClick(other);
            compare(remove.text, "Remove");
            compare(other.text, "Confirm remove");
            findChild(view, "startupView").confirmMs = 50;
            mouseClick(remove);
            compare(remove.text, "Confirm remove");
            tryCompare(remove, "text", "Remove");
            compare(controller.calls.length, 1);
        }
        function test_startup_stale_override_and_links() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            verify(findChild(view, "startupRemove-renamed.desktop"), "a stale override can be removed");
            verify(findChild(view, "startupStatus-renamed.desktop").text.indexOf("Hidden by " + userAutostart + "/renamed.desktop") >= 0);
            verify(findChild(view, "startupSwitch-renamed.desktop"));
            verify(!findChild(view, "startupRemove-linked.desktop"), "a link is never removed from here");
            verify(!findChild(view, "startupSwitch-linked.desktop"), "a link is never switched from here");
            verify(findChild(view, "startupStatus-linked.desktop").text.indexOf("link") >= 0);
        }
        function test_startup_error_only_on_its_view() {
            controller.startup = {error: "Permission denied: autostart.lua"}; controller.category = "startup"; waitForRendering(view);
            verify(findChild(view, "startupError").visible);
            verify(findChild(view, "startupError").text.indexOf("Permission denied") >= 0);
            verify(!findChild(view, "startup-nm-applet.desktop"));
            verify(!findChild(view, "select-startupAdd").visible);
            verify(findChild(view, "toggle-opt-lock"), "the option rows still render below the view");
        }
        function test_startup_add() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            const combo = findChild(view, "select-startupAdd");
            // The longer list pushes the combo below the fold.
            const flick = findChild(view, "settingsScroll").contentItem;
            flick.contentY = Math.max(0, combo.mapToItem(flick.contentItem, 0, 0).y - 200);
            waitForRendering(view);
            combo.forceActiveFocus();
            mouseClick(combo);
            tryCompare(combo.popup, "visible", true);
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            tryCompare(combo.popup, "visible", false);
            compare(controller.calls[controller.calls.length - 1], {op: "autostartAdd", app: "firefox.desktop"});
        }
        function test_pure_modules_load_in_qml() {
            const entries = Autostart.autostartEntries({system:[{id:"nm-applet.desktop",text:"[Desktop Entry]\nType=Application\nName=Network\nExec=nm-applet\n"}],user:[],desktops:["Hyprland"],onPath:function() { return true; }});
            compare(entries.length, 1);
            compare(Autostart.withStatus(entries, [{unit:entries[0].unit,active:"active"}])[0].status.state, "running");
            compare(Autostart.unitName("nm-applet.desktop"), "app-nm\\x2dapplet@autostart.service");
            compare(Autostart.setHidden("[Desktop Entry]\nName=X\n", true), "[Desktop Entry]\nName=X\nHidden=true\n");
            compare(Autostart.sessionCommands('hl.exec_cmd("waybar")')[0], "waybar");
            verify(Autostart.isMinimalOverride(Autostart.minimalOverride("X"), "X"));
            verify(Autostart.isMinimalShape(Autostart.minimalOverride("Y")));
            compare(Autostart.parseEnvironment("PATH=$'/a\\'b:/c'\n").PATH, "/a'b:/c");
            compare(Autostart.appScope({Exec: "x"}, ["Hyprland"]), "");
            const snap = {connections:[],accessPoints:[{ssid:"Cafe",strength:80,flags:0,wpaFlags:0,rsnFlags:0}]};
            compare(Network.wifiNetworks(snap)[0].ssid, "Cafe");
            compare(Network.securityOf(snap.accessPoints[0]), "open");
            compare(Network.connectPlan(snap, {ssid:"Cafe"}).kind, "add");
        }
        function init() {
            controller.closed = false; controller.query = ""; controller.category = "appearance";
            controller.calls = []; controller.busy = false; controller.interacting = "";
            controller.authPending = false;
            controller.loaded = true; controller.loading = false;
            controller.pendingDisplay = null; controller.monitors = []; controller.stagedDisplays = ({}); controller.keepPendingOnRevert = false;
            controller.network = null; controller.startup = null;
            controller.values = ({blur:{value:true,reset:true},size:{value:4},font:{value:"Sans"},nickname:{value:"Bob"},theme:{value:"B",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]},focus:{value:"1"},zone:{value:"Europe/Rome",choices:Array.from({length:30},(_,i)=>i===7?{label:"Europe / Rome",value:"Europe/Rome"}:i===8?{label:"New York",value:"America/New_York"}:{label:"Zone "+i,value:"Z"+i})},ntp:{value:true,note:"Synchronized with a time server"},idle:{value:0},mic:{value:62},"network.wifi":{value:true},"opt-lock":{value:false}});
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
        function test_note_replaces_description() {
            controller.category = "input"; waitForRendering(view);
            const note = findChild(view, "note-ntp");
            verify(note);
            compare(note.text, "Synchronized with a time server");
        }
        function test_long_select_filters() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-zone");
            mouseClick(combo); waitForRendering(view);
            const filter = findChild(combo.popup.contentItem, "filter-zone");
            verify(filter && filter.visible);
            for (const c of "new_york") keyClick(c);
            compare(combo.shown.length, 1);
            compare(combo.shown[0].value, "America/New_York");
            compare(combo.filterIndex, 0);
            keyClick(Qt.Key_Enter);
            compare(controller.calls[controller.calls.length - 1], {id: "zone", value: "America/New_York"});
            compare(combo.filter, "");
        }
        function test_short_select_has_no_filter() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-focus");
            mouseClick(combo); waitForRendering(view);
            const filter = findChild(combo.popup.contentItem, "filter-focus");
            verify(!filter || !filter.visible);
            keyClick(Qt.Key_Escape);
        }
        function test_auth_banner_and_disabled_controls() {
            controller.category = "input"; controller.authPending = true; waitForRendering(view);
            verify(findChild(view, "authPending").visible);
            verify(!findChild(view, "toggle-ntp").enabled);
        }
        function test_auth_combo_arrows_open_without_committing() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-zone");
            combo.forceActiveFocus();
            keyClick(Qt.Key_Up);
            tryCompare(combo.popup, "visible", true);
            compare(controller.calls.length, 0);
            keyClick(Qt.Key_Escape);
            tryCompare(combo.popup, "visible", false);
            keyClick(Qt.Key_Down);
            tryCompare(combo.popup, "visible", true);
            compare(controller.calls.length, 0);
            keyClick(Qt.Key_Escape);
        }
        function test_auth_combo_other_keys_open_without_committing() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-zone");
            for (const key of [Qt.Key_End, Qt.Key_Home, Qt.Key_PageDown]) {
                combo.forceActiveFocus();
                keyClick(key);
                tryCompare(combo.popup, "visible", true);
                compare(controller.calls.length, 0);
                keyClick(Qt.Key_Escape);
                tryCompare(combo.popup, "visible", false);
            }
            combo.forceActiveFocus();
            keyClick("z");
            tryCompare(combo.popup, "visible", true);
            compare(combo.filter, "z", "a typed letter seeds the filter instead of committing a match");
            compare(controller.calls.length, 0);
            keyClick(Qt.Key_Escape);
        }
        function test_filter_without_matches_commits_nothing() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-zone");
            mouseClick(combo); waitForRendering(view);
            const filter = combo.popup.contentItem.children.find(item => item.objectName === "filter-zone") || findChild(combo.popup.contentItem, "filter-zone");
            filter.forceActiveFocus();
            for (const c of "qqqq") keyClick(c);
            compare(combo.shown.length, 0);
            keyClick(Qt.Key_Up);
            compare(combo.filterIndex, -1);
            keyClick(Qt.Key_Return);
            compare(controller.calls.length, 0);
            keyClick(Qt.Key_Escape);
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
        function networkFixture() {
            return {running: true,
                wifi: {enabled: true, available: true, networks: [
                    {ssid: "Home", signal: 84, bars: 4, security: "psk", known: true, active: true},
                    {ssid: "Cafe", signal: 60, bars: 3, security: "open", known: false, active: false},
                    {ssid: "Neighbour", signal: 40, bars: 2, security: "psk", known: false, active: false},
                    {ssid: "Office", signal: 30, bars: 2, security: "unsupported", known: false, active: false}]},
                wired: [{iface: "eno1", carrier: true, speed: 1000, ip4: "192.168.1.10/24", gateway: "192.168.1.1"}],
                vpn: [{uuid: "u-proton", name: "ProtonVPN IT#113", state: "activated", iface: "proton0", proton: true, control: "app"},
                      {uuid: "u-work", name: "Work", state: "off", iface: null, proton: false, control: "switch"}],
                proton: {mode: "app", active: true}};
        }
        function openNetwork() { controller.network = networkFixture(); controller.category = "network"; waitForRendering(view); }
        function test_network_lists_and_connects() {
            openNetwork();
            verify(findChild(view, "wifi-Home")); verify(findChild(view, "wifi-Office"));
            verify(!findChild(view, "toggle-network.wifi"), "the radio row is drawn by the view, not the row list");
            verify(findChild(view, "wifiRadio"));
            mouseClick(findChild(view, "wifi-Cafe"));
            compare(controller.calls[controller.calls.length - 1], {op: "wifiConnect", ssid: "Cafe"});
            const before = controller.calls.length;
            mouseClick(findChild(view, "wifi-Neighbour"));
            compare(controller.calls.length, before, "a secured unknown network asks for a password first");
            const field = findChild(view, "psk-Neighbour");
            verify(field && field.visible);
            compare(field.echoMode, TextInput.Password);
            field.forceActiveFocus();
            for (const c of "secret123") keyClick(c);
            mouseClick(findChild(view, "connect-Neighbour"));
            compare(controller.calls[controller.calls.length - 1], {op: "wifiConnect", ssid: "Neighbour", psk: "secret123"});
            compare(field.text, "");
        }
        function test_network_active_row_click_is_noop() {
            openNetwork();
            const before = controller.calls.length;
            mouseClick(findChild(view, "wifi-Home"));
            compare(controller.calls.length, before, "clicking the already-active network does nothing");
        }
        function test_network_enterprise_is_not_connectable() {
            openNetwork();
            const before = controller.calls.length;
            mouseClick(findChild(view, "wifi-Office"));
            compare(controller.calls.length, before);
            verify(findChild(view, "advanced-Office"));
        }
        function test_network_forget_only_known() {
            openNetwork();
            verify(findChild(view, "forget-Home"));
            verify(!findChild(view, "forget-Cafe"));
            mouseClick(findChild(view, "forget-Home"));
            compare(controller.calls[controller.calls.length - 1], {op: "wifiForget", ssid: "Home"});
        }
        function test_network_vpn_switch_and_proton_app() {
            openNetwork();
            verify(!findChild(view, "vpn-u-proton"), "Proton in app mode has no switch");
            mouseClick(findChild(view, "protonApp"));
            compare(controller.calls[controller.calls.length - 1], {action: "protonApp"});
            mouseClick(findChild(view, "vpn-u-work"));
            compare(controller.calls[controller.calls.length - 1], {op: "vpn", uuid: "u-work", active: true});
        }
        function test_network_down_and_search() {
            controller.network = {running: false}; controller.category = "network"; waitForRendering(view);
            verify(findChild(view, "networkDown").visible);
            controller.query = "wi-fi"; waitForRendering(view);
            verify(findChild(view, "toggle-network.wifi"), "search still finds the radio row");
        }
        function test_network_password_survives_live_rebuild() {
            openNetwork();
            mouseClick(findChild(view, "wifi-Neighbour"));
            const field = findChild(view, "psk-Neighbour");
            verify(field && field.visible);
            field.forceActiveFocus();
            for (const c of "secret123") keyClick(c);
            compare(field.text, "secret123");
            // A live read replaces controller.network wholesale (new arrays), which
            // used to recreate delegates and wipe a half-typed password.
            controller.network = networkFixture();
            wait(20);
            const rebuilt = findChild(view, "psk-Neighbour");
            verify(rebuilt && rebuilt.visible, "the password row must still be expanded after a live rebuild");
            compare(rebuilt.text, "secret123");
        }
        function test_network_password_clears_on_collapse() {
            openNetwork();
            mouseClick(findChild(view, "wifi-Neighbour"));
            let field = findChild(view, "psk-Neighbour");
            field.forceActiveFocus();
            for (const c of "secret123") keyClick(c);
            compare(field.text, "secret123");
            mouseClick(findChild(view, "wifi-Neighbour")); // collapse
            wait(20);
            verify(!field.visible);
            mouseClick(findChild(view, "wifi-Neighbour")); // reopen
            wait(20);
            field = findChild(view, "psk-Neighbour");
            compare(field.text, "", "a typed password must not survive a collapse");
        }
        function test_network_click_on_disabled_connect_keeps_row_open() {
            openNetwork();
            mouseClick(findChild(view, "wifi-Neighbour"));
            const field = findChild(view, "psk-Neighbour");
            field.forceActiveFocus();
            for (const c of "abc") keyClick(c);
            const connect = findChild(view, "connect-Neighbour");
            verify(!connect.enabled, "three characters are not a valid WPA2 password");
            const before = controller.calls.length;
            mouseClick(connect);
            wait(20);
            verify(field.visible, "a click on the disabled Connect button must not collapse the row");
            compare(field.text, "abc");
            compare(controller.calls.length, before);
        }
        function test_network_sae_connect_mirrors_the_byte_limit() {
            const data = networkFixture();
            data.wifi.networks.push({ssid: "Wpa3", signal: 50, bars: 2, security: "sae", known: false, active: false, activating: false});
            controller.network = data; controller.category = "network"; waitForRendering(view);
            mouseClick(findChild(view, "wifi-Wpa3"));
            let text = "";
            for (let i = 0; i < 128; i++) text += "é";
            const field = findChild(view, "psk-Wpa3");
            field.forceActiveFocus();
            field.text = text; field.textEdited();
            verify(findChild(view, "connect-Wpa3").enabled, "128 two-byte characters are exactly 256 bytes");
            field.text = text + "é"; field.textEdited();
            verify(!findChild(view, "connect-Wpa3").enabled, "257 bytes is over the SAE limit");
        }
        function test_network_password_clears_on_category_change() {
            openNetwork();
            mouseClick(findChild(view, "wifi-Neighbour"));
            const field = findChild(view, "psk-Neighbour");
            field.forceActiveFocus();
            for (const c of "secret123") keyClick(c);
            compare(field.text, "secret123");
            controller.select("appearance"); wait(20);
            openNetwork();
            mouseClick(findChild(view, "wifi-Neighbour"));
            const reopened = findChild(view, "psk-Neighbour");
            compare(reopened.text, "", "a typed password must not survive a category change");
        }
        function test_no_results_label_hidden_on_network_view() {
            openNetwork();
            const label = findChild(view, "noSettingsMatch");
            verify(label, "the empty-search label needs an objectName to be tested");
            verify(!label.visible, "the network view's only row is inView, but that must not show the empty-search label");
        }
        function test_no_results_label_shown_for_empty_search() {
            controller.query = "no-such-setting-exists"; wait(20);
            const label = findChild(view, "noSettingsMatch");
            verify(label.visible);
            controller.query = "";
        }
        function test_network_row_keyboard_enter_activates() {
            openNetwork();
            const row = findChild(view, "wifi-Cafe");
            row.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(controller.calls[controller.calls.length - 1], {op: "wifiConnect", ssid: "Cafe"});
        }
        function test_network_known_enterprise_is_activatable() {
            const fixture = networkFixture();
            fixture.wifi.networks = fixture.wifi.networks.map(n => n.ssid === "Office" ? Object.assign({}, n, {known: true}) : n);
            controller.network = fixture; controller.category = "network"; waitForRendering(view);
            verify(!findChild(view, "advanced-Office"), "a known unsupported network shows no Advanced button");
            mouseClick(findChild(view, "wifi-Office"));
            compare(controller.calls[controller.calls.length - 1], {op: "wifiConnect", ssid: "Office"});
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
