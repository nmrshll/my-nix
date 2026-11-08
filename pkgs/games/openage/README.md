# openage

Neither pinned nixpkgs input packages openage. This builds upstream release
0.6.0 and its pinned nyan 0.3 dependency using Qt 6 and Python 3.12. Source
downloads are fixed; CMake cannot fetch or update dependencies during the build.

The Python environment and Qt paths are wrapped into the `openage` launcher.
The wrapper is explicit because the Qt hook does not automatically wrap this
Python script. Install checks run from a fresh directory with `PYTHONPATH`
unset, so source-tree imports cannot conceal a broken installed launcher.
The release version is set explicitly because GitHub source archives do not
carry Git history for upstream's version detection.
Original Age of Empires assets are not included. Upstream describes gameplay
as experimental/incomplete; installing the engine does not provide a complete
playable Age of Empires replacement.

Use `openage --help` and `openage convert --help` for asset conversion, and
`openage main` to start the engine once suitable assets have been converted.
