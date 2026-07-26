#!/usr/bin/env bash
# LifeOS bootstrap — run once after cloning.
#
#   ./tool/bootstrap.sh
#
# 1. Generates the native platform folders (android/, ios/, web/, ...). They are
#    intentionally not vendored: `flutter create` emits them for whatever Flutter
#    version you actually have, which avoids stale Gradle/CocoaPods pins.
# 2. Fetches packages.
# 3. Runs code generation for Drift, Freezed and json_serializable.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Generating platform folders (existing files are left untouched)"
flutter create . \
  --project-name lifeos \
  --org com.lifeos \
  --platforms=android,ios,web,macos,windows,linux

echo "==> flutter pub get"
flutter pub get

echo "==> build_runner"
dart run build_runner build --delete-conflicting-outputs

cat <<'EOF'

Done. Next steps:

  * Apply the native permission entries listed in docs/DEPLOYMENT.md
    (microphone, camera, location, notifications, biometrics).
  * Run with your configuration:

      flutter run --dart-define-from-file=tool/dart_define.example.json

    LifeOS starts fine with no configuration at all — it falls back to the
    local-only account and the on-device heuristic AI provider.
EOF
