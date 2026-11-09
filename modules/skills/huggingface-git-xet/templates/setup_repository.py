#!/usr/bin/env python3
"""Copy alongside storage_policy.py; configure only this Git checkout."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

from storage_policy import CODE_FILTER, ROOT, check_setup, config


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    os.chdir(ROOT)
    if Path(git("rev-parse", "--show-toplevel")).resolve() != ROOT:
        raise ValueError("copy setup and policy into the target repository's scripts/ first")
    for tool in ("git-lfs", "git-xet"):
        if not shutil.which(tool):
            raise ValueError(f"missing Nix-managed {tool}; enter the project Nix shell")
    git("lfs", "version")
    git("xet", "--version")
    if config(f"filter.{CODE_FILTER}.process"):
        raise ValueError("existing code process filter: integrate before setup")
    if config("lfs.standalonetransferagent"):
        raise ValueError("existing standalone LFS transfer agent: integrate before setup")

    python = shlex.quote(sys.executable)
    policy = shlex.quote(str(ROOT / "scripts/storage_policy.py"))
    command = f"{python} {policy}"
    # Tracked hook sources stay portable; Python comes from the project's shell.
    hook_command = "python3 scripts/storage_policy.py"
    hooks = ROOT / ".githooks"
    if hooks.is_symlink():
        raise ValueError("refusing to write through a symlinked .githooks directory")
    wanted = {
        "pre-commit": f"#!/bin/sh\nset -eu\n{hook_command} check\n",
        "pre-push": (
            "#!/bin/sh\nset -eu\n"
            'updates=$(mktemp)\ntrap \'rm -f "$updates"\' EXIT HUP INT TERM\n'
            'cat > "$updates"\n'
            f"{hook_command} check\n"
            f'{hook_command} push < "$updates"\n'
            'git lfs pre-push "$@" < "$updates"\n'
        ),
    }
    # Check inherited and default hooks before changing any configuration/files.
    candidates = {Path(git("rev-parse", "--git-path", "hooks")).resolve(),
                  (Path(git("rev-parse", "--git-common-dir")) / "hooks").resolve()}
    for directory in candidates:
        if directory != hooks and directory.is_dir():
            active = [p.name for p in directory.iterdir()
                      if not p.name.endswith(".sample") and p.is_file() and os.access(p, os.X_OK)]
            if active:
                raise ValueError(f"preserve/integrate existing hooks in {directory}: {active}")
    for name, text in wanted.items():
        path = hooks / name
        if path.is_symlink() or (path.exists() and path.read_text() != text):
            raise ValueError(f"preserve/integrate differing {path}; no hooks were replaced")

    # Reuse effective Nix settings; only bootstrap missing settings locally.
    lfs_keys = ("clean", "smudge", "process", "required")
    if not all(config(f"filter.lfs.{key}") for key in lfs_keys):
        git("lfs", "install", "--local", "--skip-repo")
    expected_xet = {"path": "git-xet", "args": "transfer", "concurrent": "true"}
    current_xet = {key: config(f"lfs.customtransfer.xet.{key}") for key in expected_xet}
    if any(value and value != expected_xet[key] for key, value in current_xet.items()):
        raise ValueError("existing differing Xet transfer settings: review before setup")
    if not all(current_xet.values()):
        git("xet", "install", "--local")
    git("config", "--local", "lfs.basictransfersonly", "false")
    git("config", "--local", f"filter.{CODE_FILTER}.clean", f"{command} clean -- %f")
    git("config", "--local", f"filter.{CODE_FILTER}.smudge", "cat")
    git("config", "--local", f"filter.{CODE_FILTER}.required", "true")
    hooks.mkdir(exist_ok=True)
    for name, text in wanted.items():
        path = hooks / name
        if not path.exists():
            path.write_text(text)
        path.chmod(path.stat().st_mode | 0o111)
    git("config", "--local", "core.hooksPath", ".githooks")
    check_setup()
    print("Configured local code filter, LFS/Xet readiness and .githooks commit/push guards.")
    print("No remotes changed, Hub repositories created, history migrated or refs pushed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"Repository setup: {exc}", file=sys.stderr)
        sys.exit(1)
