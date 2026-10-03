import assert from 'node:assert/strict'
import * as sheet from '../sheet.mjs'

const sections = [
    {name: 'Applications', rows: [
        {keys: ['Super', 'Enter'], label: 'Terminal (ghostty)'},
        {keys: ['Super', 'S'], label: 'Screenshot a region'},
        {keys: ['Super', 'Alt', 'S'], label: 'Screenshot a region and annotate'}]},
    {name: 'Window Management', rows: [
        {keys: ['Super', 'Shift', 'Q'], label: 'Exit Hyprland'},
        {keys: ['Super', 'F'], label: 'Toggle fullscreen'}]},
    {name: 'Media Keys', rows: [{keys: ['Volume Up'], label: 'Volume up'}]},
]

// Blank queries change nothing.
assert.equal(sheet.filterSheet(sections, ''), sections)
assert.equal(sheet.filterSheet(sections, '   '), sections)

// Words AND together, across label and key text, case-insensitively.
const names = (s) => s.map(x => [x.name, x.rows.map(r => r.label)])
assert.deepEqual(names(sheet.filterSheet(sections, 'SCREEN')), [
    ['Applications', ['Screenshot a region', 'Screenshot a region and annotate']],
    ['Window Management', ['Toggle fullscreen']]])
assert.deepEqual(names(sheet.filterSheet(sections, 'shift q')), [['Window Management', ['Exit Hyprland']]])
assert.deepEqual(names(sheet.filterSheet(sections, 'alt')), [['Applications', ['Screenshot a region and annotate']]])
assert.deepEqual(sheet.filterSheet(sections, 'nothing-matches'), [])
// A word may not straddle the label and the keys.
assert.deepEqual(sheet.filterSheet(sections, ')super'), [])

assert.equal(sheet.countRows(sections), 6)
assert.equal(sheet.keyText(sections[1].rows[0]), 'Super + Shift + Q')

// Ranges merge overlapping and touching matches, and follow case folding.
assert.deepEqual(sheet.matchRanges('Screenshot a region', 'scr reen'), [[0, 6]])
assert.deepEqual(sheet.matchRanges('Toggle fullscreen', 'L'), [[4, 5], [9, 11]])
assert.deepEqual(sheet.matchRanges('abc', ''), [])

assert.equal(sheet.highlight('Fish & <chips>', 'chips', '#6097a1'),
    'Fish &amp; &lt;<font color="#6097a1"><b>chips</b></font>&gt;')
assert.equal(sheet.highlight('Plain', '', '#fff'), 'Plain')

assert.equal(sheet.capMatches('Shift', 'shift q'), true)
assert.equal(sheet.capMatches('Super', 'shift q'), false)
assert.equal(sheet.capMatches('Super', ''), false)

assert.equal(sheet.columnCount(600), 2)
assert.equal(sheet.columnCount(1080), 3)
assert.equal(sheet.columnCount(1512), 4)
assert.equal(sheet.columnCount(5000), 4)
assert.equal(sheet.columnCount(1512, 518), 2, 'a scaled minimum width earns fewer columns')
assert.equal(sheet.columnCount(2472, 518), 4)

const block = (name, n) => ({name, rows: Array.from({length: n}, (_, i) => ({keys: ['K'], label: name + i}))})
const four = [block('a', 10), block('b', 10), block('c', 10), block('d', 10)]
assert.deepEqual(sheet.distribute(four, 4).map(c => c.map(s => s.name)), [['a'], ['b'], ['c'], ['d']])
const uneven = [block('a', 2), block('b', 2), block('c', 12), block('d', 2), block('e', 2)]
const cols = sheet.distribute(uneven, 3)
assert.ok(cols.length <= 3)
assert.deepEqual(cols.flat().map(s => s.name), ['a', 'b', 'c', 'd', 'e'], 'reading order is kept')
assert.deepEqual(cols.map(c => c.map(s => s.name)), [['a', 'b'], ['c'], ['d', 'e']])
assert.deepEqual(sheet.distribute([], 4), [])
assert.deepEqual(sheet.distribute([block('a', 3)], 4).map(c => c.map(s => s.name)), [['a']])

assert.ok(sheet.contrast('#000000', '#ffffff') > 20)
assert.equal(sheet.readableAccent('#6097a1', '#05090c', '#cfddde'), '#6097a1')
assert.equal(sheet.readableAccent('#0a1014', '#05090c', '#cfddde'), '#cfddde')
// QML hands colours over as #aarrggbb when they carry alpha.
assert.equal(sheet.readableAccent('#ff6097a1', '#ff05090c', '#cfddde'), '#ff6097a1')

console.log('sheet.mjs: ok')
