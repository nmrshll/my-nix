"""Manage an isolated LuLu 4.2 profile; never edit a running filter's files."""

import argparse
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

PROFILE = "nix-safari-youtube"
EXTENSION = "com.objective-see.lulu.extension"


class Archive:
    """The NSKeyedArchiver subset used by LuLu's NSSecureCoding Rule class."""

    def __init__(self):
        self.objects = ["$null"]
        self.classes = {}

    def add(self, value):
        self.objects.append(value)
        return plistlib.UID(len(self.objects) - 1)

    def cls(self, name, bases):
        if name not in self.classes:
            self.classes[name] = self.add({"$classname": name, "$classes": [name, *bases]})
        return self.classes[name]

    def encode(self, value):
        if value is None:
            return plistlib.UID(0)
        if isinstance(value, dict):
            return self.add({
                "$class": self.cls("NSMutableDictionary", ["NSDictionary", "NSObject"]),
                "NS.keys": [self.encode(key) for key in value],
                "NS.objects": [self.encode(item) for item in value.values()],
            })
        if isinstance(value, list):
            return self.add({
                "$class": self.cls("NSMutableArray", ["NSArray", "NSObject"]),
                "NS.objects": [self.encode(item) for item in value],
            })
        return self.add(value)

    def rule(self, rule):
        return self.add({
            "$class": self.cls("Rule", ["NSObject"]),
            **{key: self.encode(value) for key, value in rule.items()
               if key != "isEndpointAddrRegex"},
            "isEndpointAddrRegex": bool(rule.get("isEndpointAddrRegex", False)),
        })


def archive_rules(rules):
    archive = Archive()
    groups = {}
    for key, items in rules.items():
        group = {"rules": items}
        # Encode Rule objects specially, rather than dictionaries.
        group_ref = archive.encode({})
        array_ref = archive.add({
            "$class": archive.cls("NSMutableArray", ["NSArray", "NSObject"]),
            "NS.objects": [archive.rule(item) for item in group["rules"]],
        })
        archive.objects[group_ref.data]["NS.keys"] = [archive.encode("rules")]
        archive.objects[group_ref.data]["NS.objects"] = [array_ref]
        groups[key] = group_ref
    root = archive.add({
        "$class": archive.cls("NSMutableDictionary", ["NSDictionary", "NSObject"]),
        "NS.keys": [archive.encode(key) for key in groups],
        "NS.objects": list(groups.values()),
    })
    return plistlib.dumps({"$archiver": "NSKeyedArchiver", "$version": 100000,
                          "$objects": archive.objects, "$top": {"root": root}},
                         fmt=plistlib.FMT_BINARY, sort_keys=False)


def decode_archive(data):
    archive = plistlib.loads(data)
    objects = archive["$objects"]

    def decode(value):
        if not isinstance(value, plistlib.UID):
            return value
        if value.data == 0:
            return None
        obj = objects[value.data]
        if not isinstance(obj, dict):
            return obj
        kind = objects[obj["$class"].data]["$classname"]
        if kind in ("NSDictionary", "NSMutableDictionary"):
            return dict(zip(map(decode, obj["NS.keys"]), map(decode, obj["NS.objects"])))
        if kind in ("NSArray", "NSMutableArray", "NSSet", "NSMutableSet"):
            return list(map(decode, obj["NS.objects"]))
        if kind == "Rule":
            return {key: decode(item) for key, item in obj.items() if key != "$class"}
        if kind == "NSDate":
            return {"NS.time": obj["NS.time"]}
        raise ValueError(f"Unsupported LuLu archive class: {kind}")

    return decode(archive["$top"]["root"])


def load_plist(path):
    return plistlib.loads(path.read_bytes()) if path.exists() else {}


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as file:
            file.write(data)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configured(base, policy):
    profile = base / "Profiles" / PROFILE
    if load_plist(base / "preferences.plist").get("currentProfile") != str(profile):
        return False
    preferences = load_plist(profile / "preferences.plist")
    if any(preferences.get(key) != value for key, value in policy["preferences"].items()):
        return False
    if not (profile / "rules.plist").exists():
        return False
    actual = decode_archive((profile / "rules.plist").read_bytes())
    if set(actual) != set(policy["rules"]):
        return False
    for key, expected in policy["rules"].items():
        observed = actual[key]["rules"]
        if len(observed) != len(expected):
            return False
        for wanted in expected:
            # UUID/name/scope are GUI metadata after construction, not matching
            # conditions. LuLu's editor also stores nil for enabled rules.
            def matches(item):
                for field, value in wanted.items():
                    if field in ("uuid", "name", "scope"):
                        continue
                    actual = item.get(field)
                    if field == "isDisabled":
                        actual = actual or 0
                    if actual != value:
                        return False
                return True

            if not any(matches(item) for item in observed):
                return False
    return True


def apply(base, policy, running):
    if configured(base, policy):
        return False
    if running:
        raise RuntimeError("Disable LuLu's Network Extension in System Settings before applying changed rules; then enable it again.")
    profile = base / "Profiles" / PROFILE
    preferences = load_plist(base / "preferences.plist")
    backup = base / f"{PROFILE}-previous.plist"
    if not backup.exists():
        atomic_write(backup, plistlib.dumps({"preferences": preferences}))
    # Build and validate all bytes before modifying any live profile pointers.
    rules = archive_rules(policy["rules"])
    decode_archive(rules)
    atomic_write(profile / "rules.plist", rules)
    atomic_write(profile / "preferences.plist", plistlib.dumps(policy["preferences"]))
    preferences["currentProfile"] = str(profile)
    atomic_write(base / "preferences.plist", plistlib.dumps(preferences))
    return True


def extension_state():
    result = subprocess.run(["/usr/bin/systemextensionsctl", "list"],
                            text=True, capture_output=True, check=True)
    enabled = any(EXTENSION in line and "[activated enabled]" in line
                  for line in result.stdout.splitlines())
    processes = subprocess.run(["/bin/ps", "-axo", "command"],
                               text=True, capture_output=True, check=True)
    running = any("/Library/SystemExtensions/" in line and
                  "/com.objective-see.lulu.extension.systemextension/Contents/MacOS/" in line
                  for line in processes.stdout.splitlines())
    return enabled, running


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["apply", "status", "restore"])
    parser.add_argument("policy", type=pathlib.Path)
    parser.add_argument("--directory", type=pathlib.Path,
                        default=pathlib.Path("/Library/Objective-See/LuLu"))
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text())
    enabled, running = extension_state()
    if args.command == "status":
        matches = configured(args.directory, policy)
        print(f"Profile matches flake: {matches}; extension enabled: {enabled}; process running: {running}")
        print("Safari blocking and other-app connectivity still require a live check.")
        return 0 if matches and enabled and running else 1
    if os.geteuid() != 0:
        raise RuntimeError("Run this command with sudo to manage LuLu's root-owned profile.")
    if args.command == "apply":
        app = pathlib.Path("/Applications/LuLu.app/Contents/Info.plist")
        if load_plist(app).get("CFBundleShortVersionString") != "4.2.0":
            raise RuntimeError("This profile writer is verified for LuLu 4.2.0; review the archive schema before changing versions.")
        changed = apply(args.directory, policy, running or enabled)
        print("Profile applied; enable LuLu's Network Extension in System Settings." if changed else "Profile already matches the flake.")
    else:
        if running or enabled:
            raise RuntimeError("Disable LuLu's Network Extension before restoring the previous profile.")
        backup = args.directory / f"{PROFILE}-previous.plist"
        previous = load_plist(backup)
        if not previous:
            raise RuntimeError("No previous-profile backup found.")
        preferences = load_plist(args.directory / "preferences.plist")
        old = previous["preferences"].get("currentProfile")
        if old is None:
            preferences.pop("currentProfile", None)
        else:
            preferences["currentProfile"] = old
        atomic_write(args.directory / "preferences.plist", plistlib.dumps(preferences))
        print("Previous profile selected; the managed profile was preserved on disk.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
