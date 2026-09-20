#!/bin/bash
# Exercise the real pipeline with isolated caches and command stubs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    config, cache, bins = (base / n for n in ('config', 'cache', 'bin'))
    for path in (config / 'options', config / 'scripts/theming', cache, bins):
        path.mkdir(parents=True, exist_ok=True)
    (config / 'options/mainmonitor').write_text('')
    selected, events = base / 'selected', base / 'events'
    first, second = base / 'first.jpg', base / 'second.jpg'
    first.touch(); second.touch()
    selected.write_text(str(first))
    def executable(path, text):
        path.write_text('#!/bin/bash\nset -eu\n' + text)
        path.chmod(0o755)
    executable(bins / 'awww', 'printf ": DP-1: image: %s\\n" "$(cat "$FIXTURE/selected")"\n')
    executable(bins / 'wal', '''
mkdir "$FIXTURE/busy" || { echo overlap >> "$FIXTURE/events"; exit 1; }
trap 'rmdir "$FIXTURE/busy"' EXIT
echo "start $3" >> "$FIXTURE/events"
sleep 0.2
[ "${FAIL_WAL:-0}" = 0 ] || exit 1
echo "end $3" >> "$FIXTURE/events"
''')
    executable(bins / 'notify-send', 'printf "%s\\n" "$*" >> "$FIXTURE/notices"\n')
    for name in ('ags', 'astal', 'eww'):
        executable(bins / name, 'echo "$0" >> "$FIXTURE/ui-starts"\n')
    driver = config / 'scripts/theming/apply-wal.sh'
    executable(driver, 'echo apply >> "$FIXTURE/events"\nexit "${FAIL_APPLY:-0}"\n')
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_CACHE_HOME=str(cache),
               PATH=str(bins) + ':' + os.environ['PATH'], FIXTURE=str(base))
    command = ['bash', str(root / 'scripts/hyprland/wall.sh')]
    def run(**extra):
        return subprocess.run(command, env=dict(env, **extra), capture_output=True, timeout=10)
    assert run(FAIL_WAL='1').returncode == 1
    assert not (cache / 'current_wallpaper').exists()
    assert 'apply' not in events.read_text()
    assert 'Wallpaper Applied' not in (base / 'notices').read_text()
    print('ok: generation failure does not publish state, reload, or announce success')
    (base / 'notices').write_text('')
    assert run(FAIL_APPLY='1').returncode == 1
    assert 'Wallpaper Applied' not in (base / 'notices').read_text()
    assert 'some components failed' in (base / 'notices').read_text()
    print('ok: partial component failure reaches the caller and notification')
    events.write_text('')
    one = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while 'start' not in events.read_text():
        assert time.monotonic() < deadline
        time.sleep(.01)
    selected.write_text(str(second))
    two = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for process in (one, two):
        process.communicate(timeout=10)
        assert process.returncode == 0
    lines = events.read_text().splitlines()
    assert lines == [f'start {first}', f'end {first}', 'apply', f'start {second}', f'end {second}', 'apply'], lines
    assert (cache / 'current_wallpaper').resolve() == second
    print('ok: overlapping changes serialize and the latest wallpaper wins')
    assert not any('ags' in line or 'astal' in line for line in (base / 'ui-starts').read_text().splitlines())
    print('ok: wallpaper changes do not start a resident settings panel')
    # The real driver attempts later components even if an earlier one fails.
    for name, code in [('a', 1), ('b', 0)]:
        directory = config / name
        directory.mkdir()
        executable(directory / 'apply_wal_colors.sh', f'echo {name} >> "$FIXTURE/components"\nexit {code}\n')
    result = subprocess.run(['bash', str(root / 'scripts/theming/apply-wal.sh')], env=env, capture_output=True)
    assert result.returncode == 1
    assert (base / 'components').read_text() == 'a\nb\n'
    print('ok: driver attempts all components and preserves failure status')
PY
