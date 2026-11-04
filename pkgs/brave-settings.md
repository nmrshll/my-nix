# Brave launcher on macOS

`brave-settings-runner.wrapBrave` extends nixpkgs' Brave package with queued
extension settings. Its shell launcher applies pending work before and after
Brave runs; Home Manager also adds a wrapper for command-line extension flags.

macOS needs a native URL handler at the bundle's registered executable path.
A shell entry point can register while web URLs fall back to Safari. Simply
execing a hidden native executable is also insufficient: the resulting
`executableURL` differs from `CFBundleExecutable`, so LaunchServices starts new
instances and URL events can be lost before Chromium forwards to its session.

`brave-url-relay.m` is installed as the final app executable. It runs the existing
launcher as a child, receives macOS open-URL events through AppKit, and passes
the URLs to the same launcher as command-line arguments. Chromium forwards
those arguments to its existing browser session. The relay exits when the main
browser child exits; the original settings lifecycle remains unchanged.

Dock Quit is delivered to this native relay too. Its termination delegate finds
the native browser in the same bundle beneath the waiting launcher wrappers and
asks that process to quit normally with `NSRunningApplication.terminate`. It
targets the process rather than the shared bundle ID to avoid sending Quit back
to itself. The relay stays alive if the browser cancels Quit; after a successful
Quit, the settings wrapper completes its post-exit work before the relay stops.
Bundle comparisons resolve symlinks, including macOS's `/var` and `/private/var`.

Dock reopen also targets that native browser process. The relay activates it
and forwards a native `aevt/rapp` reopen event to its PID, letting Chromium
restore an existing window or create one when all windows are closed. It never
starts another no-argument command-line launcher on a Dock click: that path
can create a new window and tab. The relay's own `hasVisibleWindows` value is
irrelevant because its windows belong to the separate browser process. If the
initial settings hook is still starting the browser, reopen retries discovery
for up to five seconds without launching another backend.

Home Manager adds its flags after `postInstall`, so `postFixup` installs the
relay after that wrapping, then seals the whole bundle with a local ad-hoc
signature. Framework symlinks are preserved. This does not restore the vendor's
signature.

`tests.lifecycle` covers the existing launcher's argument forwarding, deferred
settings, failure status, termination, and missing cache directories. Verify
URL delivery through macOS after rebuilding and restarting an already running
Brave; a handler-ID check alone cannot establish that the page opens.

Run `python3 pkgs/test-brave-url-relay.py <built-app>/Contents/MacOS/Brave\ Browser`
for an isolated live AppKit test. It sends actual HTTP and HTTPS open-URL events
to a temporary app with a fake browser backend, checks exact argument forwarding
and exit cleanup, then unregisters the test app. It also exercises plain
`open URL` using a custom test scheme and rejects extra empty backend launches
during URL forwarding. The temporary app is created under `~/Applications` so
LaunchServices can select it for that scheme. The test does not change the
HTTP/HTTPS default browser or read a real browser profile.

Run `python3 pkgs/test-brave-dock-quit.py <built-app>/Contents/MacOS/Brave\ Browser`
for the isolated live Quit regression test. It compiles `test-brave-browser.m`
as a native fake browser behind a waiting shell wrapper, sends the same normal
Quit request used by the Dock, and checks browser exit, wrapper cleanup, and
relay exit. It also checks browser-initiated Quit and cancellation followed by a
second Quit request. This test needs Xcode command-line tools and a logged-in
macOS GUI session; it never opens the real browser or accesses its profile.

The configured `mac2024` Brave package was rebuilt with the local `my-nix`
override and passed both live relay tests and strict bundle signature checks.
All seven settings-launcher tests passed. The Quit test also reproduced the
missing-forwarding failure against the previously installed launcher.

Run `python3 pkgs/test-brave-dock-reopen.py <built-app>/Contents/MacOS/Brave\ Browser`
for the isolated Dock reopen regression test. A native fake browser owns a real
window behind the waiting shell wrapper. Repeated reopen events must reuse its
window, and reopening after all windows close must create exactly one visible
window. Every case must leave the wrapper launch count at one. The test quits
its fake browser and unregisters its temporary bundle afterward.

On 2026-11-04 the configured package passed all three live relay tests, the
seven settings lifecycle checks, strict signature verification, and full
mac2024 derivation evaluation with the local my-nix override. The installed
older relay failed the reopen-forwarding assertion. This validates event
delivery and lifecycle with fake backends; the real Brave session still needs
a normal restart after switching, followed by a Dock click to confirm focus
without any change in window or tab counts. The real session was left running.

The browser setup requires ordinary external links to reuse an existing normal
Brave window as new tabs, allowing a new window when Brave is stopped or no
suitable window exists. The isolated test checks URL forwarding and extra
backend launches; real window counts and tab placement still need a browser
session test. See nix-home's `docs/findings/default-browser.md` for the
requirement and follow-up status.
