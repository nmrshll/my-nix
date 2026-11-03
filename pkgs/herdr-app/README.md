# Herdr desktop

Neither of nix-home's pinned nixpkgs inputs provides the Herdr desktop app.
Unstable's `herdr` package is the older terminal multiplexer from
`herdrdev/herdr`, rather than the requested `herdrdev/herdr-app`.

This package pins the official 0.1.12 Apple Silicon tarball and SHA-256 checksum
from <https://releases.herdr.dev/app/latest.json>. It preserves the complete
Developer ID signed bundle without patching or re-signing it. Other systems
return `null` from the package collector.

The app is installed under `Applications/Herdr.app`; `herdr-app` launches it and
supports `--version`, `--help`, and `--skill`. Install checks cover bundle
identity, version, ARM64 architecture, resources, and the executable launcher.
Run the version command after building: executing the signed binary during a
build can add macOS provenance metadata that prevents Nix finalizing the output.
Verify the installed signature with `codesign --verify --deep --strict` outside
the build sandbox, which cannot access macOS signature verification services.

Herdr requires the separate `herdr-core` runtime (at least 0.1.11 for this
release). nix-home installs `pkgs.own.herdr-core` 0.1.17 alongside this app.
The app explicitly searches `~/.nix-profile/bin` for the runtime. Neither package
runs upstream's shell installer during a build.

Validation on 2026-11-03: built through the my-nix collector; install checks,
the installed launcher's `--version`/`--help`, and external
`codesign --verify --deep --strict` all passed. No interactive GUI session was
started. The subsequent core integration is validated in
[`../herdr-core/README.md`](../herdr-core/README.md).
