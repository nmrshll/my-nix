# Delta from Zed

`pkgs.own.zed-delta` packages the official Delta 0.23.0 Apple Silicon macOS app.
Neither pinned nixpkgs input contains this app: `pkgs.delta` is the unrelated
Git diff pager. Zed's official `delta-nix` flake currently supports Linux only.

The versioned ZIP and hash are pinned in `package.nix`, which follows the
`versions` / `mkPkg` / `passthru` pattern. The GUI package group registers a lazy
nullary definition and returns null on unsupported systems.

The signed bundle is copied intact to `$out/Applications/Delta.app` without
binary fixup. `zed-delta` runs the bundled CLI, and `delta-app` invokes its
`open` command. Both names avoid colliding with the diff pager's `delta` command.
The CLI wrapper sets upstream's `DELTA_UPDATE_EXPLANATION` override; update this
package through Nix. The app's own files remain immutable in the store.

Build from the my-nix checkout:

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.zed-delta {}'
```

Installation checks verify the app identity, resources, CLI release version,
and launch command syntax. Upstream's Info.plist still reports 0.1.0, so the
actual version check uses `zed-delta --version`. Verify the built bundle with
`codesign --verify --deep --strict /nix/store/…-zed-delta-…/Applications/Delta.app`.

For 0.23.0, this signature check reports an invalid arm64 signature for both
the freshly extracted upstream ZIP and the Nix output. Both bundled executables
are byte-for-byte identical to upstream; the package does not re-sign them.
The CLI version and installation checks pass, but a full GUI launch has not
been verified.

To update, resolve the public download API:
`https://delta.dev/api/releases/stable/latest/asset?asset=delta&os=macos&arch=aarch64`,
then pin its version and artifact hash together.

Sources: [official downloads](https://delta.dev/download) and
[official Linux flake](https://github.com/zed-industries/delta-nix).
