"""Tests for modules/sync-agents-md.py (stdlib only, run with python3)."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent.parent / "modules" / "sync-agents-md.py"
sys.path.insert(0, str(SCRIPT.parent))
import importlib.util

spec = importlib.util.spec_from_file_location("sync_agents_md", SCRIPT)
sync_agents_md = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_agents_md)


def block(name, content):
    return (
        f"<!-- my-nix:agents-fragment:start {name} -->\n"
        f"{content}\n"
        f"<!-- my-nix:agents-fragment:end {name} -->"
    )


class SyncTextTest(unittest.TestCase):
    def test_creates_file_content_from_nothing(self):
        self.assertEqual(
            sync_agents_md.sync_text("", {"git": "## Git\n\nUse squash."}),
            block("git", "## Git\n\nUse squash.") + "\n",
        )

    def test_idempotent(self):
        text = "# Project\n\nMine.\n\n" + block("git", "## Git") + "\n\nTail.\n"
        self.assertEqual(sync_agents_md.sync_text(text, {"git": "## Git"}), text)

    def test_preserves_manual_content_and_updates_in_place(self):
        text = (
            "# Project\n\nManual intro.\n\n"
            + block("git", "## Git\n\nOld.")
            + "\n\nManual between.\n\n"
            + block("rust", "## Rust\n\nOld.")
            + "\n\nManual tail."
        )
        updated = sync_agents_md.sync_text(text, {"git": "## Git\n\nNew.", "rust": "## Rust"})
        self.assertEqual(
            updated,
            "# Project\n\nManual intro.\n\n"
            + block("git", "## Git\n\nNew.")
            + "\n\nManual between.\n\n"
            + block("rust", "## Rust")
            + "\n\nManual tail.",
        )

    def test_appends_missing_in_name_order_after_manual_tail(self):
        text = "# Project\n\nManual tail.\n"
        self.assertEqual(
            sync_agents_md.sync_text(text, {"zeta": "Z", "alpha": "A"}),
            text + "\n" + block("alpha", "A") + "\n\n" + block("zeta", "Z") + "\n",
        )

    def test_removes_stale_fragment_keeps_manual_content(self):
        text = "Before.\n\n" + block("gone", "Old") + "\n\nAfter.\n"
        self.assertEqual(
            sync_agents_md.sync_text(text, {"kept": "K"}),
            "Before.\n\n\nAfter.\n\n" + block("kept", "K") + "\n",
        )

    def test_normalizes_surrounding_blank_lines_in_fragment(self):
        self.assertEqual(
            sync_agents_md.sync_text("", {"a": "\n\n## A\n\n\n"}),
            block("a", "## A") + "\n",
        )

    def test_preserves_missing_trailing_newline_when_unchanged(self):
        text = "Manual, no trailing newline"
        self.assertEqual(sync_agents_md.sync_text(text, {"a": "## A"}), text + "\n\n" + block("a", "## A") + "\n")

    def test_crlf_is_preserved(self):
        updated = sync_agents_md.sync_text("Manual.\r\n", {"a": "## A"})
        self.assertIn("\r\n", updated)
        self.assertNotIn("\n", updated.replace("\r\n", ""))

    def test_unterminated_marker_is_an_error(self):
        with self.assertRaises(ValueError):
            sync_agents_md.sync_text("<!-- my-nix:agents-fragment:start a -->\ncontent\n", {"a": "x"})

    def test_orphan_end_and_duplicates_are_errors(self):
        for text in (
            "<!-- my-nix:agents-fragment:end a -->\n",
            block("a", "x") + "\n" + block("a", "y") + "\n",
            "<!-- my-nix:agents-fragment:start a -->\n<!-- my-nix:agents-fragment:start b -->\n",
        ):
            with self.assertRaises(ValueError, msg=text):
                sync_agents_md.sync_text(text, {"a": "x", "b": "y"})

    def test_empty_fragment_is_an_error(self):
        with self.assertRaises(ValueError):
            sync_agents_md.sync_text("", {"a": "  \n\n"})


class SyncFileTest(unittest.TestCase):
    def run_sync(self, repo, fragments, filename="AGENTS.md"):
        fragments_file = repo / "fragments.json"
        fragments_file.write_text(json.dumps(fragments), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(repo), str(fragments_file), filename],
            capture_output=True,
            text=True,
        )
        return result

    def test_syncs_file_and_rerun_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "AGENTS.md").write_text("# Mine\n\nManual.\n", encoding="utf-8")
            result = self.run_sync(repo, {"git": "## Git"})
            self.assertEqual(result.returncode, 0, result.stderr)
            first = (repo / "AGENTS.md").read_bytes()
            self.assertEqual(
                first.decode(),
                "# Mine\n\nManual.\n\n" + block("git", "## Git") + "\n",
            )
            result = self.run_sync(repo, {"git": "## Git"})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / "AGENTS.md").read_bytes(), first)

    def test_bad_marker_leaves_file_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            broken = "# Mine\n\n<!-- my-nix:agents-fragment:start git -->\nunterminated\n"
            (repo / "AGENTS.md").write_text(broken, encoding="utf-8")
            result = self.run_sync(repo, {"git": "## Git"})
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((repo / "AGENTS.md").read_text(encoding="utf-8"), broken)

    def test_symlinked_file_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            real = repo / "real.md"
            real.write_text("# Real\n", encoding="utf-8")
            os.symlink(real, repo / "AGENTS.md")
            result = self.run_sync(repo, {"git": "## Git"})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(real.read_text(encoding="utf-8"), "# Real\n")

    def test_rejects_path_like_file_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_sync(Path(tmp), {"git": "## Git"}, filename="../evil.md")
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
