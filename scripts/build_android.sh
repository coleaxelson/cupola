#!/usr/bin/env bash

# Builds Cupola for Android, the one way it is built anywhere: by
# scripts/release.sh on the Mac, and by any recipe that rebuilds a release from
# its source (an app store's build server, a reproducibility check). It builds
# and nothing else: no tests, no upload, no naming by release.
#
#   scripts/build_android.sh [all|apk|apk-arm64|aab]      (default: all)
#
# Writes to build/android/:
#   universal.apk   every ABI, for any phone
#   arm64-v8a.apk   64-bit ARM only, less than half the size
#   bundle.aab      the App Bundle that Google Play takes
#
# All three carry the same versionCode, the build number in pubspec.yaml, so a
# phone can move between them, and between the channels that carry them,
# without uninstalling. That is why the arm64 package is built with
# --target-platform and not --split-per-abi, which adds 1000 times an ABI
# number to the versionCode.
#
# Signing is Gradle's and happens only when android/key.properties exists
# (android/app/build.gradle.kts). A rebuild anywhere else produces unsigned
# packages, and scripts/release.sh refuses to ship one.
#
# FLUTTER names the flutter executable when it is not the one on PATH.

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FLUTTER="${FLUTTER:-flutter}"
TARGET="${1:-all}"
OUT_DIR="build/android"

case "$TARGET" in
  all|apk|apk-arm64|aab)
    ;;
  *)
    printf 'Usage: scripts/build_android.sh [all|apk|apk-arm64|aab]\n' >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"

# The same source built by another Flutter is another app: different engine,
# different snapshot. pubspec.yaml pins the version CI uses, and a rebuild must
# reproduce what we shipped.
WANT=$(awk '/^environment:/ { inside = 1; next } inside && /^[^ ]/ { inside = 0 } inside && $1 == "flutter:" { print $2 }' pubspec.yaml)
HAVE=$("$FLUTTER" --version --machine | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')
if [[ -z "$WANT" || "$HAVE" != "$WANT" ]]; then
  printf 'Flutter %s, but pubspec.yaml pins environment.flutter %s\n' "${HAVE:-unknown}" "${WANT:-nothing}" >&2
  exit 1
fi

printf '==> Getting Flutter packages from the lockfile...\n'
"$FLUTTER" pub get --enforce-lockfile

mkdir -p "$OUT_DIR"

# Flutter writes every APK to the same path: take each away before the next
# build replaces it, and never leave an earlier build where this one belongs.
build_apk() {
  local name=$1
  shift
  rm -f "$OUT_DIR/$name" build/app/outputs/flutter-apk/app-release.apk
  "$FLUTTER" build apk --release "$@"
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT_DIR/$name"
}

if [[ "$TARGET" == "all" || "$TARGET" == "apk" ]]; then
  printf '==> Building the universal APK...\n'
  build_apk universal.apk
fi

if [[ "$TARGET" == "all" || "$TARGET" == "apk-arm64" ]]; then
  printf '==> Building the arm64-v8a APK...\n'
  build_apk arm64-v8a.apk --target-platform android-arm64
fi

if [[ "$TARGET" == "all" || "$TARGET" == "aab" ]]; then
  printf '==> Building the App Bundle...\n'
  rm -f "$OUT_DIR/bundle.aab" build/app/outputs/bundle/release/app-release.aab
  "$FLUTTER" build appbundle --release
  cp build/app/outputs/bundle/release/app-release.aab "$OUT_DIR/bundle.aab"
fi

ls -l "$OUT_DIR"
