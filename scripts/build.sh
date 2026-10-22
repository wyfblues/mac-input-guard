#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h}
task_arch="${1:-universal}"
case "$task_arch" in arm64|x86_64|universal) ;; *) print -u2 'Usage: build.sh [arm64|x86_64|universal]'; exit 2 ;; esac
task_build="$task_root/.build"
task_app="$task_root/dist/MacInputGuard.app"
mkdir -p "$task_build" "$task_root/dist"
if ! mkdir "$task_build/build.lock" 2>/dev/null; then
  print -u2 'Another build is active. Wait for it to finish.'; exit 1
fi
trap 'rmdir "$task_build/build.lock"' EXIT
task_arches=($task_arch)
if [[ "$task_arch" == universal ]]; then task_arches=(arm64 x86_64); fi
task_sources=("$task_root"/Sources/MacInputGuard/*.swift)
for task_cpu in $task_arches; do
  xcrun swiftc -swift-version 5 -O -target "$task_cpu-apple-macos13.0" \
    -module-cache-path "$task_build/module-cache-$task_cpu" \
    $task_sources -framework AppKit -framework Security -framework OpenDirectory \
    -framework Carbon -framework ServiceManagement -o "$task_build/MacInputGuard-$task_cpu"
done
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
if [[ "$task_arch" == universal ]]; then
  xcrun lipo -create "$task_build/MacInputGuard-arm64" "$task_build/MacInputGuard-x86_64" \
    -output "$task_app/Contents/MacOS/MacInputGuard"
else
  cp "$task_build/MacInputGuard-$task_arch" "$task_app/Contents/MacOS/MacInputGuard"
fi
python3 - "$task_root" "$task_app" <<'PY'
import plistlib,sys
from pathlib import Path
root,app=map(Path,sys.argv[1:])
version=(root/'VERSION').read_text().strip()
info={'CFBundleExecutable':'MacInputGuard','CFBundleIdentifier':'org.macinputguard.app',
 'CFBundleName':'MacInputGuard','CFBundleDisplayName':'Mac Input Guard',
 'CFBundlePackageType':'APPL','CFBundleVersion':'1',
 'CFBundleShortVersionString':version.split('-')[0],'MIGReleaseVersion':version,
 'NSHighResolutionCapable':True,'LSMinimumSystemVersion':'13.0','LSUIElement':True,
 'LSMultipleInstancesProhibited':True,'CFBundleIconFile':'AppIcon',
 'CFBundleURLTypes':[{'CFBundleURLName':'org.macinputguard.app','CFBundleURLSchemes':['macinputguard']}]}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
if [[ -f "$task_root/resources/AppIcon.icns" ]]; then
  cp "$task_root/resources/AppIcon.icns" "$task_app/Contents/Resources/"
fi
task_signing="${SIGNING_IDENTITY:--}"
if [[ "$task_signing" == - ]]; then
  /usr/bin/codesign --force --options runtime --sign - "$task_app"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$task_signing" "$task_app"
fi
/usr/bin/codesign --verify --strict "$task_app"
print "Built: $task_app"
