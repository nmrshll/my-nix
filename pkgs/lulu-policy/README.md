# LuLu profile manager

`pkgs.own.lulu-policy` writes an isolated `nix-safari-youtube` profile for the
already packaged, vendor-signed LuLu 4.2.0. Policy content comes from nix-home,
not this package. It adds no background job or listener.

LuLu 4.2 has no public policy CLI. Its XPC interface accepts only its signed
GUI client. This utility does not bypass that check. It writes the documented
on-disk profile layout only while the Network Extension is stopped, using the
`Rule` NSSecureCoding archive fields from the pinned source:

- [Rule.m](https://github.com/objective-see/LuLu/blob/828297e66e1c2df12f7ed79dfaa4320b5e610821/LuLu/Shared/Rule.m)
- [Rules.m](https://github.com/objective-see/LuLu/blob/828297e66e1c2df12f7ed79dfaa4320b5e610821/LuLu/Extension/Rules.m)
- [Preferences.m](https://github.com/objective-see/LuLu/blob/828297e66e1c2df12f7ed79dfaa4320b5e610821/LuLu/Extension/Preferences.m)

The writer checks the installed version before applying. Before an upgrade,
review the upstream schema and validate archives with Apple's secure
unarchiver and the actual LuLu application.

`apply POLICY.json` requires root. It keeps existing profiles and default
rules, saves the previous selection, and selects the generated profile.
Identical configurations are a no-op even while filtering is active; changed
configurations require disabling LuLu's extension first and re-enabling it
after application. Each file is replaced atomically, with the profile pointer
updated last. No daemon is forcibly restarted.

`restore POLICY.json` requires the extension to be stopped and restores the
previous profile selection without deleting either profile. `status` compares
the active profile's saved rules and preferences and reports extension state.
It cannot prove live traffic enforcement; verify behavior after activation.

Tests cover no writes while running, preserving old profiles, idempotence,
archive round-tripping, and drift detection.
