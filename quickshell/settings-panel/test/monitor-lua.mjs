// Runs the tracked hypr/config/hardware/monitor.lua under a stub `hl` against
// state files built by displays.mjs, so the panel's parser and Hyprland's
// loader are checked on the same bytes.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import * as displays from '../displays.mjs'

// Found by looking on PATH, not by spawning a shell: a spawn failure must
// fail the test, never pass for "no Lua here".
const lua = ['lua5.5', 'lua5.4', 'lua'].flatMap(name => (process.env.PATH || '').split(':').map(dir => path.join(dir, name)))
    .find(file => { try { fs.accessSync(file, fs.constants.X_OK); return true } catch (_) { return false } })
if (!lua) { console.log('skip: no Lua interpreter for the monitor.lua loader test'); process.exit(0) }
const loader = new URL('../../../hypr/config/hardware/monitor.lua', import.meta.url).pathname
const state = fs.mkdtempSync(path.join(os.tmpdir(), 'monitor-lua-'))
fs.mkdirSync(path.join(state, 'hypr'))
const harness = `
local applied, notices = {}, {}
hl = { monitor = function(spec) applied[#applied + 1] = spec.output .. ":" .. tostring(spec.mode or spec.disabled) end,
       exec_cmd = function(cmd) notices[#notices + 1] = cmd end }
print = function() end
dofile(${JSON.stringify(loader)})
io.write(table.concat(applied, ","), "|", #notices)
`
function load(text) {
    const file = path.join(state, 'hypr', 'monitors.lua')
    if (text === null) fs.rmSync(file, { force: true }); else fs.writeFileSync(file, text)
    return execFileSync(lua, ['-e', harness], { env: { ...process.env, XDG_STATE_HOME: state } }).toString()
}
const dp1 = displays.monitorLine('DP-1', { mode: '2560x1440@120.00', position: 'auto-left', scale: 160 / 120, transform: 1 })
const off = displays.monitorLine('HDMI-A-1', { disabled: true })
const written = displays.stateFileWith(displays.stateFileWith('', 'DP-1', dp1), 'HDMI-A-1', off)
assert.equal(load(null), ':highres@highrr|0', 'no file: only the catch-all, silently')
assert.equal(load(written), ':highres@highrr,DP-1:2560x1440@120.00,HDMI-A-1:true|0', 'a panel-written file applies every rule')
const hand = written + 'hl.monitor({ output = "DP-2", mode = "preferred", vrr = 1, bitdepth = 10, reserved = { 0, 0, 30, 0 } })\n'
assert.deepEqual([...displays.parseStateFile(hand).handEdited], ['DP-2'])
assert.equal(load(hand), ':highres@highrr,DP-1:2560x1440@120.00,HDMI-A-1:true,DP-2:preferred|0', 'a hand-edited rule with other Hyprland keys still applies, and so do the panel rules')
assert.equal(load(written + 'error("broken")\n'), ':highres@highrr|1', 'a runtime error applies nothing and notifies')
assert.equal(load('hl.monitor({ output = '), ':highres@highrr|1', 'a syntax error applies nothing and notifies')
assert.equal(load(written + 'hl.monitor({ output = "DP-2", mode = function() end })\n'), ':highres@highrr|1', 'a non-plain value applies nothing')
assert.equal(load(written + 'os.execute("true")\n'), ':highres@highrr|1', 'os is not reachable')
assert.equal(load(written + 'hl.monitor(nil)\n'), ':highres@highrr|1', 'a nil rule is not skipped silently')
assert.equal(load(written + 'hl.monitor({ output = "DP-2", reserved = { [function() end] = 1 } })\n'), ':highres@highrr|1', 'nested tables may only hold numbers under number keys')
fs.rmSync(state, { recursive: true, force: true })
console.log('ok: monitor.lua loads exactly what displays.mjs writes, and fails closed')
