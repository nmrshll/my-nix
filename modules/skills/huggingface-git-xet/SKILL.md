---
name: huggingface-git-xet
description: Set up or audit Hugging Face as a general-purpose Git remote, keeping code in Git and repository-defined assets in Xet-backed Git LFS, with clone setup, hooks, history checks and reproducible archive unpacking.
---

# Hugging Face Git and Xet

Use the repository's storage policy, not file size or text detection alone.
Source code, scripts, documentation and manifests stay ordinary Git blobs.
Assets, reference payloads, binaries and large non-code files use Git LFS backed
by Xet. Small textual reference assets can require LFS too. Distinguish authored
documentation/manifests from reference copies with the same extension.

Two mechanisms cooperate:

- A **required custom code clean filter** validates code paths on `git add` and
  returns accepted bytes unchanged. It rejects misplaced payloads, binary data,
  LFS pointers and policy size violations. It does not upload anything.
- **Git LFS** replaces asset contents with pointers in Git and retains the real
  contents in its object store. Its pre-push hook uploads them; the
  `lfs.customtransfer.xet` agent negotiates Xet transfers with the Hub. Continue
  to use `filter=lfs`; do not invent a `filter=xet` driver. A pointer or registered
  agent alone does not prove that a remote upload used Xet.

## Inspect before editing

Read repository instructions and existing storage/setup scripts first. Read
[references/projects.md](references/projects.md) for the inspected nix-home
configuration and the distinct nanobrush, urban-terror-rs and Glade layouts.
Preserve an established split between code and asset repositories.

Run from each relevant checkout (including a separate asset checkout):

```sh
git status --short
git remote -v
git config --show-origin --get-regexp '^(remote\.|filter\.|lfs\.|core\.(hooksPath|attributesFile))'
git rev-parse --git-path hooks
git rev-parse --git-common-dir
git ls-files --stage -z
git lfs ls-files --all --long
git lfs env
```

Config queries return 1 when no matching keys exist. Inspect root and nested
`.gitattributes`, `.git/info/attributes`, global attributes, effective hooks and
default Git hooks, executable bits, `.gitignore`, lock files and flake commands.
Check fetch **and** push URLs, URL rewrites, LFS endpoint overrides, skip-smudge,
`lfs.basictransfersonly` and `lfs.standalonetransferagent`. Do not print credentials.
Use NUL-delimited listings when processing paths. Compare tracked index objects
with the worktree; a materialized LFS file in the worktree is normal.

## Establish the destination and scope

Obtain namespace, repository name, Hub type (`model`, `dataset`, `space`) and
visibility from the task or verified account/repository context. The observed
`git@hf.co:nmarshall/<repo>` URLs are examples, not defaults for new tasks. If
needed, use available account tools or `hf auth whoami`; verify organization
membership separately. Authentication and SSH-key registration are prerequisites.

For a **verified** destination, add `hf` only if absent:

```sh
git remote add hf "$verified_url"
git remote get-url --all hf
git remote get-url --push --all hf
```

If `hf` exists, compare both URL sets and reuse a match. Resolve a mismatch before
changing it. Preserve `origin`, other remotes, push defaults and upstream branches
unless the task requests a change. SSH URL forms are
`git@hf.co:NAMESPACE/NAME` (model),
`git@hf.co:datasets/NAMESPACE/NAME` and
`git@hf.co:spaces/NAMESPACE/NAME`; verify against the actual Hub clone URL.

Adding a local remote does **not** create a Hub repository, set visibility, upload
assets or push commits. Create a Hub repository only within the task's authorized
scope, using the Hub UI or available Hub API/CLI with explicit type and visibility
(inspect the installed CLI help). Verify an existing repository's actual
visibility; an `exist_ok` creation call does not establish or change it. Account
context can verify identity but does not choose visibility. Push only when the
task authorizes publishing. Setup helpers must not create repositories or push.

## Encode the policy and install clone setup

Reuse nix-home's Nix-managed Git LFS/git-xet and global transfer configuration;
do not install tools through curl, pip or Homebrew, or rewrite global Git config.
Use the target project's Nix shell for its Python/archive tools. Verify
`git lfs version`, `git xet --version` and effective configuration. Missing tooling
belongs in Nix configuration following the project's package sourcing policy.

For a mixed repository, adapt precise directory/path rules like:

```gitattributes
* text=auto eol=lf filter=repo-code
assets/** filter=lfs diff=lfs merge=lfs -text !eol
references/** filter=lfs diff=lfs merge=lfs -text !eol
```

The asset exceptions follow the default code rule; `!eol` clears inherited EOL
conversion. Include nested reference directories only if policy calls for them.
Avoid blanket `*.json`, `*.txt`, `*.shader` or size-only rules that capture code
or omit textual assets. Preserve relevant Hub-generated rules, reconciling their
precedence with code policy. In an asset-only repository use an LFS default with
explicit ordinary-Git exceptions for repository metadata and maintenance scripts.
Keep classification in attributes and the validator consistent.

The small [policy template](templates/storage_policy.py) and
[setup template](templates/setup_repository.py) form a tested starting point for
a **mixed** repository. Copy them to `scripts/storage_policy.py` and
`scripts/setup_repository.py`, adapt their policy constants to the repository,
then run `python3 scripts/setup_repository.py`. Do not replace working project
implementations or copy their asset suffix inventories wholesale. The templates
reject symlinks/submodules pending an explicit project policy and scan history
using the current classification. Adapt deliberately if those are required.

Commit an idempotent setup command and expose it through the repository flake
(for example `nix develop -c python3 scripts/setup_repository.py` or a flake app).
Cloning transfers attributes and hook source files, **not** local filter drivers
or hook activation. Run setup after each clone or move and after runtime changes.
Only activate hooks after reviewing their source. Required local settings are:

```gitconfig
[filter "repo-code"]
    clean = <Nix-shell Python and repository policy script> clean -- %f
    smudge = cat
    required = true
```

Keep `%f` as a separate argument; Git quotes its substitution. Resolve/quote paths
at setup time, never commit machine paths. Ensure no competing code `process`
filter overrides `clean`. Accept effective Nix-managed `filter.lfs` clean,
smudge, process and required settings; when missing, bootstrap only locally with
`git lfs install --local --skip-repo`. Likewise use `git xet install --local` only
if effective Xet settings are missing. Expect `path=git-xet`, `args=transfer`,
`concurrent=true`; allow custom transfers with `lfs.basictransfersonly=false`.
Do not force the standalone transfer agent or disable lock verification globally.

Preserve existing hooks and hook managers. Inspect inherited `core.hooksPath`
as well as local settings and `.git/hooks` before switching directories. The setup
template refuses to hide active hooks or overwrite differing target hooks; merge
their behavior into the project's existing manager/dispatcher instead. Preserve
exit failures and arguments. Every consumer of pre-push stdin needs the same
four-field ref-update records: spool once to a temporary file and replay it to
existing validators, the history guard, and `git lfs pre-push "$@"`. A pipeline
or sequential reads of the original stdin loses records. Run validation before
uploading, and avoid calling LFS twice if the existing hook already does so.

## Retain archives, unpack only into the cache

For an archived game, keep the **original archive** as an LFS/Xet payload in the
chosen asset repository. Keep its unpacked installation only at
`<repo>/.cache/<unpacked_dir_name>/`, ignored and untracked. Do not commit the
unpacked tree to ordinary Git or LFS. Separate, intentionally curated reference
assets may follow their own documented policy; they are not another full copy of
the installation. Existing extracted trees are findings to reconcile with the
task, not a reason to silently rewrite history.

Ensure the repository's **nix flake exposes commands to unpack the original
archives**, using Nix-provided extractors and a committed unpack script/manifest.
Document the actual `nix run .#unpack-game` (or equivalent) command. It must:

- Locate/fetch the original LFS content at the pinned asset revision and verify
  its checksum; reject an unresolved LFS pointer or missing archive.
- Derive the checkout root at runtime, extract only into the named `.cache`
  directory, reject traversal/absolute paths and unsafe symlinks, and avoid
  modifying archive sources or an unrelated existing cache directory.
- Be repeatable: use a temporary cache directory and a checksum/version marker;
  reuse a complete matching extraction and replace only its own stale output.

Keep archive identity, checksum and unpack instructions in ordinary Git manifests.
Do not embed a local cache path into Nix's source snapshot or implicitly download
or unpack on unrelated evaluation. Validate by deleting only the test cache and
recreating it with the flake command; verify `.cache` is ignored and untracked.

## Verify index and all history intended for push

After setup, stage attributes and explicitly selected paths. For already tracked
files, review `git add --renormalize -- <policy paths>` and inspect its staged
diff. This changes the index for the next commit; it does not migrate old commits.

```sh
python3 scripts/storage_policy.py check
git check-attr --cached filter diff merge text eol -- src/main.rs assets/sample.bin references/sample.txt
git show :src/main.rs
git show :references/sample.txt
git lfs ls-files --long
git lfs fsck
python3 scripts/storage_policy.py history HEAD
```

Use paths that actually exist. Verify **index blobs** (`git show :path` or
`git cat-file blob <index-oid>`), not just attributes or `git lfs ls-files`:
code is ordinary text and not an LFS pointer; every nonempty asset, including
tiny textual assets, is a valid LFS pointer with `oid sha256` and `size` fields.
LFS defines an empty asset as its own empty pointer. Confirm asset attributes
include `filter=lfs diff=lfs merge=lfs -text` with no inherited EOL conversion.

Before an initial push, inspect **every reachable commit** of every proposed
branch/tag, including payloads since deleted or renamed. Run the template's
`history <ref>...` with the exact refs (`history` alone scans `--all`), or equivalent
project policy checks; the pre-push guard checks new reachable history too.
Supplement with `git rev-list --objects --all` / `git cat-file --batch-check` and
read-only `git lfs migrate info --everything`. Size reports alone miss small text
payloads. Check shallow/partial history and missing objects; fetch complete
history before claiming an audit. A clean tip is insufficient.

If raw payloads already occur in history, report paths, commits, sizes and affected
refs; stop the push until resolved. Attributes and a cleanup commit do not remove
the older objects. Do not run `git lfs migrate import`, `git filter-repo`, rebase,
reset shared history or force-push without **explicit authorization for the
rewrite**. Present scope, backups/ref mapping and collaborator impact first.
After an authorized migration, rerun index/history/LFS checks for all selected
refs. Without rewrite authorization, leave history intact and report the blocker.

Within an authorized publishing task, push explicit reviewed refs to `hf` through
the combined hook. Inspect extra refs selected by Git configuration (such as
follow-tags). Verify advertised remote OIDs and, when feasible, a fresh clone
with setup, LFS download and integrity checks. A dry run or local test is not
evidence of a successful upload. Do not claim Xet transfer without transfer/Hub
evidence. Report separately: files/config/hooks changed; remote added/reused;
Hub repository created and actual type/visibility; index conversion versus
history migration; refs/OIDs pushed; checks run, and any unverified remote state.

Validate adapted templates in an isolated temporary Git repository; the bundled
`python3 tests/test_templates.py` exercises code, binary/text assets, setup
idempotency, hook conflicts, bypassed filters and deleted historical payloads
without contacting Hugging Face. Local guards can be bypassed, so retain policy
checks in CI/review as appropriate.

Upstream details: [Git attributes](https://git-scm.com/docs/gitattributes),
[Git LFS filters](https://github.com/git-lfs/git-lfs/blob/main/docs/spec.md),
[Xet transfer agent](https://github.com/huggingface/xet-core/blob/main/git_xet/README.md),
[Hub repository management](https://huggingface.co/docs/huggingface_hub/guides/repository).
