"""Exercise the launcher's process lifecycle without launching a browser."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

LAUNCHER = sys.argv.pop(1)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="brave-launch-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.cache = self.root / "cache with spaces"
        self.cache.mkdir()
        self.pending = self.cache / "pending.json"
        self.trace = self.root / "events"
        self.arguments = self.root / "arguments"
        self.helper = self.root / "fake sync"
        self.browser = self.root / "fake browser"
        self.write(self.helper, r'''
printf 'apply\n' >> "$TEST_TRACE"
if [ "${TEST_SYNC_FAIL:-0}" = 1 ]; then exit 9; fi
rm -f "$BRAVE_SETTINGS_STATE_DIR/pending.json"
''')
        self.write(self.browser, r'''
printf 'browser\n' >> "$TEST_TRACE"
printf '%s\0' "$@" > "$TEST_ARGUMENTS"
if [ "${TEST_QUEUE_DURING_RUN:-0}" = 1 ]; then
  printf '{}' > "$BRAVE_SETTINGS_STATE_DIR/pending.json"
fi
if [ "${TEST_TERMINATE_SELF:-0}" = 1 ]; then kill -TERM "$$"; fi
exit "${TEST_BROWSER_STATUS:-0}"
''')

    def write(self, path, text):
        path.write_text("#!/bin/sh\nset -eu\n" + text)
        path.chmod(0o755)

    def run_browser(self, **settings):
        env = dict(os.environ, BRAVE_SETTINGS_SYNC=str(self.helper),
                   BRAVE_SETTINGS_STATE_DIR=str(self.cache),
                   BRAVE_SETTINGS_DATA_DIR=str(self.root / "profile with spaces"),
                   BRAVE_SETTINGS_BROWSER=str(self.browser),
                   TEST_TRACE=str(self.trace), TEST_ARGUMENTS=str(self.arguments))
        env.update(settings)
        return subprocess.run(["bash", LAUNCHER, "--example", "argument with spaces"],
                              env=env, capture_output=True, text=True, timeout=10)

    def events(self):
        return self.trace.read_text().splitlines()

    def test_no_pending_work_only_runs_browser(self):
        result = self.run_browser()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), ["browser"])
        self.assertEqual(self.arguments.read_bytes(), b"--example\0argument with spaces\0")
        self.assertFalse((self.cache / "brave-settings.log").exists())

    def test_applies_before_start_and_after_work_queued_during_run(self):
        self.pending.write_text("{}")
        result = self.run_browser(TEST_QUEUE_DURING_RUN="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), ["apply", "browser", "apply"])
        self.assertFalse(self.pending.exists())

    def test_browser_failure_still_runs_post_hook_and_preserves_status(self):
        result = self.run_browser(TEST_QUEUE_DURING_RUN="1", TEST_BROWSER_STATUS="17")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(self.events(), ["browser", "apply"])

    def test_apply_failure_does_not_block_browser_or_hide_its_status(self):
        self.pending.write_text("{}")
        result = self.run_browser(TEST_SYNC_FAIL="1", TEST_BROWSER_STATUS="19")
        self.assertEqual(result.returncode, 19)
        self.assertEqual(self.events(), ["apply", "browser", "apply"])
        self.assertTrue(self.pending.exists())
        self.assertIn("remain queued", result.stderr)

    def test_terminated_child_still_runs_post_hook(self):
        result = self.run_browser(TEST_QUEUE_DURING_RUN="1", TEST_TERMINATE_SELF="1")
        self.assertEqual(result.returncode, 143)
        self.assertEqual(self.events(), ["browser", "apply"])

    def test_deleted_cache_does_not_prevent_launch(self):
        self.cache.rmdir()
        result = self.run_browser()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), ["browser"])
        self.assertFalse(self.cache.exists())

    def test_waits_for_child_before_applying_new_work(self):
        self.write(self.browser, r'''
printf 'browser\n' >> "$TEST_TRACE"
read -r release
''')
        env = dict(os.environ, BRAVE_SETTINGS_SYNC=str(self.helper),
                   BRAVE_SETTINGS_STATE_DIR=str(self.cache),
                   BRAVE_SETTINGS_DATA_DIR=str(self.root / "profile"),
                   BRAVE_SETTINGS_BROWSER=str(self.browser),
                   TEST_TRACE=str(self.trace))
        with subprocess.Popen(["bash", LAUNCHER], env=env, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
            deadline = time.monotonic() + 5
            while not self.trace.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.trace.exists())
            self.pending.write_text("{}")
            self.assertIsNone(child.poll())
            self.assertEqual(self.events(), ["browser"])
            _, stderr = child.communicate(b"close\n", timeout=5)
            self.assertEqual(child.returncode, 0, stderr)
        self.assertEqual(self.events(), ["browser", "apply"])
        self.assertFalse(self.pending.exists())


if __name__ == "__main__":
    unittest.main()
