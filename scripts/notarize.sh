#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h}
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your existing notarytool Keychain profile}"
task_app="$task_root/dist/MacInputGuard.app"
task_cert=$(/usr/bin/codesign -dv --verbose=2 "$task_app" 2>&1)
[[ "$task_cert" == *'Authority=Developer ID Application:'* ]] || {
  print -u2 'Build with a Developer ID Application signing identity first.'; exit 1
}
task_zip="$task_root/.build/notary-upload.zip"
/usr/bin/ditto -c -k --keepParent "$task_app" "$task_zip"
xcrun notarytool submit "$task_zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$task_app"
xcrun stapler validate "$task_app"
"$task_root/scripts/package.sh" --skip-build
print 'Notarized app repackaged. No credentials were saved in this repository.'
