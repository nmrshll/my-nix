import pathlib
import plistlib
import tempfile
import unittest

from policy import apply, archive_rules, configured, decode_archive


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = pathlib.Path(self.directory.name)
        self.policy = {"preferences": {"disabled": False, "passiveMode": True},
                       "rules": {"com.apple.Safari": [{
                           "key": "com.apple.Safari", "uuid": "nix-test", "path": "/Applications/Safari.app/Contents/MacOS/Safari",
                           "name": "Safari", "action": 0, "scope": 1, "type": 3,
                           "endpointAddr": r"(?i)^([a-z0-9-]+\.)*youtube\.com$",
                           "isEndpointAddrRegex": True, "endpointPort": "*", "isDisabled": 0,
                       }]}}

    def test_archive_preserves_types_and_regex(self):
        actual = decode_archive(archive_rules(self.policy["rules"]))
        self.assertEqual(actual["com.apple.Safari"]["rules"], self.policy["rules"]["com.apple.Safari"])

    def test_refuse_running_filter_before_writing(self):
        with self.assertRaises(RuntimeError):
            apply(self.base, self.policy, True)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_isolated_profile_backup_idempotence_and_drift(self):
        old = {"currentProfile": "/old/profile", "custom": "preserved"}
        (self.base / "preferences.plist").write_bytes(plistlib.dumps(old))
        (self.base / "rules.plist").write_bytes(b"existing default rules")
        self.assertTrue(apply(self.base, self.policy, False))
        self.assertTrue(configured(self.base, self.policy))
        self.assertFalse(apply(self.base, self.policy, True))
        self.assertEqual((self.base / "rules.plist").read_bytes(), b"existing default rules")
        backup = plistlib.loads((self.base / "nix-safari-youtube-previous.plist").read_bytes())
        self.assertEqual(backup["preferences"], old)
        self.policy["preferences"]["disabled"] = True
        self.assertFalse(configured(self.base, self.policy))

    def test_gui_metadata_does_not_hide_enforcement_drift(self):
        apply(self.base, self.policy, False)
        gui = {key: [dict(item) for item in items] for key, items in self.policy["rules"].items()}
        rule = gui["com.apple.Safari"][0]
        rule.update(uuid="gui-generated", name="*", scope=None, isDisabled=None)
        path = self.base / "Profiles/nix-safari-youtube/rules.plist"
        path.write_bytes(archive_rules(gui))
        self.assertTrue(configured(self.base, self.policy))
        rule["action"] = 1
        path.write_bytes(archive_rules(gui))
        self.assertFalse(configured(self.base, self.policy))


if __name__ == "__main__":
    unittest.main()
