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
])
const dirs = new Map([
    ['/usr/share/themes', ['Kripton','Adwaita','NoGtk','Emacs','A$&B','Bad\nTheme']],
    ['/usr/share/themes/Emacs/gtk-3.0', []],
    ['/usr/share/icons', ['Papirus-Dark','Bibata-Modern-Classic']],
    ['/usr/share/icons/Bibata-Modern-Classic/cursors', []],
])
const gsettings = {'gtk-theme':"'Kripton'",'icon-theme':"'Papirus-Dark'",'color-scheme':"'prefer-dark'",'text-scaling-factor':'1.0','cursor-size':'24','cursor-theme':"'Bibata-Modern-Classic'"}
for (const name of ['font','font-gtk','cursortheme','mainmonitor','browser','terminal','editor','codeeditor','launchertype','autologin','protonvpn','randomwallpaper']) files.set(`${base}/options/${name}`,name === 'mainmonitor' ? '' : 'enabled\n')
let events = [], failingPath = '', failReload = false, failingGsettingsSets = 0
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
const running = new Set()
const encoder = new TextEncoder()
globalThis.settingsMocks = {
    GLib: {
        get_home_dir: () => '/fixture', Error: class extends Error {},
        find_program_in_path: name => name,
        SpawnFlags: {SEARCH_PATH:1,STDOUT_TO_DEV_NULL:2,STDERR_TO_DEV_NULL:4},
        spawn_async: (...args) => { events.push(['spawn',args[1]]); running.add(args[1][0]); },
        timeout_add: (_priority,_ms,fn) => { setImmediate(fn); },
    },
    Gio: {
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
        })},
    },
    execAsync: async args => {
        events.push(args)
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
        return 'ok'
    },
}
registerHooks({resolve(specifier,context,next) {
    const names = {'gi://GLib':'GLib','gi://Gio':'Gio'}
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

events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.font',value:'No Such Font'}),/No installed font/)
assert.equal(events.some(e=>e[0]==='bash'),false)
await dispatch({op:'set',id:'appearance.font',value:'FiraCode Nerd Font Med'})
await dispatch({op:'set',id:'appearance.cursor-theme',value:'Bibata-Modern-Classic'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-cursor-theme-name=Bibata-Modern-Classic$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-cursor-theme-size=24$/m)
console.log('ok: fonts must be installed and the cursor theme reaches settings.ini')
