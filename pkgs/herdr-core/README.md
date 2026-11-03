# Herdr core

Neither of nix-home's pinned nixpkgs inputs packages `herdr-core`; unstable's
`herdr` is the older terminal multiplexer. This package pins the official
Apple Silicon 0.1.17 tarball and SHA-256 checksum from
<https://releases.herdr.dev/core/latest.json>. Other systems return `null`.

It provides `herdr-core` and the `hc` alias, preserving the upstream binary and
its signature. License and third-party notices are installed alongside it.
Build checks verify the executable, alias, and ARM64 architecture. Run version,
help, and signature checks outside the build sandbox to avoid macOS provenance
metadata interfering with Nix output finalization.

Herdr desktop 0.1.12 requires core 0.1.11 or newer. The app explicitly searches
`~/.nix-profile/bin`, so installing this package in Home Manager makes the core
available to GUI launches as well as terminal launches. No daemon is started
at activation; Herdr starts the core when needed. Nix owns the installed
executable; updates belong in this derivation rather than `hc update`.

Validation on 2026-11-03: built through the my-nix collector. Both installed
command names report `hc 0.1.17`; help and external signature verification pass.
`hc update --json` returned `updated: false` without changing the installed
binary. nix-home resolves this core through the local my-nix override and its
GUI module selects both desktop and core only on Apple Silicon. No core server
or interactive GUI session was started for validation.
