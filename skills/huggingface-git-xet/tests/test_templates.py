#!/usr/bin/env python3
"""Offline integration checks using real Git/LFS/Xet and disposable checkouts."""
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

TEMPLATES = Path(__file__).resolve().parents[1] / "templates"
ATTRS = """* text=auto eol=lf filter=repo-code
assets/** filter=lfs diff=lfs merge=lfs -text !eol
references/** filter=lfs diff=lfs merge=lfs -text !eol
"""


class Templates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hf-xet-skill-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "checkout with spaces"
        self.root.mkdir()
        self.global_config = self.base / "global.gitconfig"
        self.global_config.touch()
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("GIT_") and k != "XET_LOG_PATH"}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.global_config),
                        GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1")
        self.run_cmd("git", "init", "-b", "main")
        self.git("config", "user.name", "Skill test")
        self.git("config", "user.email", "skill@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("remote", "add", "origin", "https://example.invalid/existing")
        (self.root / "scripts").mkdir()
        for name in ("storage_policy.py", "setup_repository.py"):
            shutil.copyfile(TEMPLATES / name, self.root / "scripts" / name)
        self.write(".gitattributes", ATTRS)
        self.write(".gitignore", "/.cache/\n__pycache__/\n")

    def run_cmd(self, *args, input=None, success=True):
        result = subprocess.run(args, cwd=self.root, env=self.env, input=input,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout.decode(errors="replace"))
        return result.stdout

    def git(self, *args, **kwargs):
        return self.run_cmd("git", *args, **kwargs)

    def setup_repo(self, **kwargs):
        return self.run_cmd(sys.executable, "scripts/setup_repository.py", **kwargs)

    def policy(self, *args, **kwargs):
        return self.run_cmd(sys.executable, "scripts/storage_policy.py", *args, **kwargs)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data.encode() if isinstance(data, str) else data)

    def stage_fixture(self):
        self.write("src/main.rs", 'fn main() { println!("hello"); }\n')
        self.write("README.md", "# Fixture documentation\n")
        self.write("archives.json", '{"archive": "assets/game.zip", "unpack_to": ".cache/game"}\n')
        self.write("assets/game.zip", b"PK\0\1example archive payload")
        self.write("references/small text.txt", "tiny textual reference\r\n")
        self.write("references/empty.txt", b"")
        self.git("add", ".")

    def commit(self):
        self.git("commit", "-m", "fixture")
        return self.git("rev-parse", "HEAD").strip()

    def fake_upload_agent(self):
        # Only intercept the upload entrypoint; filters still use real Git LFS.
        real_lfs = shutil.which("git-lfs")
        self.assertIsNotNone(real_lfs)
        bindir = self.base / "bin"
        bindir.mkdir()
        self.upload_log = self.base / "upload-input"
        script = bindir / "git-lfs"
        script.write_text(
            '#!/bin/sh\nif [ "$1" = pre-push ]; then\n'
            f'  cat > {shlex.quote(str(self.upload_log))}\n'
            '  exit 0\nfi\n'
            f'exec {shlex.quote(real_lfs)} "$@"\n'
        )
        script.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]

    def test_index_and_idempotent_setup(self):
        self.setup_repo()
        config = (self.root / ".git/config").read_bytes()
        hooks = {p.name: p.read_bytes() for p in (self.root / ".githooks").iterdir()}
        self.setup_repo()
        self.assertEqual(config, (self.root / ".git/config").read_bytes())
        self.assertEqual(hooks, {p.name: p.read_bytes() for p in (self.root / ".githooks").iterdir()})
        self.assertEqual(self.global_config.read_bytes(), b"")
        self.assertEqual(self.git("remote").strip(), b"origin")
        self.stage_fixture()
        self.policy("check")
        for path in ("src/main.rs", "README.md", "archives.json", "scripts/storage_policy.py"):
            self.assertEqual(self.git("show", ":" + path), (self.root / path).read_bytes())
        for path in ("assets/game.zip", "references/small text.txt"):
            data = (self.root / path).read_bytes()
            expected = ("version https://git-lfs.github.com/spec/v1\n"
                        f"oid sha256:{hashlib.sha256(data).hexdigest()}\nsize {len(data)}\n").encode()
            self.assertEqual(self.git("show", ":" + path), expected)
        self.assertEqual(self.git("show", ":references/empty.txt"), b"")
        self.commit()
        self.git("lfs", "fsck")
        self.policy("history", "HEAD")
        self.write(".cache/game/unpacked.bin", b"local\0installation")
        self.git("check-ignore", ".cache/game/unpacked.bin")
        self.assertEqual(self.git("ls-files", ".cache"), b"")
        self.git("add", "-f", ".cache/game/unpacked.bin", success=False)

    def test_reuses_effective_managed_settings(self):
        self.git("config", "--global", "filter.lfs.clean", "git-lfs clean -- %f")
        self.git("config", "--global", "filter.lfs.smudge", "git-lfs smudge -- %f")
        self.git("config", "--global", "filter.lfs.process", "git-lfs filter-process")
        self.git("config", "--global", "filter.lfs.required", "true")
        for key, value in (("path", "git-xet"), ("args", "transfer"), ("concurrent", "true")):
            self.git("config", "--global", "lfs.customtransfer.xet." + key, value)
        # nix-home's inherited hooksPath must not cause a global write.
        self.git("config", "--global", "core.hooksPath", "$GIT_DIR/.git/hooks")
        original = self.global_config.read_bytes()
        self.setup_repo()
        self.assertEqual(original, self.global_config.read_bytes())
        self.git("config", "--local", "--get", "filter.lfs.clean", success=False)
        self.git("config", "--local", "--get", "lfs.customtransfer.xet.path", success=False)
        self.stage_fixture()
        self.policy("check")

    def test_clean_filter_rejections(self):
        self.setup_repo()
        for path, data in (("src/bad.rs", b"binary\0data"),
                           ("src/invalid.py", b"\xff"),
                           ("misplaced.zip", b"text is still an archive by policy"),
                           ("huge.txt", b"x" * (2 * 1024 * 1024 + 1)),
                           ("pointer.txt", b"version https://git-lfs.github.com/spec/v1\n")):
            with self.subTest(path=path):
                self.write(path, data)
                self.git("add", path, success=False)
        self.git("config", "filter.repo-code.clean", "false")
        self.write("ordinary.py", "print('must fail closed')\n")
        self.git("add", "ordinary.py", success=False)

    def test_raw_text_asset_bypass_is_rejected(self):
        self.setup_repo()
        self.stage_fixture()
        raw = self.git("hash-object", "-w", "--stdin", input=b"tiny raw text\n").strip().decode()
        self.git("update-index", "--add", "--cacheinfo", "100644", raw, "references/bypassed.txt")
        self.policy("check", success=False)
        self.git("commit", "-m", "must be blocked", success=False)

    def test_attribute_override_is_rejected(self):
        self.setup_repo()
        self.stage_fixture()
        self.write(".gitattributes", ATTRS + "assets/game.zip text\n")
        self.git("add", ".gitattributes")
        self.policy("check", success=False)

    def test_hook_conflicts_preserve_files_and_configuration(self):
        for location in (".git/hooks/pre-push", ".githooks/pre-push", "shared-hooks/pre-commit"):
            with self.subTest(location=location):
                if location.startswith("shared"):
                    self.git("config", "--global", "core.hooksPath", str(self.root / "shared-hooks"))
                self.write(location, "#!/bin/sh\necho existing hook\n")
                hook = self.root / location
                hook.chmod(0o755)
                original = hook.read_bytes()
                config = (self.root / ".git/config").read_bytes()
                self.setup_repo(success=False)
                self.assertEqual(hook.read_bytes(), original)
                self.assertEqual((self.root / ".git/config").read_bytes(), config)
                hook.unlink()

    def test_pre_push_replays_records_and_blocks_deleted_payload_history(self):
        self.setup_repo()
        self.stage_fixture()
        good = self.commit()
        self.fake_upload_agent()
        record = b"refs/heads/main " + good + b" refs/heads/main " + b"0" * 40 + b"\n"
        self.run_cmd(".githooks/pre-push", "hf", "https://example.invalid/hf", input=record)
        self.assertEqual(self.upload_log.read_bytes(), record)
        self.upload_log.unlink()
        # Inject a historical small textual payload, bypassing clean and hooks.
        raw = self.git("hash-object", "-w", "--stdin", input=b"historical raw reference\n").strip().decode()
        self.git("update-index", "--add", "--cacheinfo", "100644", raw, "references/deleted.txt")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "bad historical payload")
        bad = self.git("rev-parse", "HEAD").strip()
        self.git("rm", "--cached", "references/deleted.txt")
        self.commit()
        self.policy("check")  # Tip is clean, reachable history is not.
        result = subprocess.run([sys.executable, "scripts/storage_policy.py", "history", "HEAD"],
                                cwd=self.root, env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(bad, result.stderr)
        self.assertIn(b"references/deleted.txt", result.stderr)
        head = self.git("rev-parse", "HEAD").strip()
        record = b"refs/heads/main " + head + b" refs/heads/main " + b"0" * 40 + b"\n"
        self.run_cmd(".githooks/pre-push", "hf", "https://example.invalid/hf", input=record, success=False)
        self.assertFalse(self.upload_log.exists(), "validation must run before upload")

    def test_wrong_transfer_override_is_rejected(self):
        self.git("config", "lfs.standalonetransferagent", "other")
        self.setup_repo(success=False)
        self.assertFalse((self.root / ".githooks").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
