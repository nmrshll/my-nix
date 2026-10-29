# Warsow

Both nix-home's pinned nixpkgs inputs removed `warsow` because the package was
unmaintained and broken. This package preserves the official Warsow 2.1.2 macOS
app, including its game assets, dynamic modules, and bundled frameworks.

The executable is Intel x86_64; Apple Silicon needs Rosetta 2. The release app
is unsigned. No quarantine settings or system security protections are changed.

Launch `Warsow` from the app launcher after a switch, or run `warsow`.
