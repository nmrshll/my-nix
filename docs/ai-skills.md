# AI skills in development shells

Import `my-nix.flakeModules.ai-skills` in a project flake to enable skill
installation. The project and any modules it imports can contribute to
`aiSkills.skills`.

```nix
imports = [ my-nix.flakeModules.ai-skills ];
aiSkills.skills.review = ./skills/review;
```

A skill source is a directory containing `SKILL.md` and any supporting files.
Track those files in Git so Nix includes them in the flake source. Use a
distinct name for each skill contributed by a module.

Enter the default dev shell from the consumer's Git worktree, with the
consumer's `flake.nix` at the worktree root. The hook copies missing
directories into `.agents/skills/` in that worktree. If a global skill
directory contains exactly the same files, byte for byte, the hook skips the
skill directory and the agent can use the global copy. A skill that differs
in any supporting file is copied. Each installed copy is writable and can be
tracked as part of the project. Existing entries are preserved,
including local edits and symlinks. To refresh a copy, move it aside and
re-enter the shell. To turn off the hook, set `aiSkills.enable = false`.

After copying, the hook reads the frontmatter names of skills under the
worktree root's `.agents/skills/`. It adds path-specific disable rules to
`.codex/config.toml` for matching skills in `~/.agents/skills/`, Codex's
user and bundled skill directories, and `/etc/codex/skills/`. The
generated paths are machine-specific,
so keep those entries out of shared commits. Existing settings and manually
written rules stay in the file. The hook replaces only its own rules, including
removing stale rules when a local skill is removed or renamed.

Run `sync-ai-skills` from the dev shell after editing skill metadata or when
direnv reuses a cached environment. Project config requires a trusted
checkout. Some Codex clients read the project config but apply skill
disable rules only when passed at launch. In that case, start the CLI
with `codex-local-skills` from the dev shell. It syncs the rules and passes
them to that Codex process. An already running desktop client uses its own
configuration.

## Managing fragments in the agents file

The same module can manage named markdown fragments inside the project's
agents file (`AGENTS.md` by default). Modules and projects contribute
fragments through `aiSkills.agentsMd.fragments`, either as inline markdown
or as a path to a markdown file tracked in Git:

```nix
imports = [ my-nix.flakeModules.ai-skills ];

aiSkills.agentsMd.fragments = {
  git-conventions = ''
    ## Git

    Use short, imperative commit messages.
  '';
  testing = ./agents/testing.md;
};
```

The `git` module contributes a `commit-messages` fragment by default, which
nudges agents to use that skill for commit subjects; consumers can override
it by setting `aiSkills.agentsMd.fragments.commit-messages` themselves.

On every dev-shell entry, the setup hook wraps each fragment in a pair of
HTML-comment markers naming it and replaces only the content between them:

```markdown
<!-- my-nix:agents-fragment:start git-conventions -->
## Git

Use short, imperative commit messages.
<!-- my-nix:agents-fragment:end git-conventions -->
```

That makes the sync idempotent and safe to rerun:

- Changed fragment content overwrites the previously managed paragraph.
- A fragment that is removed from the configuration has its markers and
  content removed on the next entry.
- A fragment that has not been seen yet is appended in name order.
- Everything outside the markers is preserved exactly, including anything
  written by hand before, between or after managed fragments, and manual
  edits *inside* a managed block are overwritten on the next entry.
- If the markers in the file are malformed (unterminated, nested or
  duplicated), the hook reports an error and leaves the file untouched
  rather than guessing. A symlinked agents file is skipped with a warning.

If the project uses the lowercase spelling, set
`aiSkills.agentsMd.file = "agents.md";` (it must be a plain file name
without directories). Set `aiSkills.agentsMd.enable = false` or
`aiSkills.enable = false` to turn the sync off. Runner: `sync-ai-skills`
reruns the same sync manually, like the skill sync.

The modules below register skills through the same option. A module that
registers skills also imports `ai-skills`, which contributes `feature-spec`.

| Module | Skills |
| --- | --- |
| `git` | `changelog`, `commit-messages` |
| `git-xet` | `huggingface-git-xet`, with references, scripts and tests |
| `frontend` | UI design, responsive layout, accessibility, static websites and chart rendering |
| `artifact-design` | `artifact-composition`, `pitch-deck` |
| `gpui` | `gpui-async` |
| `solana` | `anchor-test-surfpool`, `litesvm-test-setup` |

The Open Design skills come from the same MIT-licensed
[upstream revision](https://github.com/opencoworkai/open-codesign/tree/b94d7156bf4aeb2c79892c91dc9934911a4e3741/apps/desktop/resources/templates/skills)
that Home Manager exposes globally. Each copy includes its license.
