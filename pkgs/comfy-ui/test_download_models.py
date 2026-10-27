"""Downloader tests using tiny loopback fixtures, never real model downloads."""

import contextlib
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location("downloader", Path(__file__).with_name("download-models.py"))
downloader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloader)


class DownloaderTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="comfy-model-test-")
        self.base = Path(self.temporary.name)
        self.state = self.base / "state"
        self.root = self.base / "models"
        self.target = self.root / "diffusion_models/test.safetensors"
        self.payload = b"local fixture, not a model\n" * 4096
        self.expected = hashlib.sha256(self.payload).hexdigest()
        self.requests = []
        self.response = self.payload
        test = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                header = self.headers.get("Range")
                test.requests.append(header)
                # curl writes a separate staging file, never the final model.
                if test.target.exists():
                    assert test.target.read_bytes() != test.response
                body = test.response
                if header:
                    offset = int(header.removeprefix("bytes=").removesuffix("-"))
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {offset}-{len(body)-1}/{len(body)}")
                    body = body[offset:]
                else:
                    self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.manifest = self.base / "models.json"
        self.write_manifest()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def write_manifest(self, **extra):
        self.manifest.write_text(json.dumps({
            "directory": str(self.root),
            "files": [{"path": "diffusion_models/test.safetensors", "sha256": self.expected,
                       "url": f"http://127.0.0.1:{self.server.server_port}/fixture"}],
            **extra,
        }))

    def run_sync(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return downloader.main(["--manifest", str(self.manifest), "--state-dir", str(self.state),
                                    "--curl", shutil.which("curl")])

    def test_download_and_idempotent_skip(self):
        self.run_sync()
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.run_sync()
        self.assertEqual(len(self.requests), 1)

    def test_resume_survives_rejected_local_seed(self):
        partial = self.root / ".downloads" / (self.expected + ".part")
        partial.parent.mkdir(parents=True)
        partial.write_bytes(self.payload[:1234])
        source = self.base / "library/diffusion_models/test.safetensors"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"wrong model")
        self.write_manifest(search_roots=[str(self.base / "library")])
        self.run_sync()
        self.assertEqual(self.requests, ["bytes=1234-"])
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_bad_checksum_never_replaces_existing_file(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"keep this until a verified replacement exists")
        self.response = b"corrupt response"
        with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
            self.run_sync()
        self.assertEqual(self.target.read_bytes(), b"keep this until a verified replacement exists")
        self.assertFalse(any((self.root / ".downloads").glob("*.part")))

    def test_replacement_preserves_previous_file(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"old model")
        self.run_sync()
        backups = list(self.target.parent.glob("*.before-model-sync-*"))
        self.assertEqual([p.read_bytes() for p in backups], [b"old model"])
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_remembered_paths_reuse_without_http(self):
        source = self.base / "old-store/vae"
        source.mkdir(parents=True)
        (source / "test.safetensors").write_bytes(self.payload)
        config = self.base / "extra_model_paths.yaml"
        config.write_text(json.dumps({"old": {"base_path": str(source.parent), "diffusion_models": "vae"}}))
        downloader.main(["--remember-config", str(config), "--state-dir", str(self.state)])
        config.write_text("{}")
        downloader.main(["--remember-config", str(config), "--state-dir", str(self.state)])
        self.run_sync()
        self.assertEqual(self.requests, [])
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_completed_partial_publishes_without_http(self):
        partial = self.root / ".downloads" / (self.expected + ".part")
        partial.parent.mkdir(parents=True)
        partial.write_bytes(self.payload)
        self.run_sync()
        self.assertEqual(self.requests, [])
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_second_process_does_not_duplicate_download(self):
        self.root.mkdir()
        with (self.root / ".model-sync.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run([sys.executable, str(Path(downloader.__file__)),
                                     "--manifest", str(self.manifest), "--state-dir", str(self.state)],
                                    capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn("already running", result.stdout)
        self.assertEqual(self.requests, [])

    def test_reject_path_escape_before_http(self):
        data = json.loads(self.manifest.read_text())
        data["files"][0]["path"] = "../escaped.safetensors"
        self.manifest.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            self.run_sync()
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()
