# Privacy and security boundaries

Mac Input Guard is a convenience filter for casual local input. It is not a secure lock, kiosk, endpoint-security agent, or replacement for the macOS login window. It does not conceal the screen. Event source metadata is a heuristic, not an authentication credential.

The physical-input worker uses a session event tap. Common physical signatures are filtered; known automated and unknown nonphysical sources are allowed through. Trackpad gesture values include empirically observed raw event types that may differ across devices or OS releases. Administrators, process termination, restart, injection software, and some hardware/system actions can bypass this mechanism.

The app deliberately releases input when parent/child health or its lease fails, rather than risking a permanently unusable desktop. A released filter means protection stopped. It must not still be reported as active.

The unlock exception is limited to the app's visible, key unlock or password-recovery window while the app is foreground. It does not periodically reactivate itself. Physical scrolling and desktop-switch gestures remain blocked in that exception.

Protection passwords use a random 32-byte salt and PBKDF2-HMAC-SHA256 with 600,000 rounds. Only the salt and verifier are stored in a nonsynchronizing local Keychain item. Passwords are never sent to a server. The minimum is three characters for convenience, but short passwords are easy to guess; users should choose a longer password. Recovery verifies only the currently signed-in local account through OpenDirectory and does not modify the system password.

Status files contain modes, process IDs, health, timestamps, and aggregate input-category counts. They do not contain typed text, passwords, clipboard data, screen images, or event coordinates. An unlock-window rectangle exists transiently in the parent/worker lease; it is not logged. Data directories use owner-only permissions, and status/approval files use mode 600.

There are no network calls, analytics, automatic updates, or background model pollers. Optional Codex instructions are documentation; the app does not install or modify any AI tool's configuration.

For a possible security issue, avoid posting passwords, Keychain exports, or private screen recordings. A private reporting destination must be added by the eventual repository owner before a public security-reporting channel is advertised.
