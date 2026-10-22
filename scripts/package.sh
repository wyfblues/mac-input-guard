#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h}
if [[ "${1:-}" != --skip-build ]]; then "$task_root/scripts/build.sh"; fi
task_version=$(cat "$task_root/VERSION")
task_dist="$task_root/dist"
task_app="$task_dist/MacInputGuard.app"
/usr/bin/codesign --verify --strict "$task_app"
task_stage=$(/usr/bin/mktemp -d /tmp/mac-input-guard-package.XXXXXX)
trap '/bin/rm -rf "$task_stage"' EXIT
/usr/bin/ditto "$task_app" "$task_stage/MacInputGuard.app"
ln -s /Applications "$task_stage/Applications"
cp "$task_root/docs/INSTALL.txt" "$task_stage/INSTALL.txt"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_dist/MacInputGuard-$task_version-macos.zip"
/usr/bin/hdiutil create -volname 'Mac Input Guard' -srcfolder "$task_stage" -format UDZO \
  -ov "$task_dist/MacInputGuard-$task_version-macos.dmg" >/dev/null
python3 - "$task_root" "$task_version" <<'PY'
from pathlib import Path
import sys,zipfile,hashlib,subprocess
root=Path(sys.argv[1]);version=sys.argv[2]
allowed_dirs={'Sources','Tests','scripts','docs','resources','integrations','.github'}
allowed_files={'.gitignore','LICENSE','README.md','README.en.md','RELEASE_NOTES.md','VERSION'}
if (root/'.git').exists():
 names=subprocess.check_output(['git','-C',str(root),'ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\0')
 candidates=[root/name for name in names if name]
else:
 candidates=list(root.rglob('*'))
with zipfile.ZipFile(root/'dist'/f'mac-input-guard-{version}-source.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(candidates):
  rel=p.relative_to(root)
  safe=rel.parts[0] in allowed_dirs or str(rel) in allowed_files
  private=any(part.startswith('.env') or part.endswith(('.local','.p12','.p8','.keychain','.keychain-db')) for part in rel.parts)
  generated=any(part in {'__pycache__','.DS_Store'} for part in rel.parts)
  if safe and not private and not generated and p.is_file() and not p.is_symlink():
   z.write(p,Path('mac-input-guard')/rel)
files=sorted(p for p in (root/'dist').iterdir() if p.suffix in ['.zip','.dmg'])
(root/'dist/SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
print('Packaged '+str(len(files))+' archives with SHA256SUMS.txt')
PY
