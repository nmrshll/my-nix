"""Sync managed fragments into a project's agents.md, preserving manual content.

Each fragment is wrapped in a pair of HTML comments that name it:

    <!-- my-nix:agents-fragment:start git-conventions -->
    ...managed content...
    <!-- my-nix:agents-fragment:end git-conventions -->

On every run the content between a fragment's markers is replaced with the
currently configured content, fragments that are no longer configured are
removed, and fragments that are not present yet are appended (in name order).
Everything outside the markers -- including manual edits made between, before
or after them -- is left exactly as it is, so rerunning is a no-op when
nothing changed.

Usage: sync-agents-md.py REPO FRAGMENTS_JSON [FILE]
  REPO            consumer checkout root (the file lives directly under it)
  FRAGMENTS_JSON  JSON object mapping fragment names to their content
  FILE            file name relative to REPO (default: AGENTS.md); must be a
                  single path component, never a path with directories
"""

import fcntl
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


START = "<!-- my-nix:agents-fragment:start {name} -->"
END = "<!-- my-nix:agents-fragment:end {name} -->"
NAME = re.compile(r"[a-z0-9][a-z0-9_-]*")
MARKER = re.compile(r"<!-- my-nix:agents-fragment:(start|end) ([a-z0-9][a-z0-9_-]*) -->")


def content_lines(content):
    """Normalize fragment content to the lines placed between the markers."""
    lines = content.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        raise ValueError("agents.md fragment must not be empty")
    return lines


def render_block(name, content):
    return [START.format(name=name), *content_lines(content), END.format(name=name)]


def sync_text(text, fragments):
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    keep_trailing_newline = not text or text.endswith(("\n", "\r"))

    out = []
    seen = set()
    current = None  # name of the managed block being skipped/replaced
    for line in lines:
        marker = MARKER.fullmatch(line.strip())
        if current is None:
            if marker is None:
                out.append(line)
            elif marker.group(1) == "start":
                name = marker.group(2)
                if name in seen:
                    raise ValueError(f"duplicate agents.md fragment marker: {name}")
                seen.add(name)
                current = name
                if name in fragments:
                    out.extend(render_block(name, fragments[name]))
            else:
                raise ValueError(
                    f"agents.md fragment end without start: {marker.group(2)}"
                )
        elif marker is not None and marker.group(1) == "start":
            raise ValueError(
                f"nested agents.md fragment markers: {current} and {marker.group(2)}"
            )
        elif marker is not None and marker.group(2) != current:
            raise ValueError(
                f"agents.md fragment end for {marker.group(2)} inside {current}"
            )
        elif marker is not None:
            current = None
        # Any other line inside a managed block is dropped: it is either
        # replaced above (stale content) or the fragment was removed.
    if current is not None:
        raise ValueError(f"unterminated agents.md fragment marker: {current}")

    appended = False
    for name in sorted(fragments):
        if name not in seen:
            if out and out[-1].strip():
                out.append("")
            out.extend(render_block(name, fragments[name]))
            appended = True

    rendered = newline.join(out)
    if rendered and (keep_trailing_newline or appended):
        rendered += newline
    return rendered


def sync(repo, fragments_file, filename):
    if not filename or filename in (".", "..") or "/" in filename or "\\" in filename:
        raise ValueError(f"agents.md file must be a plain file name: {filename!r}")
    fragments = json.loads(Path(fragments_file).read_text(encoding="utf-8"))
    if not isinstance(fragments, dict):
        raise ValueError("fragments file must contain a JSON object")
    for name, content in fragments.items():
        if not isinstance(name, str) or NAME.fullmatch(name) is None:
            raise ValueError(f"invalid agents.md fragment name: {name!r}")
        if not isinstance(content, str):
            raise ValueError(f"agents.md fragment {name} must be a string")
        content_lines(content)  # validate non-empty up front
    if not fragments:
        return

    target = repo / filename
    if target.is_symlink():
        print(f"ai-skills: skipping symlinked agents file: {target}", file=sys.stderr)
        return

    # Serialize concurrent shell entries in the same checkout.
    fd = os.open(repo, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        original = target.read_bytes().decode("utf-8") if target.exists() else ""
        updated = sync_text(original, fragments)
        if updated == original:
            return
        mode = stat.S_IMODE(target.stat().st_mode) if target.exists() else 0o644
        with tempfile.NamedTemporaryFile(
            dir=repo, delete=False, prefix=f".{filename}."
        ) as out:
            temp = Path(out.name)
            try:
                out.write(updated.encode("utf-8"))
                out.flush()
                temp.chmod(mode)
                temp.replace(target)
            finally:
                temp.unlink(missing_ok=True)
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        sync(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "AGENTS.md")
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError) as error:
        sys.exit(f"ai-skills: could not sync agents.md fragments: {error}")
