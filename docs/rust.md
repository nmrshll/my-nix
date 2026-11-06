# Rust development shells

Projects that import the Rust flake module get Kache by default. Set
`perSystem.rust.kache.enable = false;` in a consumer flake to disable it.
Kache shares compiler artifacts across worktrees through
`~/.cache/kache`, using its automatic storage budget. Keep each worktree's
Cargo `target/` directory separate. Kache can share disk blocks when the store
and target directories are on the same filesystem and it supports cloning.
Set `KACHE_CACHE_DIR` before entering the shell to use another volume.

Blaze is opt-in. Set `perSystem.rust.blaze.enable = true;` in a consumer
flake to add Blaze on Apple silicon macOS. With both tools enabled, Kache's
Cargo shim routes eligible local commands to Blaze. With Kache disabled,
run `blaze build` directly. Nix supplies Blaze's matching nightly and
standard library sources to the Blaze launchers.
Update the Blaze release and its nightly together using the upstream
`harness/toolchain` pin. The project shell and Crane select their Rust
toolchain independently. Blaze
keeps a separate cache for the workspace code it compiles. Kache still
caches compatible compiler invocations such as dependency builds. Release
builds and CI use Cargo. Crane uses the project's selected Rust toolchain.

Use `KACHE_BLAZE=0 cargo build` to build with Cargo while retaining Kache.
Use `kache doctor` to inspect the setup and `kache stats` to inspect cache
activity. Kache's budget applies to its artifact store. Large worktrees can
still use additional disk space for active targets and Blaze's cache.
