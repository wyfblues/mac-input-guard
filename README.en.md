# Mac Input Guard

**[English](README.en.md) | [简体中文](README.md#简体中文)**

Keep AI working on your Mac while limiting casual physical keyboard, mouse, and trackpad input.

Mac Input Guard is a small macOS menu bar app. Your desktop remains visible. When you step away, press **Control + Option + Command + L** to enable input protection; use your independent protection password to unlock it when you return. Optional login startup stays idle in the background and never enables protection automatically.

**Current version: 0.1.0-alpha.1.** This early preview is intended for users willing to complete compatibility checks on their own Mac. The application UI is currently Chinese; this documentation is available in English and Simplified Chinese.

**Source-only release:** prebuilt apps will be provided after Developer ID signing, notarization, and release acceptance. CI builds and tests the source without uploading development installers.

## Features

- Limit ordinary physical keyboard and mouse input, two-finger scrolling, and three-/four-finger desktop switching.
- Keep the screen visible, without a fullscreen cover, recurring focus grabs, or suspension of builds, tests, or other background processes.
- Use an independent protection password. Change it by verifying the old password, or reset it after verifying the current local Mac account's login password.
- Store a salted password verifier in the local Keychain, rather than the protection password in plaintext.
- Try a preview that automatically ends after 12 seconds. Complete the local compatibility review before enabling regular protection.
- Keep input filtering in a child process. Release input if parent/child heartbeats or the lease fail. Manual sleep, display sleep, or session deactivation also ends protection.

## Installation and first use

For now, build from source using the commands below, then run `./scripts/install.sh` to install into your user's Applications directory. When notarized installers are available, you will also be able to drag `MacInputGuard.app` from the disk image into `Applications`.

1. Set your own protection password locally. The minimum is three characters; choose a longer password that you do not reuse for another account.
2. Add and enable **MacInputGuard** in **System Settings → Privacy & Security → Accessibility**. The app's **辅助功能设置** (Accessibility settings) button opens the settings page; you must grant access yourself.
3. Run **测试 12 秒** (12-second test). Check that physical input is blocked and automatically restored after the full countdown. A test starts only while the display is awake and the session is unlocked.
4. Use further bounded tests to check the unlock dialog, trackpad, and your usual AI automation. Compare the same operation with protection off and on: anything that worked before should still work during protection.
5. Open **兼容性检查** (Compatibility review), select only the items you personally verified, and save. Results from another Mac cannot replace your checks.
6. Optionally enable **登录后在后台待命** (Start idle in the background at login). Use the shortcut when leaving, and enter your protection password in the small unlock window when returning. During protection, the shortcut only shows the unlock window; it does not unlock the app.

Click **结束测试** (End test) to stop a preview early. An early stop does not satisfy the full 12-second automatic-recovery check. The app will not report regular protection as successful when permissions are missing, the compatibility review is incomplete, or filter health has failed.

The app does not prevent sleep or change system sleep, auto-lock, or password policies.

## Build and test

Requires macOS 13 or later, Xcode Command Line Tools (including the Swift compiler), and Python 3. The built app does not require Python, Codex, or a network service to run.

```sh
./scripts/build.sh                 # Universal: Apple silicon + Intel
./scripts/test.sh                  # No posted events or physical-input interception
./scripts/package.sh --skip-build  # DMG, app ZIP, source ZIP, SHA-256 checksums
./scripts/install.sh               # Install into the current user's Applications
```

You can also build a single architecture with `./scripts/build.sh arm64` or `./scripts/build.sh x86_64`. Tests use fictitious passwords. Keychain tests use randomly named UUID test entries and delete them afterward; they do not read an existing user's password record.

```sh
./scripts/control.sh status
./scripts/control.sh diagnostics
./scripts/control.sh setup
./scripts/control.sh preview       # 12 seconds; refuses to replace regular protection
```

See [distribution instructions](docs/DISTRIBUTION.md) for signing, notarization, and release steps. A development build without a Developer ID signature is not a notarized release. Gatekeeper may block an internet-downloaded development build. Do not disable system security protections to open it.

## AI tool integration

The app does not require a Codex skill. If you want accompanying Codex workflow guidance, review the [optional skill](integrations/codex/SKILL.md) and [global-instruction fragment](integrations/codex/AGENTS.fragment.md), then decide whether to install them yourself.

For browser pages, prefer exact tab bindings and compare page state with tab screenshots. For Finder Desktop icons, prefer an exposed Open action. These are workflow mitigations for observed native-tool limitations, not changes to browser or Codex internals.

## Local data and uninstalling

Local status and compatibility approval are stored in `~/Library/Application Support/MacInputGuard/`. The password verifier is stored in the current user's local Keychain. The app has no analytics, automatic updater, network endpoint, or key-text logging. See [privacy and security boundaries](docs/SECURITY.md).

Unlock protection yourself and quit the app from its menu bar before uninstalling:

```sh
./scripts/uninstall.sh
```

The script disables this app's login startup and moves the app to Trash. It retains your local password verifier and configuration for reinstalls. To remove those as well, manually delete the app's data directory and, in Keychain Access, the entry for service `org.macinputguard.password-verifier`. Do not delete other apps' data.

## Compatibility and limits

This is a convenience tool that discourages casual local interaction, **not a secure macOS system lock**. It does not hide screen content. Administrators, process termination, restart, input-injection tools, and some system hardware actions can bypass it. Input source metadata is not an authentication credential.

Distinguishing physical trackpad events from automation depends on the OS, hardware, and automation backend. Compatibility with every Mac, AI tool, or remote-control method is not guaranteed. Each Mac needs its own bounded checks, and an OS version change requires renewed confirmation. Compilation for an architecture does not establish hardware acceptance. See [testing and acceptance](docs/TESTING.md).

## License

[MIT License](LICENSE).
