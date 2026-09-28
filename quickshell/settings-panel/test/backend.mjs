import assert from 'node:assert/strict'
import fs from 'node:fs'
import { registerHooks } from 'node:module'

const base = '/fixture/.config'
const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
catalog.rows.push({id:'test.gtk-raw',source:'gtk',key:'gtk-theme',ini:{key:'gtk-theme-name'}})
const files = new Map([
    [base + '/quickshell/settings-panel/catalog.json', JSON.stringify(catalog)],
    [base + '/hypr/config/overrides.lua', ''],
    [base + '/hypr/hypridle.conf', '# Keep this comment\ngeneral { ignore_dbus_inhibit = false }\nlistener {\n timeout = 305\n on-timeout = hyprlock\n}\nlistener {\n timeout = 600\n on-timeout = hyprctl dispatch \'hl.dsp.dpms({action = "off"})\'\n}\n'],
    [base + '/hypr/hyprsunset.conf', '# Keep this comment\nmax-gamma = 100\nprofile {\n time = 07:00\n temperature = 6000\n}\nprofile {\n time = 20:00\n temperature = 4000\n}\n'],
    [base + '/swaync/config.json', JSON.stringify({timeout:5,unrelated:{keep:true}})],
    [base + '/hypr/config/hardware/primary.conf', '$monitor =\n'],
    ['/usr/share/icons/Papirus-Dark/index.theme', '[Icon Theme]\nDirectories=16x16/apps\n'],
    ['/usr/share/icons/Bibata-Modern-Classic/index.theme', '[Icon Theme]\nName=Bibata\n'],
    ['/usr/share/themes/Kripton/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Adwaita/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/A$&B/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Bad\nTheme/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Emacs/gtk-3.0/gtk-keys.css', ''],
    [base + '/gtk-3.0/settings.ini', '[Settings]\ngtk-theme-name=Kripton\ngtk-font-name=Sans 11\n'],
    [base + '/gtk-4.0/settings.ini', '[Settings]\ngtk-theme-name=Kripton\n'],
    [base + '/Kvantum/Carl/Carl.kvconfig', ''],
    ['/usr/share/Kvantum/KvArc/KvArc.kvconfig', ''],
    [base + '/Kvantum/kvantum.kvconfig', '[General]\ntheme=Carl\n'],
    [base + '/mimeapps.list', '[Default Applications]\ninode/directory=kitty-open.desktop\n'],
])
const dirs = new Map([
    ['/usr/share/themes', ['Kripton','Adwaita','NoGtk','Emacs','A$&B','Bad\nTheme']],
    ['/usr/share/themes/Emacs/gtk-3.0', []],
    ['/usr/share/icons', ['Papirus-Dark','Bibata-Modern-Classic']],
    ['/usr/share/icons/Bibata-Modern-Classic/cursors', []],
    [base + '/Kvantum', ['Carl','kvantum.kvconfig']],
    ['/usr/share/Kvantum', ['KvArc']],
])
const gsettings = {'gtk-theme':"'Kripton'",'icon-theme':"'Papirus-Dark'",'color-scheme':"'prefer-dark'",'text-scaling-factor':'1.0','cursor-size':'24','cursor-theme':"'Bibata-Modern-Classic'"}
const appsForType = {
    'inode/directory': [['thunar.desktop','Thunar'],['org.gnome.Nautilus.desktop','Files']],
    'image/png': [['mpv.desktop','mpv'],['image-viewer.desktop','Image Viewer'],['hexed.desktop','Hex Editor']],
    'text/plain': [['nvim.desktop','Neovim']],
}
const supportedTypes = {
    'thunar.desktop':['inode/directory'],
    'mpv.desktop':['image/png','image/jpeg'],
    'image-viewer.desktop':['image/png'],
    'hexed.desktop':['image/png','application/octet-stream'],
    'nvim.desktop':['text/plain'],
}
const mimeDefaults = {'inode/directory':'kitty-open.desktop'}
let failMime = ''
for (const name of ['font','font-gtk','cursortheme','mainmonitor','browser','terminal','editor','codeeditor','filemanager','aurhelper','launchertype','autologin','protonvpn','randomwallpaper']) files.set(`${base}/options/${name}`,name === 'mainmonitor' ? '' : 'enabled\n')
let events = [], failingPath = '', failReload = false, failingGsettingsSets = 0, failNextSpawn = ''
// Shapes copied from `hyprctl getoption -j` on Hyprland 0.56: the value field
// is named after its type, and `set` is only whether the config assigns it.
const hyprOptions = {
    'decoration:blur:enabled': {bool:true,set:true},
    'decoration:shadow:enabled': {bool:false,set:true},
    'general:gaps_in': {css:'4 4 4 4',set:true},
    'input:accel_profile': {str:'[[EMPTY]]',set:false},
    'input:kb_layout': {str:'us',set:true},
    'input:kb_variant': {str:'intl',set:true},
}
// Trimmed from `pactl -f json` on PipeWire 1.6.9. Note `card` is null on the
// real sinks: the card is linked through properties["device.name"].
const pulse = {
    info: {default_sink_name:'alsa_output.analog', default_source_name:'alsa_input.analog'},
    sinks: [
        {name:'alsa_output.analog',description:'Built-in Audio Analog Stereo',card:null,active_port:'analog-output-headphones',properties:{'device.name':'alsa_card.analog'},
         ports:[{name:'analog-output-lineout',description:'Line Out',availability:'not available'},{name:'analog-output-headphones',description:'Headphones',availability:'available'}]},
        {name:'alsa_output.hdmi',description:'GA102 Digital Stereo (HDMI)',card:null,active_port:'hdmi-output-0',properties:{'device.name':'alsa_card.hdmi'},
         ports:[{name:'hdmi-output-0',description:'HDMI / DisplayPort',availability:'available'}]},
    ],
    sources: [
        {name:'alsa_output.analog.monitor',description:'Monitor of Built-in Audio Analog Stereo',monitor_source:'alsa_output.analog',active_port:'analog-output-headphones',ports:[],volume:{}},
        {name:'alsa_input.analog',description:'Built-in Audio Analog Stereo',monitor_source:'',active_port:'analog-input-front-mic',
         ports:[{name:'analog-input-front-mic',description:'Front Microphone',availability:'not available'},{name:'analog-input-rear-mic',description:'Rear Microphone',availability:'not available'}],
         volume:{'front-left':{value_percent:'60%'},'front-right':{value_percent:'64%'}}},
    ],
    cards: [
        {name:'alsa_card.analog',active_profile:'output:analog-stereo+input:analog-stereo',profiles:{
            off:{description:'Off',available:true},
            'output:analog-stereo+input:analog-stereo':{description:'Analog Stereo Duplex',available:true},
            'output:analog-surround-51':{description:'Analog Surround 5.1 Output',available:false},
            'output:iec958-stereo':{description:'Digital Stereo (IEC958) Output',available:true}}},
        {name:'alsa_card.hdmi',active_profile:'output:hdmi-stereo',profiles:{'output:hdmi-stereo':{description:'Digital Stereo (HDMI) Output',available:true}}},
    ],
}
const running = new Set()
const encoder = new TextEncoder()
globalThis.settingsMocks = {
    GLib: {
        get_home_dir: () => '/fixture', get_user_config_dir: () => base, Error: class extends Error {},
        find_program_in_path: name => name === 'missing-app' ? null : name,
        SpawnFlags: {SEARCH_PATH:1,STDOUT_TO_DEV_NULL:2,STDERR_TO_DEV_NULL:4},
        spawn_async: (...args) => {
            events.push(['spawn',args[1]])
            if (failNextSpawn && args[1][0] === failNextSpawn) { failNextSpawn = ''; return }
            running.add(args[1][0])
        },
        timeout_add: (_priority,_ms,fn) => { setImmediate(fn); },
    },
    Gio: {
        AppInfo: { get_all_for_type: type => (appsForType[type] || []).map(([id,name]) => ({get_id: () => id, get_name: () => name})) },
        content_type_is_a: (mime, parent) => mime === parent || (mime === 'text/markdown' && parent === 'text/plain') || (parent === 'application/octet-stream' && !mime.startsWith('inode/')),
        FileCreateFlags:{NONE:0},
        FileQueryInfoFlags:{NONE:0},
        File:{new_for_path: path => ({
            query_exists: () => files.has(path) || dirs.has(path),
            enumerate_children: () => {
                if (!dirs.has(path)) throw new Error('No such directory: '+path)
                const names = [...dirs.get(path)]
                return { next_file: () => names.length ? {get_name: (n => () => n)(names.shift())} : null, close: () => {} }
            },
            load_contents: () => {
                if (!files.has(path)) throw new Error('Missing fixture: '+path)
                return [true,encoder.encode(files.get(path))]
            },
            replace_contents: bytes => {
                events.push(['write',path])
                if (path === failingPath) throw new Error('disk full')
                files.set(path,new TextDecoder().decode(bytes))
                return [true,'etag']
            },
            delete: () => {
                events.push(['delete',path])
                files.delete(path)
                return true
            },
            make_directory_with_parents: () => {
                events.push(['mkdir',path])
                dirs.set(path,[])
                return true
            },
        })},
    },
    GioUnix: {
        DesktopAppInfo: { new: id => supportedTypes[id] ? {get_supported_types: () => supportedTypes[id]} : null },
    },
    execAsync: async args => {
        events.push(args)
        if (args[0] === 'xdg-mime' && args[1] === 'query') return (mimeDefaults[args[3]] || '') + '\n'
        if (args[0] === 'xdg-mime' && args[1] === 'default') {
            if (args[3] === failMime) throw new Error('xdg-mime failed')
            mimeDefaults[args[3]] = args[2]
            files.set(base+'/mimeapps.list',(files.get(base+'/mimeapps.list') || '[Default Applications]\n') + `${args[3]}=${args[2]}\n`)
            return ''
        }
        if (args[0] === 'fc-list') return 'FiraCode Nerd Font,FiraCode Nerd Font Med\nAdwaita Sans\n'
        if (args[0] === 'pkill') { running.delete(args[2]); return ''; }
        if (args[0] === 'pgrep') { if (!running.has(args[2])) throw new Error('not running'); return '123'; }
        if (args[1] === 'getoption') return JSON.stringify(hyprOptions[args[2]] ?? {int:1,set:true})
        if (args[1] === 'animations') return JSON.stringify([[{name:'windows',enabled:true,speed:6,bezier:'ease',style:'popin 80%'}],[]])
        if (args[1] === 'monitors') return JSON.stringify([{name:'DP-1',width:2560,height:1440}])
        if (args[1] === 'configerrors') return '[]'
        if (args[0] === 'swaync-client' && failReload) { failReload=false; throw new Error('reload failed') }
        if (args[0] === 'localectl') return {
            'list-x11-keymap-layouts': 'us\nit\nde\n',
            'list-x11-keymap-options': 'caps:escape\ngrp:alt_shift_toggle\n',
            'list-x11-keymap-variants': args[2] === 'us' ? 'intl\ncolemak\n' : 'nodeadkeys\n',
        }[args[1]]
        if (args[0] === 'gsettings' && args[1] === 'get') return gsettings[args[3]]
        if (args[0] === 'gsettings' && args[1] === 'set') {
            if (failingGsettingsSets > 0) { failingGsettingsSets--; throw new Error('gsettings set failed') }
            gsettings[args[3]] = args[4]; return ''
        }
        if (args[0] === 'powerprofilesctl') return args[1] === 'get' ? 'performance\n'
            : args[1] === 'list' ? '* performance:\n    CpuDriver:\tintel_pstate\n\n  balanced:\n    CpuDriver:\tintel_pstate\n\n  power-saver:\n    CpuDriver:\tintel_pstate\n' : ''
        if (args[0] === 'pactl' && args[1] === '-f') return JSON.stringify(args[3] === 'info' ? pulse.info : pulse[args[4]])
        if (args[0] === 'pactl') {
            if (args[1] === 'set-default-sink') pulse.info.default_sink_name = args[2]
            return ''
        }
        return 'ok'
    },
}
registerHooks({resolve(specifier,context,next) {
    const names = {'gi://GLib':'GLib','gi://Gio':'Gio','gi://GioUnix':'GioUnix'}
    if (names[specifier]) return {url:'data:text/javascript,'+encodeURIComponent(`export default globalThis.settingsMocks.${names[specifier]}`),shortCircuit:true}
    if (specifier === './process.js') return {url:'data:text/javascript,export const execAsync = globalThis.settingsMocks.execAsync',shortCircuit:true}
    return next(specifier,context)
}})
const {dispatch} = await import('../backend.js')
let result = await dispatch({op:'read',ids:['appearance.blur','power.lock','power.nightlight-temp','notif.timeout','apps.browser'],monitors:true})
assert.equal(result.values['appearance.blur'].value,true)
assert.equal(result.values['power.nightlight-temp'].value,4000)
assert.equal(result.monitors[0].name,'DP-1')
assert.equal(events.some(e => e[0] === 'write' || e[0] === 'spawn'),false)
console.log('ok: settings and monitor reads have no writes or daemon starts')

result = await dispatch({op:'read',ids:['appearance.shadows','appearance.gaps-in']})
assert.equal(result.values['appearance.shadows'].value,false)
assert.equal(result.values['appearance.gaps-in'].value,4)
console.log('ok: keyword reads use the typed value field, never `set`')

events=[]
for (const request of [
    {op:'set',id:'not-real',value:1},
    {op:'set',id:'appearance.blur-size',value:100},
    {op:'set',id:'power.lock',value:80.5},
    {op:'set',id:'appearance.blur',value:'true'},
    {op:'set',id:'win.layout',value:'$(touch /tmp/should-not-exist)'},
    {op:'set',id:'apps.browser',value:'line\nbreak'},
    {op:'reset',id:'apps.browser'},
    {op:'action',id:'../../anything'},
]) await assert.rejects(dispatch(request))
assert.equal(events.length,0)
console.log('ok: invalid settings, types, ranges, actions and resets are rejected before side effects')

const text = 'browser with "quotes"; $(touch /tmp/never) `false`'
await dispatch({op:'set',id:'apps.browser',value:text})
assert.equal(files.get(base+'/options/browser'),text+'\n')
assert.equal(events.some(e=>e[0]==='bash'),false)
console.log('ok: option text remains data, never shell code')

await dispatch({op:'set',id:'anim.windows',value:8})
assert.match(files.get(base+'/hypr/config/overrides.lua'),/speed = 8/)
assert.match(files.get(base+'/hypr/config/overrides.lua'),/bezier = "ease"/)
assert.match(files.get(base+'/hypr/config/overrides.lua'),/style = "popin 80%"/)
console.log('ok: animation speed edits preserve the live curve and style')

await dispatch({op:'set',id:'notif.timeout',value:8})
assert.deepEqual(JSON.parse(files.get(base+'/swaync/config.json')).unrelated,{keep:true})
const before = files.get(base+'/swaync/config.json')
failReload=true
await assert.rejects(dispatch({op:'set',id:'notif.timeout',value:10}),/Previous settings restored/)
assert.equal(files.get(base+'/swaync/config.json'),before)
console.log('ok: notification edits preserve unrelated configuration and roll back failed reloads')

failingPath=base+'/options/terminal'
await assert.rejects(dispatch({op:'set',id:'apps.terminal',value:'ghostty'}),/disk full/)
failingPath=''
await dispatch({op:'mainMonitor',value:'DP-1'})
assert.equal(files.get(base+'/options/mainmonitor'),'DP-1\n')
assert.equal(files.get(base+'/hypr/config/hardware/primary.conf'),'$monitor = DP-1\n')
failingPath=base+'/hypr/config/hardware/primary.conf'
await assert.rejects(dispatch({op:'mainMonitor',value:''}),/disk full/)
assert.equal(files.get(base+'/options/mainmonitor'),'DP-1\n')
console.log('ok: file failures propagate and partial main-monitor writes are restored')

const oldSunset = files.get(base+'/hypr/hyprsunset.conf')
failingPath=''
await dispatch({op:'set',id:'power.nightlight-start',value:1230})
assert.equal(files.get(base+'/hypr/hyprsunset.conf'),oldSunset.replace('20:00','20:30'))
await assert.rejects(dispatch({op:'set',id:'power.nightlight-start',value:420}),/different times/)
console.log('ok: night light edits preserve the rest of the file and reject conflicting schedule boundaries')
const oldIdle = files.get(base+'/hypr/hypridle.conf')
await dispatch({op:'set',id:'power.lock',value:330})
assert.equal(files.get(base+'/hypr/hypridle.conf'),oldIdle.replace('305','330'))
await dispatch({op:'set',id:'power.dpms',value:720})
assert.equal(files.get(base+'/hypr/hypridle.conf'),oldIdle.replace('305','330').replace('600','720'))
console.log('ok: idle timeout edits preserve custom content and Lua dispatcher arguments')

result = await dispatch({op:'read',ids:['power.profile','power.suspend']})
assert.equal(result.values['power.profile'].value,'performance')
assert.deepEqual(result.values['power.profile'].choices.map(c=>c.value),['performance','balanced','power-saver'])
assert.equal(result.values['power.suspend'].value,0)
await dispatch({op:'set',id:'power.profile',value:'balanced'})
assert.ok(events.some(e=>e[0]==='powerprofilesctl' && e[1]==='set' && e[2]==='balanced'))
const idleBefore = files.get(base+'/hypr/hypridle.conf')
const idleNoNewline = idleBefore.replace(/\n$/,'')
const suspendAt = seconds => `# Suspend after inactivity\nlistener {\n    timeout = ${seconds}\n    on-timeout = systemctl suspend\n}\n`

// The round trip (set N, retime, set 0) must restore the file byte-for-byte
// regardless of how many trailing newlines it had before the suspend block
// ever existed - a file ending in 0, 1 or 2+ newlines are three distinct cases.
for (const [label,original] of [['no trailing newline',idleNoNewline],['one trailing newline',idleBefore],['two trailing newlines',idleBefore+'\n']]) {
    files.set(base+'/hypr/hypridle.conf',original)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:1800})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`add restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`add spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original+'\n\n'+suspendAt(1800),`add is byte-exact (${label})`)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:3600})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`retime restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`retime spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original+'\n\n'+suspendAt(3600),`retime keeps everything else identical (${label})`)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:0})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`remove restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`remove spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original,`removal restores the file byte-for-byte (${label})`)
}
files.set(base+'/hypr/hypridle.conf',idleBefore)

files.set(base+'/hypr/hypridle.conf',idleBefore+'listener {\n timeout = 99\n on-timeout = systemctl suspend\n}\n')
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:0}),/by hand/)
const customIdle = files.get(base+'/hypr/hypridle.conf')
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:1800}),/by hand/)
assert.equal(files.get(base+'/hypr/hypridle.conf'),customIdle,'a custom suspend listener is never retimed')
files.set(base+'/hypr/hypridle.conf',idleBefore)
console.log('ok: power profile and suspend listener round-trip without touching custom content')

const idleForFailure = files.get(base+'/hypr/hypridle.conf')
failNextSpawn = 'hypridle'
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:1800}),/Previous settings restored/)
assert.equal(files.get(base+'/hypr/hypridle.conf'),idleForFailure)
assert.equal(failNextSpawn,'')
console.log('ok: a suspend change that fails to restart hypridle restores hypridle.conf exactly')

result = await dispatch({op:'read',ids:['input.accel-profile']})
assert.equal(result.values['input.accel-profile'].value,'')
console.log('ok: an empty string keyword value maps through the [[EMPTY]] sentinel')

events=[]
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'zz'}),/Unknown keyboard layout zz/)
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'de'}),/de has no variant intl/)
await assert.rejects(dispatch({op:'set',id:'input.kb-options',value:'caps:nope'}),/Unknown keyboard option/)
await assert.rejects(dispatch({op:'set',id:'apps.browser',value:''}),/nonempty/)
assert.equal(events.some(e => e[1] === 'eval'),false)
await dispatch({op:'set',id:'input.kb-variant',value:''})
await dispatch({op:'set',id:'input.kb-options',value:'caps:escape,grp:alt_shift_toggle'})
await dispatch({op:'set',id:'input.kb-layout',value:'us,it'})
assert.match(files.get(base+'/hypr/config/overrides.lua'),/kb_variant = ""/)
assert.match(files.get(base+'/hypr/config/overrides.lua'),/kb_layout = "us,it"/)
console.log('ok: keyboard layout, variant and options are checked against XKB before applying')

await dispatch({op:'set',id:'input.kb-variant',value:'intl'})
events=[]
await assert.rejects(dispatch({op:'reset',id:'input.kb-layout'}),/Reset Layout Variant first/)
assert.equal(events.some(e => e[1] === 'reload'),false)
assert.match(files.get(base+'/hypr/config/overrides.lua'),/kb_layout = "us,it"/)
await dispatch({op:'reset',id:'input.kb-variant'})
await dispatch({op:'reset',id:'input.kb-layout'})
assert.doesNotMatch(files.get(base+'/hypr/config/overrides.lua'),/@override input:kb_layout /)
console.log('ok: resetting the keyboard layout while a variant override exists is rejected until the variant is reset first')

result = await dispatch({op:'read',ids:['appearance.gtk-theme','appearance.icon-theme']})
assert.deepEqual(result.values['appearance.gtk-theme'].choices.map(c=>c.value),['A$&B','Adwaita','HighContrast','HighContrastInverse','Kripton'])
assert.deepEqual(result.values['appearance.icon-theme'].choices.map(c=>c.value),['Papirus-Dark'])
assert.equal(result.values['appearance.gtk-theme'].value,'Kripton')
assert.equal(result.values['appearance.gtk-theme'].choices.some(c=>c.value==='Emacs'),false)
assert.equal(result.values['appearance.gtk-theme'].choices.some(c=>c.value==='Bad\nTheme'),false)
const systemThemes = dirs.get('/usr/share/themes')
dirs.set('/usr/share/themes',[])
result = await dispatch({op:'read',ids:['appearance.gtk-theme']})
assert.deepEqual(result.values['appearance.gtk-theme'].choices.map(c=>c.value),['Adwaita','HighContrast','HighContrastInverse'])
dirs.set('/usr/share/themes',systemThemes)
events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'NoGtk'}),/Unknown choice/)
assert.equal(events.some(e=>e[0]==='gsettings'),false)
await dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'})
assert.equal(gsettings['gtk-theme'],"'Adwaita'")
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\ngtk-font-name=Sans 11\n')
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\n')
files.set(base+'/gtk-3.0/settings.ini','[Settings]')
files.set(base+'/gtk-4.0/settings.ini','[Settings]\r\ngtk-font-name=Sans 11\r\n')
await dispatch({op:'set',id:'appearance.gtk-theme',value:'A$&B'})
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),'[Settings]\ngtk-theme-name=A$&B\n')
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),'[Settings]\r\ngtk-theme-name=A$&B\r\ngtk-font-name=Sans 11\r\n')
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Bad\nTheme'}),/Unknown choice/)
events=[]
await assert.rejects(dispatch({op:'set',id:'test.gtk-raw',value:'Bad\nTheme'}),/multiline/)
assert.equal(events.some(e=>e[0]==='write' || e[0]==='gsettings'),false)

const gtk3BeforeFailure = files.get(base+'/gtk-3.0/settings.ini')
const gtk4BeforeFailure = files.get(base+'/gtk-4.0/settings.ini')
events=[]
failingGsettingsSets=1
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'}),/gsettings set failed\. Previous settings restored\./)
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),gtk3BeforeFailure)
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),gtk4BeforeFailure)
assert.deepEqual(events.filter(e=>e[0]==='gsettings' && e[1]==='set').at(-1),['gsettings','set','org.gnome.desktop.interface','gtk-theme',"'A$&B'"])
failingGsettingsSets=2
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'}),/gsettings set failed\. Restoring the previous gsettings value also failed: gsettings set failed/)
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),gtk3BeforeFailure)
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),gtk4BeforeFailure)

events=[]
await dispatch({op:'set',id:'appearance.color-scheme',value:'prefer-dark'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-application-prefer-dark-theme=true$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-application-prefer-dark-theme=true$/m)
assert.deepEqual(events.find(e=>e[0]==='gsettings' && e[1]==='set'),['gsettings','set','org.gnome.desktop.interface','color-scheme',"'prefer-dark'"])
await dispatch({op:'set',id:'appearance.color-scheme',value:'prefer-light'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-application-prefer-dark-theme=false$/m)
console.log('ok: GTK appearance filters themes, preserves literal INI values and line endings, and rolls back failures')

result = await dispatch({op:'read',ids:['appearance.kvantum']})
assert.equal(result.values['appearance.kvantum'].value,'Carl')
assert.deepEqual(result.values['appearance.kvantum'].choices.map(c=>c.value),['Carl','KvArc'])
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=KvArc\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[Other]\ntheme=Wrong\n[General]\ntheme=Carl\n')
result = await dispatch({op:'read',ids:['appearance.kvantum']})
assert.equal(result.values['appearance.kvantum'].value,'Carl')
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[Other]\ntheme=Wrong\n[General]\ntheme=KvArc\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[General]\r\nkeep=true\r\n')
await dispatch({op:'set',id:'appearance.kvantum',value:'Carl'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\r\ntheme=Carl\r\nkeep=true\r\n')
files.delete(base+'/Kvantum/kvantum.kvconfig')
await dispatch({op:'set',id:'appearance.kvantum',value:'Carl'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=Carl\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[Other]\ntheme=Carl\n')
await assert.rejects(dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'}),/has no \[General\] section/)
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[Other]\ntheme=Carl\n')
files.delete(base+'/Kvantum/kvantum.kvconfig')
dirs.delete(base+'/Kvantum')
events=[]
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(dirs.has(base+'/Kvantum'),true)
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=KvArc\n')
assert.deepEqual(events.filter(e=>e[0]==='mkdir'),[['mkdir',base+'/Kvantum']])
console.log('ok: Kvantum theme is chosen from installed themes')

events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.font',value:'No Such Font'}),/No installed font/)
assert.equal(events.some(e=>e[0]==='bash'),false)
await dispatch({op:'set',id:'appearance.font',value:'FiraCode Nerd Font Med'})
await dispatch({op:'set',id:'appearance.cursor-theme',value:'Bibata-Modern-Classic'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-cursor-theme-name=Bibata-Modern-Classic$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-cursor-theme-size=24$/m)
console.log('ok: fonts must be installed and the cursor theme reaches settings.ini')

events=[]
await assert.rejects(dispatch({op:'set',id:'apps.filemanager',value:'missing-app --flag'}),/missing-app is not installed/)
assert.equal(events.length,0)
await dispatch({op:'set',id:'apps.filemanager',value:'nautilus'})
assert.equal(files.get(base+'/options/filemanager'),'nautilus\n')
assert.ok(events.some(e=>e[1]==='reload'))
console.log('ok: app rows must name an installed command and reload Hyprland')

events=[]
result = await dispatch({op:'read',ids:['mime.folders','mime.images']})
assert.equal(result.values['mime.folders'].value,'kitty-open.desktop')
assert.deepEqual(result.values['mime.folders'].choices.map(c=>c.value),['thunar.desktop','org.gnome.Nautilus.desktop','kitty-open.desktop'])
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='query').map(e=>e[3]).sort(),['image/png','inode/directory'])
await assert.rejects(dispatch({op:'set',id:'mime.folders',value:'evil.desktop'}),/Unknown choice/)
await dispatch({op:'set',id:'mime.folders',value:'thunar.desktop'})
assert.equal(mimeDefaults['inode/directory'],'thunar.desktop')
for (const mime of catalog.rows.find(row=>row.id==='mime.images').mimes) mimeDefaults[mime]='old.desktop'
events=[]
await dispatch({op:'set',id:'mime.images',value:'mpv.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png','image/jpeg'])
assert.equal(mimeDefaults['image/gif'],'old.desktop')
events=[]
await dispatch({op:'set',id:'mime.text',value:'nvim.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['text/plain','text/markdown'])
events=[]
await dispatch({op:'set',id:'mime.images',value:'image-viewer.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
events=[]
await dispatch({op:'set',id:'mime.images',value:'hexed.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
const exactMimeapps = '[Default Applications]\r\nimage/png=old.desktop\r\n# image/jpeg deliberately has no explicit default\r\n'
files.set(base+'/mimeapps.list',exactMimeapps)
mimeDefaults['image/png']='old.desktop'; mimeDefaults['image/jpeg']='inferred.desktop'
failMime='image/jpeg'
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed/)
assert.equal(files.get(base+'/mimeapps.list'),exactMimeapps)
failingPath=base+'/mimeapps.list'
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed\. Restoring mimeapps\.list also failed: disk full/)
failingPath=''
files.delete(base+'/mimeapps.list')
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed/)
assert.equal(files.has(base+'/mimeapps.list'),false)
failMime=''
mimeDefaults['image/png']='legacy.desktop'
events=[]
await dispatch({op:'set',id:'mime.images',value:'legacy.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
console.log('ok: file types query once, update declared MIME subclasses only, and restore mimeapps.list exactly')

events=[]
result = await dispatch({op:'read',ids:catalog.rows.filter(r=>r.source==='pulse').map(r=>r.id)})
assert.equal(events.filter(e=>e[0]==='pactl').length,4)
const sound = id => result.values['sound.'+id]
assert.equal(sound('output').value,'alsa_output.analog')
assert.deepEqual(sound('output').choices.map(c=>c.value),['alsa_output.analog','alsa_output.hdmi'])
assert.deepEqual(sound('output-port').choices.map(c=>c.label),['Headphones'])
assert.deepEqual(sound('output-profile').choices.map(c=>c.value),['output:analog-stereo+input:analog-stereo','output:iec958-stereo'])
assert.deepEqual(sound('input').choices.map(c=>c.value),['alsa_input.analog'])
assert.deepEqual(sound('input-port').choices.map(c=>c.value),['analog-input-front-mic'])
assert.equal(sound('mic-level').value,62)
events=[]
await assert.rejects(dispatch({op:'set',id:'sound.output-port',value:'analog-output-lineout'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.output-profile',value:'off'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.input',value:'alsa_output.analog.monitor'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.mic-level',value:150}),/outside/)
await assert.rejects(dispatch({op:'reset',id:'sound.output'}),/no reset/)
assert.equal(events.some(e=>e[0]==='pactl' && e[1].startsWith('set-')),false)
await dispatch({op:'set',id:'sound.output-profile',value:'output:iec958-stereo'})
await dispatch({op:'set',id:'sound.mic-level',value:40})
await dispatch({op:'set',id:'sound.output',value:'alsa_output.hdmi'})
assert.deepEqual(events.filter(e=>e[0]==='pactl' && e[1].startsWith('set-')).map(e=>e.slice(1)),[
    ['set-card-profile','alsa_card.analog','output:iec958-stereo'],
    ['set-source-volume','alsa_input.analog','40%'],
    ['set-default-sink','alsa_output.hdmi'],
])
result = await dispatch({op:'read',ids:['sound.output-port','sound.output-profile']})
assert.equal(result.values['sound.output-port'].value,'hdmi-output-0')
assert.equal(result.values['sound.output-profile'].value,'output:hdmi-stereo')
pulse.info.default_sink_name = 'alsa_output.analog'
const savedSource = pulse.info.default_source_name
pulse.info.default_source_name = ''
result = await dispatch({op:'read',ids:['sound.input','sound.mic-level','sound.output']})
assert.match(result.values['sound.input'].error,/No input device/)
assert.match(result.values['sound.mic-level'].error,/No input device/)
assert.equal(result.values['sound.output'].value,'alsa_output.analog')
pulse.info.default_source_name = savedSource
console.log('ok: sound rows share four pactl reads, offer only usable choices and follow the default device')
