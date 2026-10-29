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

The browser setup requires ordinary external links to reuse an existing normal
Brave window as new tabs, allowing a new window when Brave is stopped or no
suitable window exists. The isolated test checks URL forwarding and extra
backend launches; real window counts and tab placement still need a browser
session test. See nix-home's `docs/findings/default-browser.md` for the
requirement and follow-up status.
