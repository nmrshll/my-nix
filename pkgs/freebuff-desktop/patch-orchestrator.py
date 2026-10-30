"""Patch the pinned backend without modifying the signed Electron bundle."""
import json
import pathlib
import sys

bundle, python, closure_file = sys.argv[1:]
path = pathlib.Path(bundle)
source = path.read_text()
roots = pathlib.Path(closure_file).read_text().splitlines()
if not roots or any(not root.startswith('/nix/store/') for root in roots):
    raise SystemExit('Expected an explicit Nix store closure')


def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit(f'Freebuff backend changed; review patch anchor: {old!r}')
    source = source.replace(old, new, 1)


# Grant only the build-selected interpreter and dependencies. Keep home-secret
# checks, environment scrubbing and all sandbox deny rules in place.
replace_once(
    'function sponsoredToolchainReadRoots(env2, home, log3) {\n',
    'function sponsoredToolchainReadRoots(env2, home, log3) {\n'
    '  const original = nixOriginalToolchainReadRoots(env2, home, log3);\n'
    '  return { ...original, roots: [...new Set([...nixPythonReadRoots, ...original.roots])] };\n'
    '}\nfunction nixOriginalToolchainReadRoots(env2, home, log3) {\n',
)
# PATH is already allowed. Set it after copying the permitted environment so a
# caller's PATH cannot put Apple's Python shim ahead of the Nix interpreter.
replace_once(
    '  env2.HOME = paths.home, env2.USERPROFILE = paths.home,',
    '  env2.PATH = nixPythonBin + ":" + (env2.PATH ?? "/usr/bin:/bin");\n'
    '  env2.HOME = paths.home, env2.USERPROFILE = paths.home,',
)
old_probe = '''  "for c in python3 python; do",
  '  if command -v "$c" >/dev/null 2>&1 && "$c" --version >/dev/null 2>&1; then echo python; break; fi',
  "done",'''
probe = f'{python} --version >/dev/null 2>&1 && echo python'
replace_once(old_probe, '  ' + json.dumps(probe) + ',')
# Bun accepts ESM imports after statements. No caller-supplied variable controls
# these grants, and Python needs no PYTHONHOME/PYTHONPATH or credential passthrough.
source = (
    'const nixPythonReadRoots = ' + json.dumps(roots) + ';\n'
    'const nixPythonBin = ' + json.dumps(str(pathlib.Path(python).parent)) + ';\n'
    'process.env.PATH = nixPythonBin + ":" + (process.env.PATH ?? "/usr/bin:/bin");\n'
    + source
)
path.write_text(source)
