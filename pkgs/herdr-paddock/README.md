# Paddock for Herdr desktop

Neither pinned nixpkgs input provides this mod. `herdr-paddock` installs the
unmodified mod from `choam2426/herdr-paddock`, pinned to commit
`540e3d20d7b960ac325fd5a5401f905b40e93953` (2026-11-02) with a fixed source hash.
It exposes `share/herdr-app/mods/paddock` for Home Manager to link into Herdr's
configuration. The package runs upstream's 67 project/grouping/agent-data checks
during its build and includes the license notices.

nix-home supplies the personal `nix-paddock` layout, which replaces Herdr's
shipped Spaces block with Paddock. The mod, layout, and default selection are
managed by Nix; project directories, folds and pins remain writable app state.

The mod runs read-only Git queries and `hc machine ls`, checks project folders
(using a shell on remote machines), and can import the old space-folders file.
It uses no network APIs itself. Remote Git/core operations use the configured
machine connections. It does not need Node at runtime.

Validation on 2026-11-03: built through both the my-nix collector and nix-home's
package set, with all 67 upstream checks passing. Herdr 0.1.12 on Apple Silicon
accepted `herdr-app check`, switched to the managed layout, and rendered the
sidebar with its New project button. Runtime status reported no errors.
Interactive project creation and persistence across closing its last terminal
remain for the user's trial; the package's grouping tests cover empty projects.
