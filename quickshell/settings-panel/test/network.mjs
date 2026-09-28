import assert from 'node:assert/strict'
import * as network from '../network.mjs'

// Flag values from libnm: PRIVACY=0x1; PSK=0x100, 802.1X=0x200, SAE=0x400, OWE=0x800.
// 392 (0x188) is what this machine's WPA2 access points report.
const snap = {
    running: true, wifiEnabled: true, wifiDevices: [{iface: 'wlan0'}],
    accessPoints: [
        {ssid: 'Home', strength: 40, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Home', strength: 84, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Cafe', strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {ssid: 'Office', strength: 70, flags: 1, wpaFlags: 0, rsnFlags: 0x200},
        {ssid: 'New3', strength: 60, flags: 1, wpaFlags: 0, rsnFlags: 0x400},
        {ssid: 'Old', strength: 20, flags: 1, wpaFlags: 0, rsnFlags: 0},
        {ssid: '', strength: 99, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Saved', strength: 10, flags: 1, wpaFlags: 0, rsnFlags: 392},
    ],
    wired: [{iface: 'eno1', carrier: true, speed: 1000, ip4: '192.168.1.10/24', gateway: '192.168.1.1'}],
    connections: [
        {uuid: 'u-saved', id: 'Saved', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-saved2', id: 'Saved 1', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-home', id: 'Home', type: '802-11-wireless', ssid: 'Home', state: 'activated', iface: 'wlan0'},
        {uuid: 'u-proton', id: 'ProtonVPN IT#113', type: 'wireguard', ssid: null, state: 'activated', iface: 'proton0'},
        {uuid: 'u-work', id: 'Work', type: 'vpn', ssid: null, state: null, iface: null},
        {uuid: 'u-kill', id: 'pvpn-killswitch-ipv6', type: 'dummy', ssid: null, state: 'activated', iface: 'ipv6leakintrf0'},
        {uuid: 'u-wired', id: 'Wired connection 1', type: '802-3-ethernet', ssid: null, state: 'activated', iface: 'eno1'},
    ],
}

const list = network.wifiNetworks(snap)
assert.deepEqual(list.map(n => n.ssid), ['Home', 'Saved', 'Cafe', 'Office', 'New3', 'Old'])
assert.equal(list[0].signal, 84)
assert.equal(list[0].active, true)
assert.equal(list[1].known, true)
assert.deepEqual(list.map(n => n.bars), [4, 1, 4, 3, 3, 1])
console.log('ok: networks grouped by SSID, hidden dropped, active/known/signal order')

assert.deepEqual(['Cafe', 'Home', 'Office', 'New3', 'Old'].map(ssid => list.find(n => n.ssid === ssid).security), ['open', 'psk', 'unsupported', 'sae', 'unsupported'])
assert.equal(network.securityOf({flags: 1, wpaFlags: 0, rsnFlags: 0x800}), 'open')
console.log('ok: security from AP flags (open, PSK, SAE, 802.1X, WEP, OWE)')

assert.deepEqual(network.vpnConnections(snap, 'app').map(v => [v.name, v.state, v.control]),
    [['ProtonVPN IT#113', 'activated', 'app'], ['Work', 'off', 'switch']])
assert.equal(network.vpnConnections(snap, 'nm')[0].control, 'switch')
console.log('ok: VPN list has vpn/wireguard only, Proton controlled by mode')

const view = network.networkView(snap, {protonApp: true, mode: 'app'})
assert.equal(view.running, true)
assert.equal(view.wifi.available, true)
assert.equal(view.proton.active, true)
assert.equal(view.wired[0].iface, 'eno1')
assert.deepEqual(network.networkView({running: false}), {running: false})
assert.equal(network.networkView({...snap, wifiDevices: []}).wifi.available, false)
assert.equal(network.networkView(snap, {protonApp: false}).proton, null)
console.log('ok: page model, including NM down and no Wi-Fi device')

assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved'}), {kind: 'activate', uuid: 'u-saved'})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Cafe'}), {kind: 'add', ssid: 'Cafe', psk: null, keyMgmt: null, replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'New3', psk: 'correct horse'}), {kind: 'add', ssid: 'New3', psk: 'correct horse', keyMgmt: 'sae', replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved', psk: 'f'.repeat(64)}), {kind: 'add', ssid: 'Saved', psk: 'f'.repeat(64), keyMgmt: 'wpa-psk', replace: ['u-saved', 'u-saved2']})
for (const [request, message] of [
    [{ssid: 'Old'}, /not supported/],
    [{ssid: 'Office'}, /not supported/],
    [{ssid: 'Gone'}, /no longer in range/],
    [{ssid: 'Home', psk: 'short'}, /8–63/],
    [{ssid: 'Home', psk: 'x'.repeat(64)}, /8–63/],
    [{ssid: 'Home', psk: 'ok but\nnewline'}, /8–63/],
    [{ssid: 'New3'}, /Enter the network password/],
    [{ssid: ''}, /Invalid network name/],
    [{ssid: 'x'.repeat(33)}, /Invalid network name/],
    [{ssid: 42}, /Invalid network name/],
]) assert.throws(() => network.connectPlan(snap, request), message)
console.log('ok: connect plans and every refusal')

assert.deepEqual(network.forgetPlan(snap, 'Saved'), ['u-saved', 'u-saved2'])
assert.throws(() => network.forgetPlan(snap, 'Cafe'), /not saved/)
console.log('ok: forget removes every saved profile for the SSID')

assert.deepEqual(network.vpnPlan(snap, {uuid: 'u-work', active: true}, 'app'), {uuid: 'u-work', active: true})
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-proton', active: false}, 'app'), /Proton VPN app/)
assert.deepEqual(network.vpnPlan(snap, {uuid: 'u-proton', active: false}, 'nm'), {uuid: 'u-proton', active: false})
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-wired', active: false}, 'nm'), /not a VPN/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'nope', active: true}, 'nm'), /no longer exists/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-work', active: 'yes'}, 'nm'), /on\/off/)
assert.equal(network.failureMessage('NO_SECRETS'), 'Wrong password')
assert.equal(network.failureMessage('LOGIN_FAILED'), 'Wrong password')
assert.equal(network.failureMessage('CONNECT_TIMEOUT'), 'The network did not answer in time')
assert.equal(network.failureMessage('SOMETHING_NEW'), 'Connection failed (something new)')
console.log('ok: VPN plans and readable failure reasons')
