"""Compare installed skills and hide global Codex skills shadowed by a checkout."""

import fcntl
import hashlib
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

import tomlkit
from tomlkit.items import AoT, Array, InlineTable
import yaml


MARKER = "my-nix: local skill override"
MANAGED_LINE = re.compile(
    r'\s*\{path = "(?:[^"\\]|\\.)*", enabled = false\}, # '
    + re.escape(MARKER)
    + r"\s*"
)


def skills(root, include_system=False):
    """Yield frontmatter names and discovery paths, following installed symlinks."""
    visited = set()
    for directory, dirs, files in root.walk(follow_symlinks=True):
        real_dir = directory.resolve()
        if real_dir in visited:
            dirs.clear()
            continue
        visited.add(real_dir)
        dirs[:] = sorted(
            name for name in dirs
            if not name.startswith(".") or (include_system and name == ".system")
        )
        if "SKILL.md" not in files:
            continue
        path = directory / "SKILL.md"
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
            if not lines or lines[0].strip() != "---":
                continue
            end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
            metadata = yaml.safe_load("\n".join(lines[1:end]))
        except (OSError, UnicodeError, StopIteration, yaml.YAMLError):
            continue
        if not isinstance(metadata, dict):
            continue
        name, description = metadata.get("name"), metadata.get("description")
        if isinstance(name, str) and name.strip() and isinstance(description, str) and description.strip():
            yield name.strip(), path


def codex_home_path():
    return Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").absolute()


def global_skills():
    codex_skills = codex_home_path() / "skills"
    yield from skills(Path.home() / ".agents" / "skills")
    yield from skills(codex_skills, include_system=True)
    yield from skills(Path("/etc/codex/skills"))


def directory_fingerprint(directory):
    """Fingerprint every file in a skill directory, or None when unreadable."""
    directory = Path(directory)
    entries = []
    visited = set()
    for base, dirs, files in os.walk(directory, followlinks=True):
        real_dir = Path(base).resolve()
        if real_dir in visited:
            dirs.clear()
            continue
        visited.add(real_dir)
        dirs.sort()
        for name in sorted(files):
            path = Path(base) / name
            try:
                entries.append((path.relative_to(directory).as_posix(),
                                hashlib.sha256(path.read_bytes()).hexdigest()))
            except OSError:
                return None
    return tuple(entries)


def print_identical_sources(sources):
    if not sources:
        return
    global_fingerprints = set()
    for _, path in global_skills():
        fingerprint = directory_fingerprint(path.parent)
        if fingerprint is not None:
            global_fingerprints.add(fingerprint)
    for source in sources:
        fingerprint = directory_fingerprint(source)
        if fingerprint is not None and fingerprint in global_fingerprints:
            print(source)


def shadowed_paths(repo):
    local = {}
    for name, path in skills(repo / ".agents" / "skills"):
        local.setdefault(name, set()).add(path.resolve())
    if not local:
        return []

    paths = set()
    for name, path in global_skills():
        if name in local:
            real_path = path.resolve()
            if real_path not in local[name]:
                paths.add(str(real_path))
    return sorted(paths)


def updated_config(text, paths):
    config = tomlkit.parse(text)
    if "skills" not in config:
        if not paths:
            return text
        config["skills"] = tomlkit.table(is_super_table=True)

    settings = config["skills"]
    if "config" not in settings:
        if not paths:
            return text
        settings["config"] = tomlkit.array() if isinstance(settings, InlineTable) else tomlkit.aot()
    rules = settings["config"]

    if isinstance(rules, AoT):
        managed = [
            index for index, rule in enumerate(rules)
            if rule.trivia.comment == f"# {MARKER}"
        ]
        wanted = [{"path": path, "enabled": False} for path in paths]
        if (managed == list(range(len(rules) - len(paths), len(rules)))
                and [rules[index].unwrap() for index in managed] == wanted):
            return text
        for index in reversed(managed):
            del rules[index]
        for path in paths:
            rule = tomlkit.table()
            rule.update(path=path, enabled=False)
            rule.comment(MARKER)
            rules.append(rule)
        if not rules:
            del settings["config"]
    elif isinstance(rules, Array):
        # Keep inline arrays inline-compatible and preserve the user's entries.
        lines = rules.as_string().splitlines(keepends=True)
        kept = [line for line in lines if not MANAGED_LINE.fullmatch(line)]
        if len(kept) != len(lines):
            cleaned = tomlkit.value("".join(kept))
            if len(rules) - len(cleaned) != len(lines) - len(kept):
                raise ValueError("unexpected managed rule syntax in skills.config")
            rules = cleaned
            settings["config"] = rules
        closing_newline = re.search(r"\n[ \t]*\]$", rules.as_string())
        for path in paths:
            rule = tomlkit.inline_table()
            rule.update(path=path, enabled=False)
            rules.add_line(rule, comment=MARKER)
        if paths and not closing_newline:
            rules.add_line(indent="")
    else:
        raise ValueError("skills.config must be an array")

    return tomlkit.dumps(config)


def sync(repo):
    paths = shadowed_paths(repo)
    directory = repo / ".codex"
    config = directory / "config.toml"
    if directory.is_symlink() or config.is_symlink():
        raise ValueError(f"skipping symlinked Codex config: {config}")
    if not paths and not config.exists():
        return
    directory.mkdir(exist_ok=True)

    # Serialize concurrent shell entries in the same checkout.
    fd = os.open(directory, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        original = config.read_bytes().decode("utf-8") if config.exists() else ""
        updated = updated_config(original, paths)
        if updated == original:
            return
        tomlkit.parse(updated)
        mode = stat.S_IMODE(config.stat().st_mode) if config.exists() else 0o600
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as out:
            temp = Path(out.name)
            try:
                out.write(updated.encode("utf-8"))
                out.flush()
                temp.chmod(mode)
                temp.replace(config)
            finally:
                temp.unlink(missing_ok=True)
    finally:
        os.close(fd)


def launch_codex(repo, args):
    """Pass the project rules explicitly for clients that ignore them at discovery."""
    def read_rules(path):
        if not path.exists():
            return []
        config = tomlkit.parse(path.read_text(encoding="utf-8"))
        return config.get("skills", {}).get("config", [])

    project_rules = read_rules(repo / ".codex" / "config.toml")
    options = []
    if project_rules:
        inline = tomlkit.array()
        user_rules = read_rules(codex_home_path() / "config.toml")
        for rule in [*user_rules, *project_rules]:
            entry = tomlkit.inline_table()
            entry.update(rule.unwrap())
            inline.append(entry)
        options = ["--config", f"skills.config={inline.as_string()}"]
    os.execvp("codex", ["codex", *options, *args])


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--identical-sources":
            print_identical_sources(sys.argv[2:])
        else:
            repo = Path(sys.argv[1])
            sync(repo)
            if sys.argv[2:3] == ["--codex"]:
                launch_codex(repo, sys.argv[3:])
    except (OSError, ValueError, TypeError, tomlkit.exceptions.TOMLKitError) as error:
        sys.exit(f"ai-skills: could not sync Codex skills: {error}")
