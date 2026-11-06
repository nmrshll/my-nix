#!/usr/bin/env python3
"""Mixed-repository starter: adapt classification and limits to project policy."""
import argparse
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CODE_FILTER = "repo-code"
MAX_CODE_BYTES = 2 * 1024 * 1024
ASSET_PREFIXES = ("assets/", "references/")
# Examples only: extend from repository policy, not a universal extension list.
PAYLOAD_SUFFIXES = {".bin", ".png", ".zip", ".7z", ".pk3", ".exe", ".dll"}
POINTER_HEADER = b"version https://git-lfs.github.com/spec/v1\n"
POINTER = re.compile(re.escape(POINTER_HEADER) + rb"oid sha256:[0-9a-f]{64}\nsize [0-9]+\n")


def git(*args, input=None):
    return subprocess.check_output(["git", *args], input=input)


def config(key):
    result = subprocess.run(["git", "config", "--get", key], capture_output=True)
    if result.returncode not in (0, 1):
        raise ValueError(f"cannot read {key}")
    return result.stdout.decode().strip()


def is_asset(path):
    return path.startswith(ASSET_PREFIXES)


def check_path(path):
    if ".cache" in PurePosixPath(path).parts:
        raise ValueError(f"{path}: unpacked/cache files must stay local and untracked")


def check_code(path, data):
    check_path(path)
    if is_asset(path) or PurePosixPath(path).suffix.lower() in PAYLOAD_SUFFIXES:
        raise ValueError(f"{path}: payload belongs in an LFS asset path")
    if len(data) > MAX_CODE_BYTES or b"\0" in data or data.startswith(POINTER_HEADER):
        raise ValueError(f"{path}: oversized, binary or LFS pointer content in code Git")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: code must be UTF-8") from exc


def check_blob(path, oid):
    check_path(path)
    size = int(git("cat-file", "-s", oid))
    limit = 1024 if is_asset(path) else MAX_CODE_BYTES
    if size > limit:
        raise ValueError(f"{path}: raw Git blob {oid} is {size} bytes (limit {limit})")
    data = git("cat-file", "blob", oid)
    if is_asset(path):
        # Git LFS treats an empty asset as its own empty pointer.
        if data and not POINTER.fullmatch(data):
            raise ValueError(f"{path}: raw asset blob {oid}, expected an LFS pointer")
    else:
        check_code(path, data)


def check_setup():
    expected = {
        f"filter.{CODE_FILTER}.required": "true",
        f"filter.{CODE_FILTER}.smudge": "cat",
        "filter.lfs.required": "true",
        "lfs.customtransfer.xet.path": "git-xet",
        "lfs.customtransfer.xet.args": "transfer",
        "lfs.customtransfer.xet.concurrent": "true",
        "core.hooksPath": ".githooks",
    }
    for key, value in expected.items():
        if config(key) != value:
            raise ValueError(f"{key}: expected {value}; rerun repository setup")
    for key in (f"filter.{CODE_FILTER}.clean", "filter.lfs.clean",
                "filter.lfs.smudge", "filter.lfs.process"):
        if not config(key):
            raise ValueError(f"{key}: missing driver; rerun repository setup")
    if config(f"filter.{CODE_FILTER}.process"):
        raise ValueError("code process filter overrides the required clean filter")
    basic = subprocess.run(["git", "config", "--type=bool", "--get",
                            "lfs.basictransfersonly"], capture_output=True)
    if basic.returncode not in (0, 1) or basic.stdout.strip() not in (b"", b"false"):
        raise ValueError("lfs.basictransfersonly must allow custom transfers")
    if config("lfs.standalonetransferagent"):
        raise ValueError("review/remove standalone transfer override before using Xet")


def check_index():
    check_setup()
    paths = []
    for entry in git("ls-files", "--stage", "-z").split(b"\0"):
        if not entry:
            continue
        header, raw_path = entry.split(b"\t", 1)
        mode, oid, stage = header.decode().split()
        path = os.fsdecode(raw_path)
        if stage != "0" or mode not in {"100644", "100755"}:
            raise ValueError(f"{path}: unresolved, symlink or submodule entry; define policy first")
        check_blob(path, oid)
        paths.append(raw_path)
    if not paths:
        return
    attrs = git("check-attr", "--cached", "-z", "--stdin",
                "filter", "diff", "merge", "text", "eol",
                input=b"\0".join(paths) + b"\0").split(b"\0")
    for i in range(0, len(attrs) - 1, 3):
        raw_path, attr, actual = attrs[i:i + 3]
        path = os.fsdecode(raw_path)
        expected = {b"filter": CODE_FILTER.encode()}
        if is_asset(path):
            expected = {b"filter": b"lfs", b"diff": b"lfs", b"merge": b"lfs",
                        b"text": b"unset", b"eol": b"unspecified"}
        if attr in expected and actual != expected[attr]:
            raise ValueError(f"{path}: {os.fsdecode(attr)}={os.fsdecode(actual)}, "
                             f"expected {os.fsdecode(expected[attr])}")


def check_history(revisions):
    if git("rev-parse", "--is-shallow-repository").strip() == b"true":
        raise ValueError("complete history is required; this checkout is shallow")
    seen = set()
    for commit in git("rev-list", *revisions).decode().splitlines():
        try:
            for entry in git("ls-tree", "-rz", commit).split(b"\0"):
                if not entry:
                    continue
                header, raw_path = entry.split(b"\t", 1)
                mode, kind, oid = header.decode().split()
                path = os.fsdecode(raw_path)
                if kind != "blob" or mode not in {"100644", "100755"}:
                    raise ValueError(f"{path}: unsupported tree entry; define policy first")
                if (path, oid) not in seen:
                    check_blob(path, oid)
                    seen.add((path, oid))
        except ValueError as exc:
            raise ValueError(f"commit {commit}: {exc}") from exc


def check_push():
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise ValueError("malformed pre-push record")
        _, local_oid, _, remote_oid = fields
        if not all(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid)
                   for oid in (local_oid, remote_oid)):
            raise ValueError("invalid pre-push object ID")
        if set(local_oid) == {"0"}:
            continue  # Ref deletion, no new history.
        revisions = [local_oid]
        if set(remote_oid) != {"0"}:
            exists = subprocess.run(["git", "cat-file", "-e", remote_oid],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if exists.returncode == 0:
                revisions.append("^" + remote_oid)
        check_history(revisions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["clean", "check", "history", "push"])
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    os.chdir(ROOT)
    try:
        if args.command == "clean":
            if len(args.paths) != 1:
                raise ValueError("clean requires one Git path")
            data = sys.stdin.buffer.read(MAX_CODE_BYTES + 1)
            check_code(args.paths[0], data)
            sys.stdout.buffer.write(data)
        elif args.command == "check":
            check_index()
        elif args.command == "history":
            check_history(args.paths or ["--all"])
        else:
            check_setup()
            check_push()
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"Storage policy: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
