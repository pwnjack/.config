import assert from 'node:assert/strict'
import * as displays from '../displays.mjs'

const pg279q = {name:'DP-1',width:2560,height:1440,availableModes:['2560x1440@59.95Hz','2560x1440@144.00Hz','1024x768@60.00Hz']}
assert.deepEqual(displays.modeChoices(pg279q).map(c=>c.value),['highres@highrr','2560x1440@59.95','2560x1440@144.00','1024x768@60.00'])
assert.equal(displays.modeChoices(pg279q)[2].label,'2560 × 1440 · 144 Hz')
assert.deepEqual(displays.modeChoices({availableModes:[]}).map(c=>c.value),['highres@highrr'])
assert.deepEqual(displays.modeSize('highres@highrr',pg279q),[2560,1440])
assert.deepEqual(displays.modeSize('1024x768@60.00',pg279q),[1024,768])
console.log('ok: modes list Automatic first and drop the Hz suffix')

assert.deepEqual(displays.scaleChoices(2560,1440).map(c=>c.label),['100 %','107 %','125 %','133 %','160 %','167 %','200 %','213 %','250 %','267 %'])
assert.equal(displays.scaleChoices(2560,1440).some(c=>c.value===1.5),false)
assert.equal(displays.scaleChoices(2560,1440)[3].value,160/120)
for (const choice of displays.scaleChoices(1024,768)) {
    const step = Math.round(choice.value * 120)
    assert.equal((1024 * 120) % step,0); assert.equal((768 * 120) % step,0)
}
console.log('ok: scales are 1/120 steps with a whole logical size')

const line = displays.monitorLine('DP-1',{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0})
assert.equal(line,'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto-left", scale = 1.25, transform = 0 })')
const off = displays.monitorLine('HDMI-A-1',{disabled:true})
assert.equal(off,'hl.monitor({ output = "HDMI-A-1", disabled = true })')
assert.throws(()=>displays.monitorLine('DP-1", disabled = true }) os.execute("x',{disabled:true}),/Invalid display value/)
assert.throws(()=>displays.monitorLine('DP-1',{mode:'a b',position:'auto',scale:1,transform:0}),/Invalid display value/)
console.log('ok: monitor lines have one exact format and never carry injected Lua')

const both = displays.stateFileWith(displays.stateFileWith('','DP-1',line),'HDMI-A-1',off)
assert.ok(both.startsWith(displays.STATE_HEADER))
assert.deepEqual(displays.parseStateFile(both).outputs,{'DP-1':{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0},'HDMI-A-1':{disabled:true}})
const third = displays.monitorLine('DP-3',{mode:'highres@highrr',position:'auto',scale:160/120,transform:1})
assert.equal(displays.parseStateFile(displays.stateFileWith(both,'DP-3',third)).outputs['DP-3'].scale,160/120)
assert.equal(displays.stateFileWith(displays.stateFileWith(both,'DP-3',third),'DP-3',null),both)
const replaced = displays.stateFileWith(both,'DP-1',displays.monitorLine('DP-1',displays.AUTOMATIC))
assert.equal(replaced.split('\n').filter(l=>l.includes('"DP-1"')).length,1)
assert.equal(displays.stateFileWith(both,'DP-9',null),both)
const hand = displays.STATE_HEADER+'hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1, bitdepth = 10 })\n'
assert.deepEqual([...displays.parseStateFile(hand).handEdited],['DP-1'])
assert.deepEqual(displays.parseStateFile(hand).outputs,{})
assert.deepEqual([...displays.parseStateFile(displays.STATE_HEADER+'hl.monitor({ output = "", mode = "preferred" })\n').handEdited],['*'])
const malformed = displays.STATE_HEADER+'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1..2, transform = 0 })\n'
assert.deepEqual([...displays.parseStateFile(malformed).handEdited],['DP-1'])
const unterminated = '-- hand comment'
assert.equal(displays.stateFileWith(unterminated,'DP-1',line),'-- hand comment\n'+line+'\n')
console.log('ok: the state file keeps one line per output, round-trips exactly and reports hand edits')
assert.deepEqual(displays.modeChoices({availableModes:['2560x1440@144.00Hz','weird-mode']}).map(c=>c.value),['highres@highrr','2560x1440@144.00'])
console.log('ok: unparseable modes are skipped, never fatal')
const twice = displays.stateFileWith('','DP-1',line) + line + '\n'
assert.deepEqual([...displays.parseStateFile(twice).handEdited],['DP-1'])
console.log('ok: two panel lines for one output count as a hand edit')
