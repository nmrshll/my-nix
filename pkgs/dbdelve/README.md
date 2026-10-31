# DBDelve

Neither of nix-home's pinned nixpkgs inputs packages DBDelve. This package uses
the official 0.6.1 macOS DMG, pinned by its SHA-256 hash, and the existing
`pkgs.lib.darwin.installDmg` helper.

Upstream ships an Apple Silicon app for macOS 12 or later. The collector returns
`null` on other systems. The complete `DBDelve.app` retains its native ARM64
executable, icon, third-party license notices, and upstream ad-hoc signature.
Install checks verify the bundle identity/version, architecture, signature,
resources, and terminal-launcher syntax.

Launch **DBDelve** through the macOS app launcher or run `dbdelve`. It has no
version/help CLI: those arguments would still start the GUI. The package does
not clear quarantine attributes or change Gatekeeper settings.

Validation on 2026-10-31: the package built through the my-nix collector and
passed all install checks. The installed app opened and rendered its
**Connect a database** startup screen on Apple Silicon. No database connection
or credential entry was used for this startup check.

References: [release](https://github.com/ShayanAbbas1/dbdelve/releases/tag/v0.6.1)
and [upstream installation instructions](https://github.com/ShayanAbbas1/dbdelve/blob/v0.6.1/docs/install.md).
