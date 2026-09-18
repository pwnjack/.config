#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    source, dest, bins = (base / name for name in ('source', 'destination', 'bin'))
    for path in (source / 'ags', dest / 'ags', bins):
        path.mkdir(parents=True)
    (source / 'ags/app.ts').write_text('new')
    (source / 'sp ace-é').write_text('new spaced')
    (source / '.env').write_text('untracked fixture')
    (source / 'cache-link').symlink_to('missing-cache')
    (dest / 'ags/app.ts').write_text('old')
    (dest / 'sp ace-é').write_text('old spaced')
    (dest / 'cache-link').symlink_to('old-missing-cache')
    (dest / 'unrelated').write_text('keep')
    manifest = base / 'manifest'
    manifest.write_bytes(b'ags/app.ts\0sp ace-\xc3\xa9\0cache-link\0')
    fakegit = bins / 'git'
    fakegit.write_text('#!/bin/bash\n[ "${FAIL_GIT:-0}" = 0 ] || exit 1\ncat "$MANIFEST"\n')
    fakegit.chmod(0o755)
    env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'], MANIFEST=str(manifest))
    def deploy(name, dry='false', no_backup='false', **extra):
        return subprocess.run(['bash', '-c', 'source "$1"; deploy_dotfiles "$2" "$3" "$4" "$5" "$6"',
            'test', str(root / 'scripts/lib/deploy.sh'), str(source), str(dest), str(base / name), dry, no_backup],
            env=dict(env, **extra), capture_output=True, text=True)
    result = deploy('dry-backup', dry='true')
    assert result.returncode == 0, result.stderr
    assert not (base / 'dry-backup').exists()
    assert (dest / 'ags/app.ts').read_text() == 'old'
    print('ok: dry run creates no backup and writes no destination files')
    result = deploy('backup')
    assert result.returncode == 0, result.stderr
    assert (base / 'backup/ags/app.ts').read_text() == 'old'
    assert (base / 'backup/sp ace-é').read_text() == 'old spaced'
    assert os.readlink(base / 'backup/cache-link') == 'old-missing-cache'
    assert os.readlink(dest / 'cache-link') == 'missing-cache'
    assert (dest / 'ags/app.ts').read_text() == 'new'
    assert not (dest / '.env').exists()
    assert (dest / 'unrelated').read_text() == 'keep'
    print('ok: tracked files and dangling symlinks are backed up; untracked files stay out')
    assert deploy('backup').returncode != 0
    assert (base / 'backup/ags/app.ts').read_text() == 'old'
    print('ok: existing backups cannot be overwritten')
    (dest / 'cache-link').unlink()
    outside = base / 'outside'
    outside.mkdir()
    (dest / 'cache-link').symlink_to(outside, target_is_directory=True)
    assert deploy('link-backup').returncode == 0
    assert not list(outside.iterdir())
    assert os.readlink(dest / 'cache-link') == 'missing-cache'
    print('ok: leaf symlinks to directories are replaced without writing through them')
    (dest / 'ags/app.ts').unlink()
    (dest / 'ags').rmdir()
    (dest / 'ags').symlink_to(outside, target_is_directory=True)
    result = deploy('unsafe-backup')
    assert result.returncode != 0
    assert not (base / 'unsafe-backup').exists()
    assert not list(outside.iterdir())
    print('ok: symlinked parent directories fail preflight before any writes')
    (dest / 'ags').unlink()
    (dest / 'ags').mkdir()
    assert deploy('git-failed', FAIL_GIT='1').returncode != 0
    assert not (base / 'git-failed').exists()
    assert deploy('no-backup', no_backup='true').returncode == 0
    assert not (base / 'no-backup').exists()
    print('ok: Git failure aborts safely and --no-backup skips only backups')
PY
