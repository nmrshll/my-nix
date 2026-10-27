"""Synchronize a model manifest outside Nix; never expose unverified partial files."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(8 * 1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def atomic_json(path, value):
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)


def remember(config, state):
    """Remember old store/library paths before HM replaces its generated YAML."""
    with (state / "source-paths.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        hints = state / "source-paths.json"
        roots = json.loads(hints.read_text()) if hints.exists() else {}
        if config.exists():
            # HM deliberately emits JSON, which is also valid YAML.
            data = json.loads(config.read_text())
            for section in data.values():
                base = Path(section.get("base_path", str(config.parent))).expanduser()
                if not base.is_absolute():
                    base = config.parent / base
                for category in ("diffusion_models", "text_encoders", "vae"):
                    for item in section.get(category, "").splitlines():
                        root = str((base / item).resolve())
                        if root not in roots.setdefault(category, []):
                            roots[category].append(root)
        atomic_json(hints, roots)


def validated_manifest(path):
    data = json.loads(path.read_text())
    root = Path(data["directory"]).expanduser()
    if not root.is_absolute() or root.resolve().is_relative_to("/nix/store"):
        raise ValueError("Model directory must be an absolute path outside /nix/store")
    paths = set()
    for model in data["files"]:
        relative = Path(model["path"])
        if relative.is_absolute() or ".." in relative.parts or len(relative.parts) < 2:
            raise ValueError("Model paths must be category-relative paths without '..'")
        if relative.parts[0].startswith(".") or model["path"] in paths:
            raise ValueError("Reserved or duplicate model path")
        paths.add(model["path"])
        if not re.fullmatch(r"[0-9a-f]{64}", model["sha256"]):
            raise ValueError("Every model needs a lowercase SHA-256 hash")
        if urlsplit(model["url"]).scheme not in ("http", "https"):
            raise ValueError("Model URLs must use HTTP(S)")
        if not (root / relative).resolve().is_relative_to(root.resolve()):
            # A model file may itself be an old store symlink: it is replaced,
            # never written through. Directory symlinks must remain in root.
            if not (root / relative).parent.resolve().is_relative_to(root.resolve()):
                raise ValueError("Model directory symlink escapes the configured root")
    return data, root


def copy_verified(source, partial, expected):
    sha = hashlib.sha256()
    with source.open("rb") as incoming, partial.open("wb") as outgoing:
        for block in iter(lambda: incoming.read(8 * 1024 * 1024), b""):
            sha.update(block)
            outgoing.write(block)
        outgoing.flush()
        os.fsync(outgoing.fileno())
    if sha.hexdigest() == expected:
        return True
    partial.unlink()
    return False


def publish(partial, target):
    if target.exists() or target.is_symlink():
        backup = target.with_name(target.name + ".before-model-sync-" + str(time.time_ns()))
        try:
            os.link(target, backup, follow_symlinks=False)
        except OSError:
            shutil.copy2(target, backup, follow_symlinks=False)
        print("Preserved previous file:", backup, flush=True)
    os.replace(partial, target)


def sync(data, root, state, curl):
    roots = json.loads((state / "source-paths.json").read_text()) if (state / "source-paths.json").exists() else {}
    partial_dir = root / ".downloads"
    if not partial_dir.resolve().is_relative_to(root.resolve()):
        raise ValueError("Partial download directory escapes the configured root")
    partial_dir.mkdir(parents=True, exist_ok=True)
    for model in data["files"]:
        target = root / model["path"]
        expected = model["sha256"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and digest(target) == expected:
            if not (target.is_symlink() and target.resolve().is_relative_to("/nix/store")):
                print("Ready:", model["path"], flush=True)
                continue
        partial = partial_dir / (expected + ".part")
        if not (partial.is_file() and digest(partial) == expected):
            relative = Path(model["path"])
            candidates = [Path(p) / relative for p in data.get("search_roots", [])]
            candidates += [Path(p) / Path(*relative.parts[1:]) for p in roots.get(relative.parts[0], [])]
            if target.is_file():
                candidates.insert(0, target)
            reused = False
            for source in dict.fromkeys(candidates):
                if source.is_file() and source.stat().st_size > 0:
                    print("Checking local file:", source, flush=True)
                    seed = partial.with_suffix(".seed")
                    if copy_verified(source, seed, expected):
                        os.replace(seed, partial)
                        reused = True
                        break
            if not reused:
                print("Downloading:", model["path"], flush=True)
                args = [curl, "--fail", "--location", "--silent", "--show-error",
                        "--retry", "3", "--retry-all-errors", "--retry-delay", "5",
                        "--connect-timeout", "20", "--speed-time", "60", "--speed-limit", "1024",
                        "--continue-at", "-", "--output", str(partial),
                        "--write-out", "%{http_code}", model["url"]]
                result = subprocess.run(args, stdout=subprocess.PIPE, text=True)
                if result.returncode in (33, 36) or (result.returncode == 22 and result.stdout == "416"):
                    partial.unlink(missing_ok=True)
                    result = subprocess.run(args, stdout=subprocess.PIPE, text=True)
                if result.returncode:
                    raise RuntimeError("Download failed; rerun comfyui-models to resume: " + model["path"])
                if digest(partial) != expected:
                    partial.unlink()
                    raise RuntimeError("SHA-256 mismatch; rejected download: " + model["path"])
        publish(partial, target)
        print("Installed:", model["path"], flush=True)
    print("Model sync complete", flush=True)


def main(argv=None):
    home = Path.home()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "comfyui/models.json")
    parser.add_argument("--state-dir", type=Path, default=Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "comfyui-models")
    parser.add_argument("--remember-config", type=Path)
    parser.add_argument("--curl", default="curl")
    args = parser.parse_args(argv)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    # Remembering hints is short; do not wait behind a running download.
    if args.remember_config:
        remember(args.remember_config, args.state_dir)
        return 0
    data, root = validated_manifest(args.manifest)
    root.mkdir(parents=True, exist_ok=True)
    # The lock follows the model directory, even with a custom state directory.
    with (root / ".model-sync.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("A model sync is already running", flush=True)
            return 0
        sync(data, root, args.state_dir, args.curl)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr, flush=True)
        sys.exit(1)
