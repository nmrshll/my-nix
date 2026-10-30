// Exercise the patched release's real scrubber, toolchain discovery, probe and
// Seatbelt profile generator without starting the desktop server or reading state.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [output] = process.argv.slice(2);
const source = fs.readFileSync(`${output}/libexec/orchestrator/orchestrator.js`, 'utf8');
function section(start, end) {
  const at = source.indexOf(start);
  assert(at >= 0, `Missing ${start}`);
  const stop = source.indexOf(end, at + start.length);
  assert(stop >= 0, `Missing ${end}`);
  return source.slice(at, stop);
}
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'freebuff-nix-check-'));
try {
  const modulePath = path.join(temp, 'backend-parts.mjs');
  fs.writeFileSync(modulePath, [
    "import fs16 from 'node:fs'; import path27 from 'node:path';",
    source.slice(0, source.indexOf('process.env.PATH = nixPythonBin')),
    section('var SPONSORED_LOCAL_ENV_ALLOWLIST', 'var SPONSORED_WINDOWS_ENV_ALLOWLIST'),
    section('// ../sdk/src/tools/sponsored-toolchain.ts', '// src/server/repo/project-db.ts'),
    section('function canonicalRoot(target)', 'var ENV_TEMPLATE_BASENAMES2'),
    section('function sbplLiteral(', 'function secretScanSkips('),
    section('function sponsoredMacProfile(', 'function spawnMac('),
    section('var SPONSORED_RUNTIME_PROBE_TIMEOUT_MS', 'function parseSponsoredRuntimeProbe'),
    'export { sponsoredToolchainReadRoots, scrubSponsoredLocalEnv, sponsoredMacProfile, SPONSORED_RUNTIME_PROBE_SCRIPT, nixPythonBin };',
  ].join('\n'));
  const backend = await import(pathToFileURL(modulePath));
  const workspace = path.join(temp, 'workspace');
  const runtime = path.join(temp, 'runtime');
  const home = path.join(runtime, 'home');
  const tmp = path.join(runtime, 'tmp');
  for (const dir of [workspace, home, tmp]) fs.mkdirSync(dir, {recursive: true});
  const credential = path.join(temp, 'private-token');
  fs.writeFileSync(credential, 'synthetic test credential');
  const env = backend.scrubSponsoredLocalEnv({
    PATH: '/usr/bin:/bin', OPENAI_API_KEY: 'synthetic-key', PYTHONPATH: '/untrusted',
  }, {home, tmp});
  assert.equal(env.OPENAI_API_KEY, undefined);
  assert.equal(env.PYTHONPATH, undefined);
  assert.equal(env.HOME, home);
  assert.equal(env.PATH.split(':')[0], backend.nixPythonBin);
  const roots = backend.sponsoredToolchainReadRoots(env, temp).roots;
  const closure = fs.readFileSync(`${output}/libexec/python-store-paths`, 'utf8').trim().split('\n');
  assert(closure.every(root => roots.includes(root)));
  assert(!roots.includes('/nix/store'));
  const profile = backend.sponsoredMacProfile([workspace, runtime], roots);
  function sandbox(command, args) {
    const result = spawnSync('/usr/bin/sandbox-exec', ['-p', profile, command, ...args], {
      cwd: workspace, env, encoding: 'utf8', timeout: 15000,
    });
    assert.ifError(result.error);
    return result;
  }
  const probe = sandbox('/bin/sh', ['-c', backend.SPONSORED_RUNTIME_PROBE_SCRIPT]);
  assert.equal(probe.status, 0, probe.stderr);
  assert(probe.stdout.split('\n').includes('python'), probe.stdout + probe.stderr);
  assert(probe.stdout.includes('__freebuff_runtimes_done__'));
  const python = `${backend.nixPythonBin}/python3`;
  const imports = sandbox(python, ['-c', 'import sys, ssl, sqlite3, ctypes, json; print(sys.executable); print(ssl.OPENSSL_VERSION)']);
  assert.equal(imports.status, 0, imports.stderr);
  assert(imports.stdout.includes(python));
  for (const denied of [credential, `${output}/libexec/python-store-paths`]) {
    assert.notEqual(sandbox('/bin/cat', [denied]).status, 0, `Unexpected read access: ${denied}`);
  }
  const writes = sandbox(python, ['-c', 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("ok")', path.join(workspace, 'result')]);
  assert.equal(writes.status, 0, writes.stderr);
  assert.equal(fs.readFileSync(path.join(workspace, 'result'), 'utf8'), 'ok');
  console.log('PASS: runtime probe, Python native imports, private HOME, credential filtering, workspace writes, unrelated file/store denial');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
