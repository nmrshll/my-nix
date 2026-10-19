"""Run with python3 tests/zellij-shortcuts.py; no third-party dependencies."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "shortcuts", Path(__file__).parents[1] / "utils/zellij-shortcuts.py"
)
shortcuts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shortcuts)


class ShortcutHelp(unittest.TestCase):
    def test_quit_and_custom_keys_are_explained_without_commented_bindings(self):
        result = shortcuts.render('''keybinds {
    normal {
        // bind "Alt c" { Copy; }
        bind "Alt s" { ToggleActiveSyncTab; }
    }
    shared_except "locked" {
        bind "Ctrl q" { Quit; }
    }
}''')
        self.assertIn("terminate ALL its tabs and their processes", result)
        self.assertIn("Other Zellij sessions are unaffected", result)
        self.assertIn('SHARED EXCEPT "locked"', result)
        self.assertIn("F1", result)
        self.assertIn("Toggle whether the vertical tab sidebar", result)
        self.assertNotIn("ToggleActiveSyncTab", result)
        self.assertNotIn("Alt c", result)

    def test_nested_plugin_block_does_not_hide_following_bindings(self):
        result = shortcuts.render('''keybinds {
    session {
        bind "c" {
            LaunchOrFocusPlugin "zellij:configuration" {
                floating true
                name "A { brace }"
            }
        }
        bind "d" { Detach; }
    }
}''')
        self.assertIn('LaunchOrFocusPlugin "zellij:configuration"', result)
        self.assertIn('name "A { brace }"', result)
        self.assertIn("Detach", result)


if __name__ == "__main__":
    unittest.main()
