# Media Curfew

Native macOS agent that closes mpv and VLC every day from **22:00 inclusive to
05:00 exclusive**, using the current local time zone. The policy is in
`Policy.swift`; the Nix package is exposed as `pkgs.own.media-curfew`.

The AppKit notice has one action, **Back to other apps**. It dismisses the notice
without changing enforcement. There is no snooze, extra time, unlock or quit
control. The program requires neither Accessibility nor Screen Recording access.

Launch and activation notifications trigger immediate checks. A one-second timer
also catches existing playback at 22:00 and terminal/audio-only processes. Wake
and session activation trigger checks; every check reads wall time again, so DST
and time-zone changes follow the Mac's current clock. An activity assertion stops
App Nap from delaying checks while still allowing the computer to sleep.

Targets match `io.mpv` / `org.videolan.vlc` bundle IDs or exact executable names
`mpv`, `mpv-unwrapped`, `vlc` (case insensitive), including Nix's dot-prefixed
`-wrapped` executables. Only processes owned by the agent's user are stopped.
The agent sends SIGTERM first, allowing normal player shutdown and mpv resume
saving, then SIGKILL if still running after two seconds. PID, owner, executable
and process start time are checked before signalling to avoid PID reuse.

This is a user-session restriction, not an execution authorization service. A
player can start briefly before being closed. Deliberately unloading the agent,
modifying its configuration, changing the clock or disguising an executable can
bypass it. The launchd service should use KeepAlive to recover from crashes.

## Validation

From the nix-home checkout, using its pinned nixpkgs and the local package repo:

```sh
nix build --impure --no-write-lock-file \
  --override-input my-nix path:/Users/me/src/scripts/my-nix \
  .#darwinConfigurations.mac2024.pkgs.own.media-curfew --no-link -L
```

The check phase exhausts every minute of the day in three time zones, checks the
London DST transitions and executable matching, and starts isolated dummy player
processes to verify enumeration, identity validation, SIGTERM and SIGKILL. It does
not change the clock or stop actual media players.
