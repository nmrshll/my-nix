"""Live macOS URL-event test with an isolated app and fake browser backend.

Run with the built Brave app's Contents/MacOS/Brave Browser executable.
No real browser profile or default-handler preference is changed.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time


def wait_for(predicate, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix="brave-relay-", dir="/private/tmp") as directory:
    root = Path(directory)
    app = root / "Relay Test.app"
    contents = app / "Contents"
    executable = contents / "MacOS" / "relay"
    executable.parent.mkdir(parents=True)
    shutil.copyfile(sys.argv[1], executable)
    executable.chmod(0o755)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": "io.nixhome.brave-relay-test",
                      "CFBundleName": "Brave Relay Test",
                      "CFBundleExecutable": "relay",
                      "CFBundlePackageType": "APPL",
                      "CFBundleURLTypes": [{"CFBundleURLSchemes": ["http", "https"]}]}, stream)
    log = root / "calls.jsonl"
    stop = root / "stop"
    pid_file = root / "relay.pid"
    backend = Path(str(executable) + "-launch-wrapped")
    backend.write_text(f"#!{sys.executable}\n" + f'''
import json, os, pathlib, sys, time
with open({str(log)!r}, "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) == 1:
    pathlib.Path({str(pid_file)!r}).write_text(str(os.getppid()))
    deadline = time.monotonic() + 45
    while not pathlib.Path({str(stop)!r}).exists() and time.monotonic() < deadline:
        time.sleep(0.05)
''')
    backend.chmod(0o755)
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    register = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    try:
        subprocess.run(["/usr/bin/open", "-a", str(app)], check=True)
        wait_for(pid_file.exists, "Relay did not start the browser backend")
        for url in ["http://example.com/relay-http", "https://example.org/relay-https"]:
            subprocess.run(["/usr/bin/open", "-a", str(app), url], check=True)
            wait_for(lambda: [url] in [json.loads(line) for line in log.read_text().splitlines()],
                     f"URL event was not forwarded: {url}")
            print(f"Forwarded {url}")
        stop.touch()
        relay_pid = int(pid_file.read_text())

        def relay_exited():
            try:
                os.kill(relay_pid, 0)
                return False
            except ProcessLookupError:
                return True

        wait_for(relay_exited, "Relay remained running after the browser exited")
        print("Relay shut down after browser exit")
    finally:
        stop.touch()
        subprocess.run([register, "-u", str(app)], check=False, capture_output=True)
