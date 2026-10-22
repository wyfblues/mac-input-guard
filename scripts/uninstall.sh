#!/bin/zsh
set -euo pipefail
task_parent="${1:-$HOME/Applications}"
task_app="$task_parent/MacInputGuard.app"
if /usr/bin/pgrep -u "$(id -u)" -x MacInputGuard >/dev/null; then
  print -u2 'Unlock and quit MacInputGuard yourself before uninstalling.'; exit 1
fi
if [[ ! -x "$task_app/Contents/MacOS/MacInputGuard" ]]; then print -u2 'App not found at the requested location.'; exit 1; fi
task_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_app/Contents/Info.plist")
[[ "$task_bundle" == org.macinputguard.app ]] || { print -u2 'Unexpected application identity.'; exit 1; }
"$task_app/Contents/MacOS/MacInputGuard" --disable-login
task_trash="$HOME/.Trash/MacInputGuard.$(date +%Y%m%d%H%M%S).app"
[[ ! -e "$task_trash" ]] || { print -u2 'Trash destination exists; try later.'; exit 1; }
mv "$task_app" "$task_trash"
print 'Application moved to Trash. Your local password verifier and preferences are retained.'
