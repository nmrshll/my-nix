# Urban Terror

nixpkgs packages Urban Terror 4.3.4 for Linux only. The Darwin package uses the
official full release ZIP, retaining the Intel x86_64 Mac app, its SDL library,
and all `q3ut4` assets. Apple Silicon requires Rosetta 2.

The game files stay beside the app under `$out/share/urbanterror`; the
Applications entry points there. The `urbanterror` command also supplies an
explicit base path so it can launch from any working directory.

The Apple Silicon download on the upstream downloads page is an updater, not
the complete game. This package uses fixed game assets and does not require an
updater to write into the immutable Nix store.
