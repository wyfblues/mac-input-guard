#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h}
task_build="$task_root/.build/tests"
task_sources="$task_root/Sources/MacInputGuard"
mkdir -p "$task_build"
if ! mkdir "$task_build/test.lock" 2>/dev/null; then print -u2 'Tests already active.'; exit 1; fi
trap 'rmdir "$task_build/test.lock"' EXIT
task_common=("$task_sources/AppPaths.swift" "$task_sources/CompatibilityApproval.swift")
task_frameworks=(-framework AppKit -framework Security -framework OpenDirectory -framework Carbon -framework ServiceManagement)
xcrun swiftc -swift-version 5 $task_common "$task_sources/PrivacyCore.swift" \
  "$task_root/Tests/test-core.swift" $task_frameworks -o "$task_build/core"
"$task_build/core"
xcrun swiftc -swift-version 5 "$task_sources/InputPolicy.swift" \
  "$task_root/Tests/test-input-policy.swift" -o "$task_build/policy"
"$task_build/policy"
xcrun swiftc -swift-version 5 "$task_sources/InputPolicy.swift" "$task_sources/InputWorker.swift" \
  "$task_root/Tests/test-input-worker.swift" -framework AppKit -o "$task_build/worker"
"$task_build/worker"
xcrun swiftc -swift-version 5 $task_common "$task_root/Tests/test-portability.swift" -o "$task_build/portability"
"$task_build/portability"
python3 - "$task_sources/main.swift" "$task_build/PrivacyDelegateSource.swift" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text().split('\nsignal(SIGPIPE,SIG_IGN)')[0]
s=s.replace('final class PrivacyDelegate:', 'class PrivacyDelegate:',1)
Path(sys.argv[2]).write_text(s)
PY
task_delegate_sources=("$task_sources"/*.swift)
task_delegate_sources=("${(@)task_delegate_sources:#$task_sources/main.swift}")
xcrun swiftc -swift-version 5 $task_delegate_sources "$task_build/PrivacyDelegateSource.swift" \
  "$task_root/Tests/test-unlock-action.swift" $task_frameworks -o "$task_build/unlock"
"$task_build/unlock"
print 'All non-intercepting tests passed. No physical input was blocked.'
