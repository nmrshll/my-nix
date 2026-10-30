"""Seed a writable upstream app; prepare the Nix backend without editing it."""
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

output = Path(sys.argv[1])
args = sys.argv[2:]
app = Path(os.environ.get('FREEBUFF_DESKTOP_APP', str(Path.home() / 'Applications/Freebuff.app'))).absolute()
cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / 'Library/Caches'))) / 'freebuff-nix'
cache.mkdir(parents=True, exist_ok=True)
resources = app / 'Contents/Resources'


def prepare():
    source = resources / 'orchestrator/orchestrator.js'
    digest = hashlib.sha256(source.read_bytes() + str(output).encode()).hexdigest()
    destination = cache / digest
    if not destination.exists():
        staging = Path(tempfile.mkdtemp(prefix='backend-', dir=cache))
        try:
            shutil.copytree(resources / 'orchestrator', staging / 'orchestrator')
            backend = staging / 'orchestrator/orchestrator.js'
            backend.chmod(0o644)
            subprocess.run([
                sys.executable, str(output / 'libexec/patch-orchestrator.py'),
                str(backend), sys.executable, str(output / 'libexec/python-store-paths'),
            ], check=True)
            staging.rename(destination)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    return destination / 'orchestrator/orchestrator.js'


try:
    with (cache / 'prepare.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not app.exists():
            app.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(tempfile.mkdtemp(prefix='.freebuff-', dir=app.parent))
            try:
                copy = staging / 'Freebuff.app'
                subprocess.run(['/usr/bin/ditto', str(output / 'libexec/Freebuff.app'), str(copy)], check=True)
                # Nix finalizes outputs as read-only. Squirrel needs both the app
                # and its parent writable; permissions do not change signed bytes.
                for root, dirs, files in os.walk(copy):
                    for name in ['.'] + files:
                        item = Path(root) / name
                        if not item.is_symlink():
                            item.chmod(item.stat().st_mode | 0o200)
                copy.rename(app)
            finally:
                shutil.rmtree(staging)
        if args == ['--install']:
            sys.exit(0)
        backend = prepare()
    if args == ['--prepare-backend']:
        print(backend)
        sys.exit(0)
    env = os.environ.copy()
    env['FREEBUFF_DESKTOP_APP'] = str(app)
    env['FREEBUFF_BUN_PATH'] = str(output / 'libexec/freebuff-bun')
    env['PATH'] = str(Path(sys.executable).parent) + ':' + env.get('PATH', '/usr/bin:/bin')
    if args[:1] == ['--bun']:
        command = str(resources / 'bun/bun')
        args = [str(backend) if arg == str(resources / 'orchestrator/orchestrator.js') else arg for arg in args[1:]]
    else:
        command = str(app / 'Contents/MacOS/Freebuff')
    os.execve(command, [command, *args], env)
except (OSError, subprocess.CalledProcessError) as error:
    print(f'Freebuff Nix integration failed: {error}\n'
          'The installed desktop may need a new Python patch in my-nix. '
          'Its app bundle and data have been preserved.', file=sys.stderr)
    sys.exit(1)
