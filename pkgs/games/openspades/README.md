# OpenSpades on macOS

`pkgs.own.openspades` packages upstream's OpenSpades 0.1.3 macOS app because
both pinned nixpkgs inputs mark their source package broken on Darwin.
The versioned ZIP and SHA-256 hash are pinned in `package.nix`.

The official app includes its game resources and SDL frameworks. It is an Intel
binary and requires Rosetta 2 on Apple Silicon. The package preserves the bundle
and supplies `openspades` as a terminal launcher. Home Manager can discover
`Applications/OpenSpades.app` for the normal macOS app launcher.

Build this package from the my-nix checkout:

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.openspades {}'
```

Installation checks verify the executable, bundled frameworks, game resources,
app version and launcher syntax. Linux should use `pkgs.openspades` from nixpkgs.
