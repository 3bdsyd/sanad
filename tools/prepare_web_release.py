#!/usr/bin/env python3
"""Package a verified Flutter web build locally. Never connects or publishes."""
import argparse
import hashlib
import json
import re
import shutil
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('release', help='Release tag embedded in HTML and bootstrap')
args = parser.parse_args()
if not re.fullmatch(r'[0-9]{8}[a-z][a-z0-9]*', args.release):
    parser.error('Use a release tag such as 20261103c')
source = root / 'build/web'
for name in ['index.html', 'flutter_bootstrap.js']:
    if args.release not in (source / name).read_text():
        raise SystemExit(f'{name} does not contain {args.release}; rebuild first')
for name in ['main.dart.js', '.htaccess', 'app-ads.txt', 'privacy/index.html', 'support/index.html']:
    if not (source / name).is_file():
        raise SystemExit(f'Missing {name}; do not package an incomplete build')
target = root / 'build/review' / f'web-release-{args.release}'
target.mkdir(parents=True, exist_ok=True)
files = sorted(p for p in source.rglob('*') if p.is_file())
manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(source).as_posix() + '\n' for p in files)
(target / 'FILES.sha256').write_text(manifest)
with tarfile.open(target / 'assets.tar.gz', 'w:gz') as archive:
    for path in files:
        if path.name == 'index.html' and path.parent == source:
            continue
        archive.add(path, arcname=path.relative_to(source), recursive=False)
shutil.copy2(source / 'index.html', target / 'index.html')
(target / 'release.json').write_text(json.dumps({
    'release': args.release, 'destination': 'https://jobsnad.com',
    'remote_root': 'domains/jobsnad.com/public_html',
    'published': False, 'files': len(files),
    'manifest_sha256': hashlib.sha256(manifest.encode()).hexdigest(),
    'procedure': 'Backup outside webroot; overlay assets without deleting unrelated files; index.html last; verify remote and HTTPS hashes.',
}, ensure_ascii=False, indent=2) + '\n')
print(f'Prepared {len(files)} files: {target}. No network access or publication.')
