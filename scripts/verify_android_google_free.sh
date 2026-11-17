#!/usr/bin/env bash
# Fails when an Android package carries a Google library: ML Kit, Google Play
# services, Google's data transport or Firebase.
#
#   scripts/verify_android_google_free.sh <package.apk|package.aab>...
#
# Android ships none of them: the code scanner in Copy from another device
# reads with zxing-cpp (packages/mobile_scanner), and
# test/tool/android_dependency_guard_test.dart holds the Gradle files. This
# holds the packages themselves, whatever pulled a library in: their file
# names, the classes in their dex, and the APK's manifest.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: %s <package.apk|package.aab>...\n' "$(basename "$0")" >&2
  exit 2
fi

BUILD_TOOLS=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* | sort -V | tail -1)
GOOGLE='com/google/mlkit|com/google/android/gms|com/google/android/datatransport|com/google/firebase'

failed=0
for pkg in "$@"; do
  name=$(basename "$pkg")
  # Each reader reads its input to the end: under pipefail, a reader that
  # stopped early would turn the writer's SIGPIPE into a failed check.
  if unzip -Z1 "$pkg" | LC_ALL=C grep -Eic 'barhopper|mlkit' > /dev/null; then
    printf '%s carries ML Kit files:\n' "$name" >&2
    unzip -Z1 "$pkg" | LC_ALL=C grep -Ei 'barhopper|mlkit' >&2
    failed=1
  fi
  if unzip -p "$pkg" '*.dex' | LC_ALL=C grep -Eac "$GOOGLE" > /dev/null; then
    printf '%s carries Google classes:\n' "$name" >&2
    unzip -p "$pkg" '*.dex' | LC_ALL=C grep -Eao "$GOOGLE" | sort -u >&2
    failed=1
  fi
  if [[ "$pkg" == *.apk ]] &&
    "$BUILD_TOOLS/aapt2" dump xmltree "$pkg" --file AndroidManifest.xml |
    LC_ALL=C grep -Ec 'mlkit|datatransport|com\.google\.android\.gms|firebase' > /dev/null; then
    printf '%s declares Google components in its manifest\n' "$name" >&2
    failed=1
  fi
done

exit "$failed"
