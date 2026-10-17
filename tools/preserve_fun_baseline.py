"""Hash the confirmed fun build and source without writing to either."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FUN = Path('C:/repos/BasedFootball-Recovery')
EVIDENCE = ROOT / 'evidence' / 'fun-baseline'

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()

def inspect():
    tracked = subprocess.check_output(['git', '-C', str(FUN), 'ls-files', '-z']).decode().split('\0')
    paths = [FUN / name for name in tracked if name]
    release = FUN / 'build/recovered-2d5d7ad-cd49e926e66acbf2'
    paths.extend(release / name for name in ['BasedFootball.exe', 'BasedFootball.pck', 'recovery-installation.json'])
    desktop = Path(os.environ['USERPROFILE']) / 'Desktop'
    paths.extend(desktop / name for name in ['Based Football.lnk', 'Based Football - Recovered 3v3.lnk'])
    profile = Path(os.environ['APPDATA']) / 'BasedFootball-Recovered-3v3'
    if profile.exists():
        paths.extend(profile.glob('*.json'))
    return {str(path): {'sha256': digest(path), 'size': path.stat().st_size}
            for path in paths if path.is_file()}

EVIDENCE.mkdir(parents=True, exist_ok=True)
(ROOT / 'evidence/.gdignore').touch(exist_ok=True)
baseline = EVIDENCE / 'before.json'
if sys.argv[1:] == ['record']:
    with baseline.open('x', encoding='utf-8') as handle:
        json.dump({'fun_commit': 'efbc4cabf201f4036effe9bd01c1108cc7f204ab', 'files': inspect()}, handle, indent=2)
    print('FUN_BASELINE_RECORDED')
elif sys.argv[1:] == ['verify']:
    before = json.loads(baseline.read_text(encoding='utf-8'))['files']
    changed = [name for name, record in before.items()
               if not Path(name).is_file() or digest(Path(name)) != record['sha256']]
    print(json.dumps({'unchanged': not changed, 'checked_files': len(before), 'changed': changed}, indent=2))
    sys.exit(1 if changed else 0)
else:
    raise SystemExit('Use record or verify.')
