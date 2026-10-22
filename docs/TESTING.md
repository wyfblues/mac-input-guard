# Testing and acceptance

The compatibility standard is regression-based: an operation that works with protection off should still work with it on. Existing authorization requirements or pre-existing automation defects are separate observations, not automatically a regression introduced by this app.

## Automated tests

`scripts/test.sh` runs crypto/Keychain, physical-source policy, in-memory worker filtering, portable-path/approval-gate, and actual unlock target/action regression tests. It does not register an event tap, post events, enable protection, stop the installed personal app, or read its password item. Keychain tests use a random test service and delete only that item.

## Manual bounded checks

Use the app's 12-second preview. Do not use regular protection as a test substitute. Keep a separate recovery observer where possible; it may stop only the clearly identified bounded worker, never a regular protected session. Never ask an AI to enter a real password or change Accessibility permissions for the user.

Check physical keyboard/mouse, two-finger scrolling, desktop gestures, unlock-dialog entry and button activation, AI input/click/scroll, app switching, Finder opening, screenshots, and verification of the expected page. Verify that the same filter was active before and after each operation; actions crossing the automatic-release boundary do not count as protected-mode evidence. Confirm physical input recovers afterward.

Native Chrome can lose a window target after the operated window is closed. Activate a surviving window and re-read it; preserve user tabs. Native capture may return stale pixels. Use exact tab-bound state and screenshots for page content, and do not use a page screenshot as proof of native menus or system dialogs. Finder Desktop AX generic double-click can fail without protection; supported Open and normal-window double-click are distinct tested paths.

Serialize native control when other conversations use the same app. Do not stop or message other tasks without owner authorization. Discard mismatched or concurrent evidence rather than marking it passed.

## Scope of the alpha

The original personal prototype was exercised on one Apple silicon Mac with Codex. The shareable app has a separate identity, storage, and onboarding flow; the personal app's acceptance record is never bundled as approval for another machine.

A universal executable establishes compilation for two architectures, not Intel hardware acceptance. Actual reboot/login, fresh-machine Accessibility/Keychain authorization, full physical interception, and external download/Gatekeeper checks must be listed separately in release verification.
