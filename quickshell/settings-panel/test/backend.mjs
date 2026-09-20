import assert from 'node:assert/strict'
import fs from 'node:fs'
import { registerHooks } from 'node:module'

const base = '/fixture/.config'
const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
const files = new Map([
    [base + '/quickshell/settings-panel/catalog.json', JSON.stringify(catalog)],
    [base + '/hypr/config/overrides.lua', ''],
    [base + '/hypr/hypridle.conf', '# Keep this comment\ngeneral { ignore_dbus_inhibit = false }\nlistener {\n timeout = 305\n on-timeout = hyprlock\n}\nlistener {\n timeout = 600\n on-timeout = hyprctl dispatch \'hl.dsp.dpms({action = "off"})\'\n}\n'],
    [base + '/hypr/hyprsunset.conf', '# Keep this comment\nmax-gamma = 100\nprofile {\n time = 07:00\n temperature = 6000\n}\nprofile {\n time = 20:00\n temperature = 4000\n}\n'],
    [base + '/swaync/config.json', JSON.stringify({timeout:5,unrelated:{keep:true}})],
    [base + '/hypr/config/hardware/primary.conf', '$monitor =\n'],
])
for (const name of ['font','font-gtk','cursortheme','mainmonitor','browser','terminal','editor','launchertype','autologin','protonvpn','randomwallpaper']) files.set(`${base}/options/${name}`,name === 'mainmonitor' ? '' : 'enabled\n')
let events = [], failingPath = '', failReload = false
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
        File:{new_for_path: path => ({
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
        if (args[0] === 'pkill') { running.delete(args[2]); return ''; }
        if (args[0] === 'pgrep') { if (!running.has(args[2])) throw new Error('not running'); return '123'; }
        if (args[1] === 'getoption') return JSON.stringify({int:1})
        if (args[1] === 'animations') return JSON.stringify([[{name:'windows',enabled:true,speed:6,bezier:'ease',style:'popin 80%'}],[]])
        if (args[1] === 'monitors') return JSON.stringify([{name:'DP-1',width:2560,height:1440}])
        if (args[1] === 'configerrors') return '[]'
        if (args[0] === 'swaync-client' && failReload) { failReload=false; throw new Error('reload failed') }
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
