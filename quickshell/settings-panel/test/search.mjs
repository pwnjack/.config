import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

// The QML tests stub visibleRows with their own filter, so the real binding in
// shell.qml is evaluated here, against the real catalog.
const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
const source = fs.readFileSync(new URL('../shell.qml', import.meta.url), 'utf8')
const start = 'readonly property var visibleRows: {'
const body = source.slice(source.indexOf(start) + start.length, source.indexOf('\n    function refresh()'))
const visible = (query, category = 'appearance') =>
    vm.runInNewContext('(function () {' + body.slice(0, body.lastIndexOf('}')) + '})()', {catalog, query, category}).map(row => row.id)

// A page lists its own rows, minus those its view draws itself.
assert.equal(visible('').length, catalog.rows.filter(row => row.category === 'appearance').length)
assert.deepEqual(visible('', 'network'), [])
// Search matches section titles, and the plainer titles kept their old search terms.
for (const [query, id] of [['night light', 'power.nightlight-start'], ['output', 'sound.output-port'],
    ['window opening', 'anim.windowsIn'], ['windows move', 'anim.windowsMove'], ['recording volume', 'sound.mic-level'],
    ['scroll factor', 'input.scroll-factor'], ['vrr', 'monitors.vrr'], ['numlock', 'input.numlock']])
    assert.ok(visible(query).includes(id), `"${query}" finds ${id}`)
console.log('ok: search')
