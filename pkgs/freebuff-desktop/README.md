# Freebuff Desktop

`pkgs.own.freebuff-desktop` packages the official Apple Silicon macOS app,
separately from `pkgs.own.freebuff-launcher` (the CLI). The official download
endpoint resolves to a versioned GitHub release; the package pins that release
and its SHA-256 hash instead of fetching the mutable endpoint.

The package uses the shared `installDmg` helper for the APFS disk image and
copies `Freebuff.app` intact to `$out/Applications`. It skips binary fixup to
preserve upstream's signing. `freebuff-desktop` opens the packaged app through
macOS Launch Services. Other platforms expose a null package.

Build from this checkout:

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.freebuff-desktop {}'
```

Installation checks verify the executable, Electron resources, app version,
and launcher. To verify the copied bundle's signature after building, run
`codesign --verify --deep --strict /nix/store/…-freebuff-desktop-…/Applications/Freebuff.app`.

To update, resolve `https://freebuff.com/api/desktop/download/mac-arm64`, then
update the version and hash together in `package.nix`.
