# Shared Zellij launchers

Every `l.mkZmux` consumer has a single-row shortcut bar: an **F1 keymaps** chevron first, followed by the classic mode-aware Zellij status bar: **Ctrl+** once, then **g lock · p pane · t tab · n resize · h move · s search · o session · q quit**, each in its own chevron. There is no separate help/footer row. F1 uses a fixed fourteen-column segment. Classic mode shows effect labels when they fit and removes the default one-line UI’s trailing ribbon/ellipsis. On narrow terminals Zellij may shorten labels to fit; F1 always opens the full list.

Press **F1** to open the floating keyboard-shortcut list. It lists my-nix overrides and every binding from the packaged Zellij defaults, grouped by input mode. Arrow keys and Page Up/Down scroll; `/` searches; `q` closes help. The help command switches to Normal mode so the pager controls work even when opened from another mode. That switch deliberately lives in the command rather than the F1 binding: including F1 among Zellij’s mode-switch keys would prevent its status bar from recognizing Ctrl as the common modifier.

The first entry explains that **Ctrl+Q quits the current session and terminates all its tabs and their processes**, leaving other sessions alone. In Locked mode, Ctrl+G unlocks first. Ctrl+Q retains Zellij's default binding. Alt+Up/Down select tabs, and Alt+S toggles sidebar selectability.

The list is generated at build time from the same Zellij package used by the launcher; commented-out bindings are omitted. Custom F1/Alt+S/Alt+Up/Alt+Down replace their default entries in the list. Remaining action names are Zellij's own names. Rebuild/reload the consuming Nix shell and start a new session to receive layout changes; already-running sessions retain their layout.
