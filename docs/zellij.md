# Shared Zellij launchers

Every `l.mkZmux` consumer has a persistent footer: **F1: keyboard shortcuts | Ctrl+Q: quit session + all tabs**.

Press **F1** to open the floating keyboard-shortcut list. It lists my-nix overrides and every binding from the packaged Zellij defaults, grouped by input mode. Arrow keys and Page Up/Down scroll; `/` searches; `q` closes help. F1 switches to Normal mode so the pager controls work even when opened from another mode.

The first entry explains that **Ctrl+Q quits the current session and terminates all its tabs and their processes**, leaving other sessions alone. In Locked mode, Ctrl+G unlocks first. Ctrl+Q retains Zellij's default binding. Alt+Up/Down select tabs, and Alt+S toggles sidebar selectability.

The list is generated at build time from the same Zellij package used by the launcher; commented-out bindings are omitted. Custom F1/Alt+S/Alt+Up/Alt+Down replace their default entries in the list. Remaining action names are Zellij's own names. Rebuild/reload the consuming Nix shell and start a new session to receive layout changes; already-running sessions retain their layout.
