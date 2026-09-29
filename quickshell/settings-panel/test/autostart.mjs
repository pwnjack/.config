import assert from 'node:assert/strict'
import fs from 'node:fs'
import * as autostart from '../autostart.mjs'

const system = [
    {id: 'nm-applet.desktop', text: '[Desktop Entry]\nName=Network\nExec=nm-applet\nNotShowIn=KDE;GNOME;\nIcon=nm-device-wireless\n'},
    {id: 'blueman.desktop', text: '[Desktop Entry]\nName=Blueman Applet\nExec=blueman-applet\n'},
    {id: 'gnome-only.desktop', text: '[Desktop Entry]\nName=GNOME thing\nExec=gnome-thing\nOnlyShowIn=GNOME;\n'},
    {id: 'skipped.desktop', text: '[Desktop Entry]\nName=Skipped\nExec=skip\nX-systemd-skip=true\n'},
    {id: 'kde.desktop', text: '[Desktop Entry]\nName=KDE thing\nExec=kde-thing\nNotShowIn=Hyprland;\n'},
]
const user = [
    {id: 'blueman.desktop', text: '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n'},
    {id: 'arch-update-tray.desktop', text: '[Desktop Entry]\nName=Arch-Update Systray Applet\nExec=arch-update --tray\n'},
    {id: 'quoted.desktop', text: '[Desktop Entry]\nName=Quoted\nExec="/opt/My App/run" --flag\n'},
    {id: 'gnome-off.desktop', text: '[Desktop Entry]\nName=Gnome off\nExec=blueman-applet\nX-GNOME-Autostart-enabled=false\n'},
]
const onPath = binary => ['nm-applet', 'blueman-applet', 'gnome-thing', 'skip', 'kde-thing', '/opt/My App/run'].includes(binary)
const entries = autostart.autostartEntries({system, user, desktops: ['Hyprland'], onPath})
const byId = Object.fromEntries(entries.map(e => [e.id, e]))

assert.equal(byId['nm-applet.desktop'].origin, 'system')
assert.equal(byId['blueman.desktop'].origin, 'override')
assert.equal(byId['arch-update-tray.desktop'].origin, 'user')
console.log('ok: user files replace system files by id')

assert.equal(byId['nm-applet.desktop'].enabled, true)
assert.equal(byId['nm-applet.desktop'].scope, '')
assert.equal(byId['blueman.desktop'].enabled, false)
assert.equal(byId['gnome-off.desktop'].enabled, false)
assert.match(byId['gnome-only.desktop'].scope, /Only for GNOME/)
assert.match(byId['kde.desktop'].scope, /Not for Hyprland/)
assert.match(byId['skipped.desktop'].scope, /systemd/)
console.log('ok: Hidden, GNOME flag, OnlyShowIn, NotShowIn and X-systemd-skip')

assert.equal(byId['blueman.desktop'].name, 'Blueman Applet')
assert.equal(byId['blueman.desktop'].binary, 'blueman-applet')
assert.equal(byId['arch-update-tray.desktop'].installed, false)
assert.equal(byId['arch-update-tray.desktop'].binary, 'arch-update')
assert.equal(byId['quoted.desktop'].binary, '/opt/My App/run')
assert.equal(byId['quoted.desktop'].installed, true)
console.log('ok: overrides describe the system entry; binaries are resolved')

assert.deepEqual(entries.slice(0, 2).map(e => e.id), ['arch-update-tray.desktop', 'nm-applet.desktop'])
console.log('ok: enabled-and-applicable first, then by name')

assert.equal(autostart.unitName('nm-applet.desktop'), 'app-nm\\x2dapplet@autostart.service')
assert.equal(autostart.unitName('org.kde.discover.notifier.desktop'), 'app-org.kde.discover.notifier@autostart.service')
assert.equal(autostart.unitName('a b.desktop'), 'app-a\\x20b@autostart.service')
console.log('ok: unit names use systemd escaping')

const units = [
    {unit: 'app-nm\\x2dapplet@autostart.service', active: 'active', sub: 'running'},
    {unit: 'app-gnome\\x2doff@autostart.service', active: 'failed', sub: 'failed'},
    {unit: 'app-quoted@autostart.service', active: 'inactive', sub: 'dead'},
]
const status = Object.fromEntries(autostart.withStatus(entries, units).map(e => [e.id, e.status]))
assert.deepEqual(status['nm-applet.desktop'], {state: 'running', label: 'Running'})
assert.deepEqual(status['gnome-off.desktop'], {state: 'failed', label: 'Failed'})
assert.deepEqual(status['quoted.desktop'], {state: 'finished', label: 'Finished'})
assert.deepEqual(status['arch-update-tray.desktop'], {state: 'missing', label: 'Not installed: arch-update'})
assert.deepEqual(status['blueman.desktop'], {state: 'none', label: ''})
console.log('ok: status from list-units, missing binaries first')

assert.equal(autostart.minimalOverride('Blueman\nApplet'), '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n')
assert.equal(autostart.isMinimalOverride(user[0].text), true)
assert.equal(autostart.isMinimalOverride('# note\n\n' + user[0].text), true)
assert.equal(autostart.isMinimalOverride(user[0].text + 'Comment=mine\n'), false)
assert.equal(autostart.isMinimalOverride(user[1].text), false)
console.log('ok: minimal override text and recognition')

const full = '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n'
const hidden = autostart.setHidden(full, true)
assert.equal(hidden, '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\nHidden=true\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden(hidden, false), '# keep\n[Desktop Entry]\nName=X\nExec=x\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden('[Desktop Entry]\nName=Y\nHidden = true\n', true), '[Desktop Entry]\nName=Y\nHidden=true\n')
console.log('ok: setHidden edits only the main group and only Hidden / the GNOME flag')

const parsed = autostart.parseEntry('[Desktop Entry]\nName=A\nName=B\n[Other]\nExec=no\n')
assert.deepEqual(parsed, {Name: 'A'})
console.log('ok: parseEntry keeps the first key and only the main group')

const lua = fs.readFileSync(new URL('../../../hypr/config/setup/autostart.lua', import.meta.url), 'utf8')
const commands = autostart.sessionCommands(lua)
assert.equal(commands[0], 'waybar')
assert.ok(commands.includes('systemctl --user start …'))
assert.ok(commands.includes('wl-paste --type text --watch cliphist store'))
assert.deepEqual(autostart.sessionCommands('-- hl.exec_cmd("commented")\nhl.exec_cmd("a \\"q\\"")'), ['a "q"'])
console.log('ok: session commands parsed from autostart.lua')
