---
name: mac-input-guard
description: "Use when managing Mac Input Guard or automating a Mac with its physical-input protection enabled. Check state, preserve protection, use tested browser/Finder paths, and run only explicitly authorized bounded compatibility tests."
---

# Mac Input Guard

Locate the user's installed `MacInputGuard.app` in their Applications folder or `/Applications`. Do not assume another user's absolute home path. `scripts/control.sh` from this project accepts `MAC_INPUT_GUARD_APP` to select the exact app.

Before local UI work, run its `--status` command without opening controls or enabling protection. Read the project's testing and security notes when testing or diagnosing compatibility. Ordinary UI work is not authorization to enable protection, start a test, rebuild the app, or change permissions.

Use supported CUA interfaces for UI actions. Prefer exact browser-tab bindings, page state, and tab screenshots for page content. Compare actual pixels with expected text. Native screenshot success alone may return stale content; tab screenshots cannot validate native menus or system dialogs.

Preserve a live Chrome window. Close only owned temporary tabs. If native lookup times out after a window closes, activate a surviving window through UI and obtain fresh state. If the tree is a menu exposing Cancel, cancel it before locating window controls. Never kill Chrome or reset shared automation services as an automatic workaround.

For Finder Desktop items, use an exposed Open secondary action and verify the result. Use a standard Finder window if a real double-click is needed. Preserve the user's files, windows, and work.

Check whether another conversation is operating the same native app before driving menus or file dialogs. Exact tab IDs do not isolate native focus. Wait for the other task or ask the owner to arrange priority. Never stop or message another conversation without authorization.

Never terminate regular protection or enter the owner's password. Do not weaken input filtering to make automation work. For explicitly authorized tests, use only the 12-second preview, verify the same active worker before/after each action, check automatic release, and ask the owner to confirm physical-input recovery. Physical checks require real owner participation. Do not fabricate approval files or inherit another machine's results.

The app does not prevent sleep or replace the system lock. Existing permission requirements and baseline tool failures are separate from regressions introduced by protection. Report only tested compatibility, not universal guarantees.
