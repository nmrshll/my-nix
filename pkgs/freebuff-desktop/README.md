# Freebuff Desktop

`pkgs.own.freebuff-desktop` supplies the official Apple Silicon macOS app plus
its Nix Python integration. Neither pinned nixpkgs input currently provides
Freebuff. The CLI remains a separate `pkgs.own.freebuff-launcher` package.

## Writable desktop and updates

Nix pins Freebuff 0.0.192 as a bootstrap app, downloaded from a versioned GitHub
release with a fixed SHA-256 hash. The signed bundle is kept intact under
`$out/libexec/Freebuff.app`. On first use, `freebuff-desktop` copies it to
`~/Applications/Freebuff.app` and makes the copy writable. Subsequent launches
and Home Manager switches preserve the installed app, including newer versions
installed by Freebuff's own updater. Nix rollback does not roll back that copy.
An existing app at that location is also preserved.

The package exposes a launcher app under `$out/Applications/Freebuff.app`, so
the existing mac-app-util trampoline continues to work. The actual Electron
process executes from the writable bundle. `freebuff-desktop --install` only
seeds the copy; it does not open the GUI. `FREEBUFF_DESKTOP_APP` can select a
different writable app path for manual use or testing.

The nix-home activation seeds the app and sets `FREEBUFF_BUN_PATH` in launchd's
user environment. Home Manager also sets it for shells. This makes Finder
launches and upstream updater restarts use the same backend bridge. Quit an
already-running Freebuff instance after rebuilding, then launch it again.

## Python sandbox integration

`FREEBUFF_BUN_PATH` is an existing desktop runtime override. The bridge runs
the installed app's bundled Bun with an external copy of its orchestrator.
The signed app itself is never patched or re-signed. The patch:

- Places the package's Nix Python first on the backend and sandbox PATH.
- Adds only that Python's explicit `closureInfo` store paths to the sandbox's
  read roots; it does not grant `/nix/store` as a whole.
- Makes the runtime probe call that Python by absolute path, avoiding Apple's
  `/usr/bin/python3` shim and any installer dialog.
- Keeps the existing credential filtering, private HOME, secret deny rules,
  and read-only treatment of toolchains.

This supplies a base Python interpreter. It does not import a project's dev
shell, Python dependencies, SDKROOT or other build variables. The CLI's
compiled auto-updating runtime is not patched by this desktop integration.

The external backend is cached under `~/Library/Caches/freebuff-nix` (or
`$XDG_CACHE_HOME/freebuff-nix`), keyed by the installed backend's SHA-256 and
the Nix package path. Each updated backend is patched before use. Patch anchors
must match exactly: if upstream changes the relevant code, launch fails with
`Freebuff backend changed; review patch anchor` and the installed app and data
are preserved. Update `patch-orchestrator.py` for that release and rebuild.
Auto-updates are writable, but compatibility with every future backend is not
guaranteed. The launcher does not silently downgrade an updated app.

## Validation and maintenance

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.freebuff-desktop {}'
node pkgs/freebuff-desktop/check-sandbox.mjs /nix/store/…-freebuff-desktop-0.0.192
codesign --verify --deep --strict /nix/store/…-freebuff-desktop-0.0.192/libexec/Freebuff.app
```

Installation checks verify the seed app, version, launcher syntax, Python native
imports and patch anchors. The sandbox check extracts the actual patched
release's environment scrubber, toolchain discovery, runtime probe and Seatbelt
profile generator without starting the server. It verifies Python native
imports, workspace writes, credential filtering and denial of unrelated files
and Nix-store contents.

The writable-copy launcher has also been checked in a temporary directory for
signature preservation, preservation of a newer installed version, backend
cache reuse, and explicit failure on incompatible backend changes. A live
upstream download/install/restart cycle still requires GUI verification.

To update the bootstrap release, resolve
`https://freebuff.com/api/desktop/download/mac-arm64`, update the version and
hash together in `package.nix`, review the patch anchors, and rerun the checks.
Removing the writable app manually allows the next launch to seed it again;
this does not remove Freebuff's separately stored user data.
