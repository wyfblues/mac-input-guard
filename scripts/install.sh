#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h}
task_source="$task_root/dist/MacInputGuard.app"
task_parent="${1:-$HOME/Applications}"
task_destination="$task_parent/MacInputGuard.app"
task_lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ ! -x "$task_source/Contents/MacOS/MacInputGuard" ]]; then print -u2 'Run scripts/build.sh first.'; exit 1; fi
if /usr/bin/pgrep -u "$(id -u)" -x MacInputGuard >/dev/null; then
  print -u2 'Unlock and quit MacInputGuard before installing or updating.'; exit 1
fi
/usr/bin/codesign --verify --strict "$task_source"
mkdir -p "$task_parent"
task_stage=$(/usr/bin/mktemp -d "$task_parent/.MacInputGuard-install.XXXXXX")
trap '/bin/rm -rf "$task_stage"' EXIT
/usr/bin/ditto "$task_source" "$task_stage/MacInputGuard.app"
/usr/bin/codesign --verify --strict "$task_stage/MacInputGuard.app"
task_backup=''
if [[ -e "$task_destination" ]]; then
  task_backup="$task_destination.backup.$(date +%Y%m%d%H%M%S)"
  if [[ -e "$task_backup" ]]; then print -u2 'Backup already exists; try later.'; exit 1; fi
  # A shortcut icon is separate from the running app's Dock icon. Retire the
  # old application record before replacing the entire signed bundle.
  if ! "$task_lsregister" -u "$task_destination"; then
    print -u2 'Warning: could not unregister the previous application record.'
  fi
  if ! mv "$task_destination" "$task_backup"; then
    "$task_lsregister" -f "$task_destination" || true
    exit 1
  fi
fi
if ! mv "$task_stage/MacInputGuard.app" "$task_destination"; then
  if [[ -n "$task_backup" ]]; then
    mv "$task_backup" "$task_destination"
    "$task_lsregister" -f "$task_destination" || true
  fi
  exit 1
fi
if ! "$task_lsregister" -f "$task_destination"; then
  print -u2 'Warning: app installed, but macOS application registration could not be refreshed.'
fi
print "Installed: $task_destination"
print 'Open the app to set your own password, grant Accessibility, and complete a 12-second compatibility review.'
