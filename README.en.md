# Mac Input Guard

A small macOS menu bar app that limits casual physical keyboard, mouse, and trackpad input while leaving the desktop visible and allowing tested automation paths to continue.

Version **0.1.0-alpha.1** is an early preview. The current UI is Chinese. See the [Chinese guide](README.md) for detailed setup.

Only source code is published at this stage. Prebuilt apps will follow Developer ID signing, notarization, and release acceptance. CI builds and tests the source without uploading development installers.

## Features

- Manual protection with **Control + Option + Command + L** and an independent password.
- No fullscreen cover, recurring focus grab, or background-process suspension.
- Physical wheel and trackpad gesture filtering, subject to per-machine testing.
- A bounded 12-second preview with parent/child heartbeat and lease-based release.
- Local Keychain password verifier, authenticated password change, and local-account password recovery.
- Optional login startup that stays idle in the background, without automatically enabling protection.
- Local compatibility review required before regular protection is enabled.

## Build

Requires macOS 13+, Xcode Command Line Tools and Python 3. The built app does not require Python, Codex, or a network connection.

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package.sh --skip-build
./scripts/install.sh
```

The default build is universal (arm64 and x86_64). Compilation does not establish hardware compatibility. Give the app Accessibility access yourself, set your own password, and complete the 12-second physical-input and automation checks on each Mac.

The app stores state in `~/Library/Application Support/MacInputGuard/`, and its password verifier in the local user's Keychain. It does not capture key text, clipboard content, screen content, or input coordinates in logs. It has no network endpoint, telemetry, or automatic updater.

Optional Codex integration is under `integrations/codex/`; it is not required to use the app and is not installed automatically.

## Distribution

See [distribution instructions](docs/DISTRIBUTION.md). An ad-hoc development build is not a Developer ID signed, notarized release. Gatekeeper may block an internet-downloaded development build. Do not disable system security protections.

## Important limits

This is a convenience input filter, **not a secure operating-system lock**. Content remains visible. Administrators, process termination, restart, other injection tools, and some system hardware actions can bypass it. Input metadata is not an authentication boundary. It does not manage sleep or auto-lock preferences.

Compatibility must be tested with the exact Mac, OS, input hardware, and automation backend. Native and browser-tab screenshots verify different surfaces. See [security and privacy](docs/SECURITY.md) and [testing](docs/TESTING.md).

Unlock and quit before uninstalling. `./scripts/uninstall.sh` moves the app to Trash and disables its login item, retaining local credentials and preferences for reinstalls.

[MIT License](LICENSE).
