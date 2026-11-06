# Inspected implementations

Observed on 2026-10-28. These are examples to learn from; inspect the target
checkout again before applying a policy. Namespaces and layouts are not defaults.

| Project | Code filter / remote | Payload layout |
| --- | --- | --- |
| nanobrush | `nanobrush-code`; `hf` → `git@hf.co:nmarshall/nanobrush` | Same repository: `assets/**`, root `references/**` and nested `**/references/**` use LFS, including small reference text. |
| urban-terror-rs | `urt-code`; `hf` → `git@hf.co:nmarshall/urt-rs` | Same repository: `assets/**` uses LFS, including original shader/config text. Cached original installation files are forbidden as tracked assets. |
| Glade | `glade-code`; `hf` → `git@hf.co:nmarshall/mini-gl` | Code repo rejects assets and ignores `/assets/`. `scripts/assets.py` manages a **separate dataset Git checkout** there, with its own origin, attributes, local config and hooks. |

In each source checkout, read `.gitattributes`, `scripts/storage_policy.py`,
`scripts/setup-repository.py`, `.githooks/pre-commit`, `.githooks/pre-push`,
`flake.nix`, and effective/local Git filter settings. The policies check UTF-8,
NULs, misplaced asset extensions/directories, unexpected pointers and a 2 MiB code
limit. These are repository policies, not Hugging Face limits. Index validators
check object content and attributes; push validators inspect new commit trees,
including files deleted by later commits. Nanobrush and Urban Terror spool
pre-push stdin for both policy and LFS. Urban Terror hooks require its Nix-shell
`PYTHON`; don't copy that interpreter constraint into unrelated projects.

The setup scripts resolve their own checkout and interpreter at runtime, install
required local code clean filters, and select `.githooks`. Mixed repositories
also install local LFS filters and Xet registration. Existing code checks local
hooksPath before changing it; a reusable setup must additionally consider
inherited hooksPath and active default hooks. Local absolute paths observed in
`.git/config` are runtime products, never portable source configuration.

Glade's `config/asset-repository.gitattributes` makes every asset payload LFS,
including JSON/RON/text; only root `.gitattributes`, `.gitignore` and `README.md`
are ordinary Git metadata. `assets.lock.json` pins repo ID, type, checkout and
revision. Its `scripts/assets.py` verifies fetch/push URLs against the lock,
configures local LFS/Xet and asset hooks, supports explicit private-dataset
creation, and fetches/checks pinned revisions. Asset pre-push runs `push-assets`
and `git lfs pre-push` on the same stdin. Push asset commits before pinning them
in code Git. Glade code pre-push only needs its code history guard because assets
are in the other repository. Do not assume its asset origin uses the code repo's
SSH URL: the manager constructs a verified HTTPS **dataset** URL.
At inspection time the asset lock's `repo_id` and `revision` were both `null`
and no local `assets/.git` existed. The separate asset layout is implemented but
had not been initialized in this checkout; no actual dataset identity, visibility,
local asset filter configuration or uploaded payloads were verified.

Archive retention is a separate invariant for new work: original archives belong
in Xet and the unpacked installation only in ignored `.cache/<name>/`, reproduced
by flake commands. Existing curated/extracted references do not establish a rule
to commit whole unpacked game installations.

## Nix integration

`features/cli/cli-tools.p.nix` already provides `pkgs.git-lfs` and git-xet from
the existing unstable nixpkgs input, enables `programs.git.lfs`, and sets:

```gitconfig
[lfs]
    concurrenttransfers = 8
[lfs "customtransfer.xet"]
    path = git-xet
    args = transfer
    concurrent = true
```

It also sets a global hooksPath, so never inspect only local config. Reuse this
tooling and verify effective settings with `--show-origin`. No package addition
or global installer is required for this skill.

`features/ai-agents/skills.nix` discovers directories containing `SKILL.md` in
`features/ai-agents/skills/` and exposes each whole directory through Home
Manager as `~/.agents/skills/<name>`. The `agent-skills` / `agent-tooling` module
imports that collector. Add skill sources here, stage them before Git-flake
evaluation, and use the normal nix-home rebuild to activate them. Do not write
the skill directly into the global home directory.
