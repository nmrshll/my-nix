# Shared Zellij launchers

Every `l.mkZmux` consumer has a single-row shortcut bar: an **F1 keymaps** chevron first, followed by the classic mode-aware Zellij status bar (Ctrl+G lock, Ctrl+P pane, Ctrl+T tab, Ctrl+N resize, Ctrl+H move, Ctrl+S scroll, Ctrl+O session, Ctrl+Q quit). There is no separate help/footer row. F1 uses a fixed fourteen-column segment. Classic mode shows effect labels when they fit and removes the default one-line UI’s trailing ribbon/ellipsis. On narrow terminals Zellij may shorten labels to fit; F1 always opens the full list.

Press **F1** to open the floating keyboard-shortcut list. It lists my-nix overrides and every binding from the packaged Zellij defaults, grouped by input mode. Arrow keys and Page Up/Down scroll; `/` searches; `q` closes help. F1 switches to Normal mode so the pager controls work even when opened from another mode.

The first entry explains that **Ctrl+Q quits the current session and terminates all its tabs and their processes**, leaving other sessions alone. In Locked mode, Ctrl+G unlocks first. Ctrl+Q retains Zellij's default binding. Alt+Up/Down select tabs, and Alt+S toggles sidebar selectability.

The list is generated at build time from the same Zellij package used by the launcher; commented-out bindings are omitted. Custom F1/Alt+S/Alt+Up/Alt+Down replace their default entries in the list. Remaining action names are Zellij's own names. Rebuild/reload the consuming Nix shell and start a new session to receive layout changes; already-running sessions retain their layout.
