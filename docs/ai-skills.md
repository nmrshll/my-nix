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
directories into `.agents/skills/` in that worktree. Each copy is writable
and can be tracked as part of the project. Existing entries are preserved,
including local edits and symlinks. To refresh a copy, move it aside and
re-enter the shell. To turn off the hook, set `aiSkills.enable = false`.
