---
name: commit-messages
description: Commit completed implementation stages after relevant checks pass, including documentation updates and extremely terse, affected-area subjects. Use when finishing an implementation stage or preparing a Git commit.
---

# Commit messages

Commit after each completed implementation stage, once its relevant checks pass. Include the stage's documentation updates in the commit.

Follow the recent repository history: `<short affected area>: <extremely terse description>`.

- Use the affected component, provider, or topic as the prefix, such as `docs`, `workspace`, `cli`, `migrations`, `data model`, `nexo`, `kraken`, or `evm-chains`.
- Keep the description short and specific. Use lowercase by default and omit the final period.
- Prefer the affected area over generic prefixes like `feat` or `fix`. Put essential rationale in the body when needed, rather than lengthening the subject.

Examples from the history: `docs: implementation plan`, `kraken: balance reconciliation`, `migrations: run at start + idempotent`, and `evm-chains: exclude spam tokens`.

## Commit state

Use git mv (or git add -A) so moves register as renames, and always check git status before committing.
