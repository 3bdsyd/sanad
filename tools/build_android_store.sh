#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_file="$project_root/android/key.properties"

if [[ ! -f "$signing_file" ]]; then
  printf 'Missing Android signing configuration: %s\n' "$signing_file" >&2
  exit 1
fi

python3 - "$signing_file" "$project_root" <<'PY'
import sys
from pathlib import Path
signing_path, root_path = map(Path, sys.argv[1:])

signing = {}
for line in signing_path.read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        signing[key.strip()] = value.strip()

required = ("storeFile", "storePassword", "keyAlias", "keyPassword")
missing = [key for key in required if not signing.get(key)]
if missing:
    raise SystemExit("Android signing is missing: " + ", ".join(missing))

keystore = Path(signing["storeFile"])
if not keystore.is_absolute():
    keystore = root_path / "android/app" / keystore
if not keystore.is_file():
    raise SystemExit("The release keystore named in android/key.properties was not found")
PY

cd "$project_root"
flutter build appbundle --release

printf 'Store bundle ready: %s\n' \
  "$project_root/build/app/outputs/bundle/release/app-release.aab"
