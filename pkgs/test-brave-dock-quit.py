"""Send the Dock's normal Quit request to an isolated relay and native backend.

Run with a built Brave app's Contents/MacOS/Brave Browser executable.
No real browser or profile is opened. Requires a logged-in macOS GUI session.
"""
import os
from pathlib import Path
import plistlib
import shlex
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


def exited(pid):
    try:
        os.kill(pid, 0)
        return False
    except ProcessLookupError:
        return True


with tempfile.TemporaryDirectory(prefix="brave-quit-") as directory:
    root = Path(directory)
    app = root / "Quit Test.app"
    contents = app / "Contents"
    executable = contents / "MacOS" / "relay"
    executable.parent.mkdir(parents=True)
    shutil.copyfile(sys.argv[1], executable)
    executable.chmod(0o755)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": "io.nixhome.brave-quit-test",
                      "CFBundleName": "Brave Quit Test",
                      "CFBundleVersion": "1.0", "CFBundleExecutable": "relay",
                      "CFBundlePackageType": "APPL"}, stream)
    browser = executable.with_name(".browser")
    subprocess.run(["/usr/bin/clang", "-Wall", "-Wextra", "-Werror", "-O2",
                    "-fobjc-arc", "-framework", "AppKit",
                    str(Path(__file__).with_name("test-brave-browser.m")), "-o", str(browser)], check=True)
    ready, quit_seen, cancel, cleanup, relay_pid_file = [
        root / name for name in ["ready", "quit", "cancel", "cleanup", "relay.pid"]]
    wrapper = Path(str(executable) + "-launch-wrapped")
    wrapper.write_text("#!/bin/sh\n" + "\n".join([
        f"export TEST_READY={shlex.quote(str(ready))}",
        f"export TEST_QUIT={shlex.quote(str(quit_seen))}",
        f"export TEST_CANCEL={shlex.quote(str(cancel))}",
        f"echo $PPID > {shlex.quote(str(relay_pid_file))}",
        shlex.quote(str(browser)),
        f"touch {shlex.quote(str(cleanup))}", ""]))
    wrapper.chmod(0o755)
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    register = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    try:
        for target in ["browser", "relay"]:
            for path in [ready, quit_seen, cleanup, relay_pid_file]:
                path.unlink(missing_ok=True)
            subprocess.run(["/usr/bin/open", "-n", str(app)], check=True)
            wait_for(ready.exists, "Native browser did not start")
            relay_pid = int(relay_pid_file.read_text())
            browser_pid = int(ready.read_text())
            if target == "relay":
                cancel.touch()
                subprocess.run([str(browser), "--quit", str(relay_pid)], check=True)
                wait_for(quit_seen.exists, "Relay did not forward Quit to browser")
                time.sleep(0.3)
                assert not exited(relay_pid), "Relay exited while browser cancelled Quit"
                assert not exited(browser_pid), "Browser did not cancel Quit"
                assert not cleanup.exists(), "Wrapper stopped before browser exited"
                cancel.unlink()
                quit_seen.unlink()
                print("Browser cancelled Quit; relay and settings wrapper stayed alive")
            subprocess.run([str(browser), "--quit", str(relay_pid if target == "relay" else browser_pid)], check=True)
            wait_for(quit_seen.exists, "Browser did not receive normal Quit")
            wait_for(cleanup.exists, "Settings wrapper did not finish after browser exit")
            wait_for(lambda: exited(relay_pid), "Relay did not exit after settings cleanup")
            assert exited(browser_pid), "Browser remained running"
            print(f"Quit via {target}: browser exited, wrapper cleaned up, relay exited")
    finally:
        cancel.unlink(missing_ok=True)
        if ready.exists():
            subprocess.run([str(browser), "--quit", ready.read_text()], check=False)
        subprocess.run([register, "-u", str(app)], check=False, capture_output=True)
