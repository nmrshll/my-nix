"""Send Dock reopen events to an isolated relay with a native window backend.

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


with tempfile.TemporaryDirectory(prefix="brave-reopen-") as directory:
    root = Path(directory)
    app = root / "Reopen Test.app"
    contents = app / "Contents"
    executable = contents / "MacOS" / "relay"
    executable.parent.mkdir(parents=True)
    shutil.copyfile(sys.argv[1], executable)
    executable.chmod(0o755)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": "io.nixhome.brave-reopen-test",
                      "CFBundleName": "Brave Reopen Test",
                      "CFBundleVersion": "1.0", "CFBundleExecutable": "relay",
                      "CFBundlePackageType": "APPL"}, stream)
    browser = executable.with_name(".browser")
    subprocess.run(["/usr/bin/clang", "-Wall", "-Wextra", "-Werror", "-O2",
                    "-fobjc-arc", "-framework", "AppKit",
                    str(Path(__file__).with_name("test-brave-browser.m")), "-o", str(browser)], check=True)
    ready, quit_seen, cancel, cleanup, relay_pid_file = [
        root / name for name in ["ready", "quit", "cancel", "cleanup", "relay.pid"]]
    reopen, close, launches = [root / name for name in ["reopen", "close", "launches"]]
    wrapper = Path(str(executable) + "-launch-wrapped")
    wrapper.write_text("#!/bin/sh\n" + "\n".join([
        f"echo launch >> {shlex.quote(str(launches))}",
        f"export TEST_REOPEN={shlex.quote(str(reopen))}",
        f"export TEST_CLOSE={shlex.quote(str(close))}",
        f"export TEST_READY={shlex.quote(str(ready))}",
        f"export TEST_QUIT={shlex.quote(str(quit_seen))}",
        f"export TEST_CANCEL={shlex.quote(str(cancel))}",
        f"echo $PPID > {shlex.quote(str(relay_pid_file))}",
        shlex.quote(str(browser)),
        f"touch {shlex.quote(str(cleanup))}", ""]))
    wrapper.chmod(0o755)
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    register = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    browser_pid = None
    try:
        subprocess.run(["/usr/bin/open", "-n", str(app)], check=True)
        wait_for(ready.exists, "Native browser did not start")
        relay_pid = int(relay_pid_file.read_text())
        browser_pid = int(ready.read_text())
        for state in ["reused", "reused", "created"]:
            reopen.unlink(missing_ok=True)
            if state == "created":
                close.touch()
                wait_for(lambda: reopen.exists() and reopen.read_text() == "closed",
                         "Native browser did not close its window")
                reopen.unlink()
            # LaunchServices sends the same reopen event as clicking a running
            # app's Dock tile; the relay has no windows of its own.
            subprocess.run(["/usr/bin/open", str(app)], check=True)
            wait_for(reopen.exists, "Relay did not forward reopen to native browser")
            assert reopen.read_text() == f"{state}:1", reopen.read_text()
            assert launches.read_text().splitlines() == ["launch"], "Dock reopen launched another backend"
            print(f"Dock reopen: {state} one native window, no extra launcher invocation")
        subprocess.run([str(browser), "--quit", str(relay_pid)], check=True)
        wait_for(cleanup.exists, "Settings wrapper did not finish after browser exit")
        wait_for(lambda: exited(relay_pid), "Relay did not exit after settings cleanup")
    finally:
        cancel.unlink(missing_ok=True)
        if browser_pid is not None:
            subprocess.run([str(browser), "--quit", str(browser_pid)], check=False)
        if ready.exists():
            subprocess.run([str(browser), "--quit", ready.read_text()], check=False)
        subprocess.run([register, "-u", str(app)], check=False, capture_output=True)
