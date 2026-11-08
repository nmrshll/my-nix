# Web development shells

Import the module explicitly. It does **not** register itself in the
`utils`/`essentials` groups, so importing those leaves your shell unchanged —
the same opt-in-by-import shape as `rust.nix`:

```nix
imports = [ inputs.my-nix.flakeModules.web ];
```

It contributes one Node, one package manager, the environment Vite/Astro/Panda
expect, and a set of `web-*` scripts. Repo-specific `dev`, `build` and zellij
scripts keep their names: those encode project ordering (Rust API + Vite
together, a filtered app), while these are the generic operations.

## Options

| Option | Default | Purpose |
| --- | --- | --- |
| `web.nodePackage` | `pkgs.nodejs_26` (26.10.0 on nixpkgs 26.05) | Node for every package-manager call |
| `web.packageManager` | `"pnpm"` | `"pnpm"`, `"yarn"` or `"bun"` |
| `web.packageManagerPackage` | nixpkgs package for that manager | Override the binary/version |
| `web.frozenLockfile` | `false` | `--frozen-lockfile` on installs (turn on in CI) |
| `web.managePackageManagerVersions` | `false` | Let pnpm download the `packageManager` version |
| `web.skipPlaywrightBrowserDownload` | `true` | Export `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` |
| `web.extraPackages` | `[ ]` | Additional toolchain packages |
| `web.apps` | `{ }` | Named apps: `{ dir; port ? null; }` |
| `web.portHashSeed` | `""` | Seed for the port hash; empty uses package.json `name` |
| `web.portBase` | `20000` | First port of the hash band (always ends at 49151) |
| `web.ports` | derived (read-only) | Resolved `app → port` table |
| `web.appNames` | derived (read-only) | Apps found in the repo, name-sorted |

## Scripts

| Script | Runs |
| --- | --- |
| `web-install` | `install` for the selected manager |
| `web-codegen` | the `codegen` script in every workspace package |
| `web-typecheck` | the `typecheck` script in every workspace package |
| `web-build` | the `build` script in every workspace package |
| `web-check` | codegen → typecheck → build, in that order |
| `web-dev [name]` | installs, then `dev` in a declared app |
| `web-ports` | the resolved app → directory → port table |
| `web-stop` | stops Astro `dev`/`preview` servers in the declared apps |

`web-check` keeps the codegen-first order because `tsc` cannot resolve the
generated `styled-system` imports before codegen runs. `web-dev` installs first
so a server never starts against stale `node_modules`.

Per-manager differences: `pnpm` runs workspace scripts with
`-r --if-present` (the design system has `codegen`, a site does not, and a
recursive run without the flag fails on the ones that lack it); `bun` uses
`--filter '*'`; `yarn` runs the script at the root only, so a Yarn repo should
delegate the operation itself.

## App discovery and ports

Declare apps, or leave `web.apps` empty and let the module read
`pnpm-workspace.yaml`:

```nix
perSystem.web.apps = {
  docs = { dir = "apps/docs-web"; };
  app = { dir = "apps/taskstream-web"; port = 5180; };  # explicit override
};
```

The fallback expands top-level `dir/*` entries and keeps only directories
containing a `package.json`. `!` ignore patterns and deeper globs are not
supported. App names are the directory's base name.

Ports come from a per-app hash. Each app hashes `"<package.json name>/<app
name>"` into the band 20000-49151: below the ephemeral range, so an outbound
connection can never be holding a dev port, and wide enough that two unrelated
repos collide with probability ~1/29000. The repo half is stable across commits
(the flake's store path is not, it changes with every commit); the app half means
adding, renaming or removing one app leaves every other app's port alone. Ports a
browser refuses (2049, 6665-6669, ...) are filtered out, and two names that hash
to the same slot are probed forward, so a repo never hands out one port twice.

Every port is computed statically in Nix, so the dev shell exports it: `WEB_PORT_DOCS`,
`WEB_PORT_TASKSTREAM_WEB`, ... (uppercased, non-alphanumerics as `_`) and
`WEB_APP_PORTS`, a JSON object of app to port, so one app can call another
without hardcoding. `web.appNames` and `web.ports` expose the same table to Nix.
`web-dev` forwards the port (`--port` via `--` for pnpm and bun, directly for
yarn) and exports `WEB_DEV_PORT`. A directory passed explicitly that is not a
declared app starts on `web.portBase`. Override one app with `apps.<name>.port`,
or move the whole band with `web.portBase`.

`web-stop` exists because Astro records a running `dev`/`preview` in
`.astro/*.json` and refuses a second one; a stale preview is worse, because a
Playwright suite reuses it and tests the previous build.

## Which conflicting implementation this picks

| Conflict | Observed before | Module |
| --- | --- | --- |
| Node version | `nodejs_22`, `nodejs` (24.21), `nodejs_26` | `pkgs.nodejs_26`, overridable |
| pnpm attribute | `pkgs.pnpm` vs `pkgs.nodePackages.pnpm` | `pkgs.pnpm` |
| pnpm version source | `packageManager: pnpm@11.25.0`/`11.27.0`, nixpkgs 11.27.0 | The flake's pnpm; self-download disabled |
| Install timing | inside repo `dev` scripts | Inside `web-dev` (and `web-install`) |
| Package manager | pnpm everywhere except one yarn repo | First-class `pnpm`/`yarn`/`bun` |
| Script surface | hand-written `astro`, `dev-stop`, `web`, `ts-web` | `web-*` only; repo aliases untouched |
| Enablement | n/a | Opt in by importing `flakeModules.web` |
| App list | hardcoded directory names in scripts | `web.apps`, else parsed workspace |
| Ports | hardcoded 4321/4322/5173/5174/5180 | Per-app hash into 20000–49151, overridable |

`COREPACK_ENABLE_STRICT=0` and (for pnpm)
`NPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS=false` are exported so the shell
cannot silently fetch a manager other than the one Nix provides.
