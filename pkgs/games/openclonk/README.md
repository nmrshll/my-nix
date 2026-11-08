# OpenClonk for macOS

Both pinned nixpkgs inputs restrict OpenClonk to Linux. On macOS this packages
the official 8.0 Intel x86_64 app from the release archive; upstream's 8.1
directory has no Mac build. Apple Silicon needs Rosetta 2. Linux consumers
continue to use nixpkgs rather than this package.

The full bundle retains its Qt libraries, game data, tutorials, scenarios, and
music. It installs as `OpenClonk.app` with an `openclonk` terminal launcher.
The package does not modify signing, quarantine, or system security settings.

The upstream binary reached its menu on an Apple Silicon Mac running macOS
15.7.4, initialized OpenGL 4.1, and loaded graphics and music. This verifies
startup, not complete gameplay. It does not support `--version`; that option
prints a warning and still starts the game. Build checks inspect the installed
bundle and launcher without opening a GUI.
