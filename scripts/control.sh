#!/bin/zsh
set -euo pipefail
task_app="${MAC_INPUT_GUARD_APP:-$HOME/Applications/MacInputGuard.app}"
if [[ ! -d "$task_app" && -d /Applications/MacInputGuard.app ]]; then task_app=/Applications/MacInputGuard.app; fi
if [[ ! -x "$task_app/Contents/MacOS/MacInputGuard" ]]; then
  print -u2 'MacInputGuard is not installed; set MAC_INPUT_GUARD_APP to the app path.'; exit 1
fi
case "${1:-status}" in
  setup) /usr/bin/open -a "$task_app" ;;
  status) "$task_app/Contents/MacOS/MacInputGuard" --status ;;
  diagnostics) "$task_app/Contents/MacOS/MacInputGuard" --diagnostics ;;
  preview) /usr/bin/open -a "$task_app" 'macinputguard://preview' ;;
  protect) /usr/bin/open -a "$task_app" 'macinputguard://protect' ;;
  *) print -u2 'Usage: control.sh setup|status|diagnostics|preview|protect'; exit 2 ;;
esac
