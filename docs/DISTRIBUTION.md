# Build and distribution

## Local development artifacts

`scripts/build.sh` builds both CPU architectures by default and signs with an ad-hoc identity. `scripts/package.sh --skip-build` creates a DMG, an app ZIP, a source ZIP, and `SHA256SUMS.txt` under `dist/`. It does not publish or upload anything.

The public repository currently distributes source only. CI builds and tests the code, without uploading development app artifacts. Prebuilt public binaries remain pending Developer ID signing, notarization, and release acceptance.

Development artifacts are usable for source review and local evaluation. They are not a claim of Gatekeeper acceptance or Apple notarization. A download can be quarantined and blocked. Never ship scripts that disable Gatekeeper or strip quarantine to hide this distinction.

## Developer ID and notarization

Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Use a Developer ID Application certificate, hardened runtime, a timestamped signature, and the notary service for a normal public distribution workflow.

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh
NOTARY_PROFILE='your-existing-profile' ./scripts/notarize.sh
```

`notarize.sh` uploads the app ZIP to Apple only when explicitly run. It expects an existing notarytool Keychain profile. Never put certificate files, passwords, API keys, account identifiers, or notary credentials in the repository, workflows, issue comments, or release notes. Do not use another team's signing identity without authorization.

The script waits for notarization, staples and validates the app ticket, then regenerates distribution archives. Validate the final downloaded artifact on a separate Mac. A signature check alone is not a fresh-install or Gatekeeper acceptance test.

## Release checklist

- Review the source, license, bundle identity, version, and exact release text.
- Run the non-intercepting tests and inspect both architectures.
- Exercise setup, Accessibility, Keychain authorization, login startup, local compatibility review, and uninstall on a separate user or test Mac.
- Use only bounded previews for physical-input and automation testing; confirm input recovers.
- State which CPU/OS/automation combinations were actually tested.
- Sign and notarize a normal public binary; verify the final artifacts and hashes.
- Inspect the source archive for local paths, credentials, runtime files, screenshots, and personal data.
- Publish only with explicit owner authorization; do not treat building as permission to push.

An OS, build policy, or automation-backend change requires renewed compatibility review. Re-signing an ad-hoc build may require fresh local permissions; keep the application identity stable for normal releases.
