#!@python@
"""Merge a Nix-managed backend into Desktop's mutable installation registry."""

import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

manifest = json.loads(Path(sys.argv[1]).read_text())
registry = Path(sys.argv[2])
registry.parent.mkdir(parents=True, exist_ok=True)
original = registry.read_text() if registry.exists() else "[]"
instances = json.loads(original)
if not isinstance(instances, list):
    raise SystemExit("Comfy Desktop installation registry must be a JSON array")

instance = next((item for item in instances if item.get("nixManaged")), None)
if instance is None:
    instance = next((item for item in instances
                     if item.get("sourceId") == "standalone"
                     and item.get("adoptedBaseDir") == manifest["adoptedBaseDir"]), None)
if instance is None:
    instance = {"id": "nix-comfyui", "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    instances.append(instance)
instance.update(manifest)

if json.loads(original) != instances:
    running = subprocess.run(
        ["/usr/bin/pgrep", "-u", str(os.getuid()), "-x", "Comfy Desktop"],
        stdout=subprocess.DEVNULL,
    )
    if running.returncode == 0:
        raise SystemExit("Quit Comfy Desktop, then rerun Home Manager activation to apply its Nix instance.")
    if registry.exists():
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        shutil.copy2(registry, registry.with_name(registry.name + ".before-nix-" + stamp))
    descriptor, temporary = tempfile.mkstemp(dir=registry.parent, prefix=".nix-installations-")
    try:
        with os.fdopen(descriptor, "w") as file:
            json.dump(instances, file, indent=2)
            file.write("\n")
        os.replace(temporary, registry)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
