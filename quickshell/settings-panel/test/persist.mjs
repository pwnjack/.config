// Run the actual persistence layer with mocked GIO and Hyprland transports.
import assert from 'node:assert/strict'
import { registerHooks } from 'node:module'

let saved = ''
let failWrite = false
let reply = 'ok'
let configErrors = []
let release = null
let held = false
const events = []
const encoder = new TextEncoder()
globalThis.panelMocks = {
    GLib: { get_home_dir: () => '/fixture', Error: class extends Error {} },
    Gio: {
        FileCreateFlags: { NONE: 0 },
        File: { new_for_path: () => ({
            load_contents: () => [true, encoder.encode(saved)],
            replace_contents: bytes => {
                events.push('save')
                if (failWrite) throw new Error('disk full')
                saved = new TextDecoder().decode(bytes)
                return [true, 'etag']
            },
        }) },
    },
    execAsync: async args => {
        events.push(args[1])
        if (args[1] === 'configerrors') return JSON.stringify(configErrors)
        if (args[1] === 'eval' && held) {
            held = false
            await new Promise(resolve => { release = resolve })
        }
        return reply
    },
}
registerHooks({
    resolve(specifier, context, next) {
        const names = { 'gi://GLib': 'GLib', 'gi://Gio': 'Gio' }
        if (names[specifier]) return {
            url: 'data:text/javascript,' + encodeURIComponent(`export default globalThis.panelMocks.${names[specifier]}`), shortCircuit: true,
        }
        if (specifier === './process.js') return {
            url: 'data:text/javascript,export const execAsync = globalThis.panelMocks.execAsync', shortCircuit: true,
        }
        return next(specifier, context)
    },
})
const p = await import('../persist.js')
const h = await import('../hyprctl.js')
const tick = () => new Promise(resolve => setImmediate(resolve))

held = true
const first = p.setPersistent('general:gaps_in', 8)
await tick()
assert.equal(saved, '', 'must wait for Hyprland before saving')
const second = p.setPersistent('general:gaps_out', 15)
await tick()
assert.deepEqual(events, ['eval'], 'second edit must wait for the first transaction')
release()
await Promise.all([first, second])
assert.deepEqual(events, ['eval', 'save', 'eval', 'save'])
assert.equal(p.getOverride('general:gaps_in'), '8')
assert.equal(p.getOverride('general:gaps_out'), '15')
console.log('ok: edits await confirmation and serialize without losing other settings')

const before = saved
reply = 'Lua error: invalid value'
await assert.rejects(p.setPersistent('general:gaps_in', 99), /could not be applied/)
assert.equal(saved, before)
reply = 'ok'
console.log('ok: an error in stdout is rejected even with a successful process exit')

failWrite = true
events.length = 0
await assert.rejects(p.setPersistent('general:gaps_in', 9), /saved settings have been restored/)
assert.equal(saved, before)
assert.deepEqual(events, ['eval', 'save', 'reload', 'configerrors'])
failWrite = false
await p.setPersistent('general:gaps_in', 10)
assert.equal(p.getOverride('general:gaps_in'), '10')
console.log('ok: save failure reloads saved settings and does not poison later edits')

await p.setAnimationPersistent('windowsIn', 'windowsIn,1,5,default')
await p.setAnimationPersistent('windows', 'windows,1,6,default')
assert.equal(p.hasAnimationOverride('windowsIn'), true)
await p.setAnimationPersistent('windows', 'windows,1,7,default')
assert.equal(p.hasAnimationOverride('windowsIn'), true)
await p.resetAnimation('windows')
assert.equal(p.hasAnimationOverride('windows'), false)
assert.equal(p.hasAnimationOverride('windowsIn'), true)
console.log('ok: animation updates and resets preserve similarly named animations')

configErrors = ['broken config']
await assert.rejects(h.reloadConfig(), /configuration errors/)
console.log('ok: reload checks configuration errors')
configErrors = ['']
await h.reloadConfig()
console.log('ok: the live compositor’s empty-string config error entry is accepted')
configErrors = []
events.length = 0
await p.resetSetting('general:gaps_in')
assert.equal(p.getOverride('general:gaps_in'), null)
assert.equal(p.getOverride('general:gaps_out'), '15')
assert.deepEqual(events, ['save', 'reload', 'configerrors'])
assert.equal('DEFAULTS' in p, false)
console.log('ok: reset reloads actual Lua defaults and preserves unrelated overrides')

const beforeReset = saved
let reloads = 0
// The imported mock closes over the original transport, so inject a one-shot
// config error via the reply value and release it after the first reload.
Object.defineProperty(configErrors, 'toJSON', { value: () => ++reloads === 1 ? ['invalid config'] : [] })
await assert.rejects(p.resetSetting('general:gaps_out'), /previous settings have been restored/)
assert.equal(saved, beforeReset)
console.log('ok: failed reset restores the previous file and retries its configuration')
