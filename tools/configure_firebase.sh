#!/usr/bin/env bash
set -euo pipefail

# Run from the Sanad workspace: bash tools/configure_firebase.sh PROJECT_ID
# Registers/reuses ONLY this app's iOS and Android apps in the chosen project.
# It does not create a Firebase project, deploy services, or enable Analytics.
if [[ $# -ne 1 || ! "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  printf 'Usage: bash tools/configure_firebase.sh YOUR_FIREBASE_PROJECT_ID\n' >&2
  exit 64
fi
if [[ ! -f pubspec.yaml || ! -f lib/core/firebase_bootstrap.dart ]]; then
  printf 'Run this command from the Sanad project root.\n' >&2
  exit 64
fi
if ! command -v firebase >/dev/null 2>&1; then
  printf 'Install the Firebase CLI first: https://firebase.google.com/docs/cli\n' >&2
  exit 69
fi
if command -v flutterfire >/dev/null 2>&1; then
  sanad_flutterfire=(flutterfire)
elif command -v dart >/dev/null 2>&1; then
  sanad_flutterfire=(dart pub global run flutterfire_cli:flutterfire)
else
  printf 'Install Flutter/Dart and flutterfire_cli before configuring Firebase.\n' >&2
  exit 69
fi

printf 'Configuring Sanad (app.fursa.fursa) for Firebase project %s.\n' "$1"
"${sanad_flutterfire[@]}" configure \
  --project="$1" \
  --platforms=ios,android \
  --ios-bundle-id=app.fursa.fursa \
  --ios-target=Runner \
  --android-package-name=app.fursa.fursa \
  --out=lib/firebase_options.dart \
  --ios-out=ios/Runner/GoogleService-Info.plist \
  --android-out=android/app/google-services.json \
  --yes

printf 'Configuration downloaded. Rebuild both mobile apps; see docs/firebase-setup.md for verification.\n'
