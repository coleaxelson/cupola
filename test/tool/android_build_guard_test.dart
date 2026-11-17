import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android is built one way: **`scripts/build_android.sh`**, for every channel.
///
/// GitHub carries a universal APK and an arm64 APK, Google Play takes the App
/// Bundle, and an app store that rebuilds from source runs the same script. A
/// phone moves between them without uninstalling only while all of them carry
/// the same versionCode and our key, and a rebuild matches our APK byte for
/// byte only while both run the same commands. Three ways to break that
/// without a visible change: a second `flutter build` somewhere else,
/// `--split-per-abi` (it adds 1000 times an ABI number to the versionCode), and
/// the Gradle plugin's dependency block in the APK (encrypted for Google, it
/// differs from one build to the next and app stores flag it).
void main() {
  test('release.sh builds Android only through build_android.sh', () {
    final release = File('scripts/release.sh').readAsStringSync();
    expect(release, contains('scripts/build_android.sh'));
    for (final command in ['flutter build apk', 'flutter build appbundle']) {
      expect(
        release.contains(command),
        isFalse,
        reason:
            'release.sh runs `$command` itself: build through '
            'scripts/build_android.sh so every channel gets the same package.',
      );
    }
  });

  test('no Android package is split per ABI', () {
    final build = File('scripts/build_android.sh').readAsStringSync();
    // The header explains why the flag is absent; only commands count.
    final commands = build
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    expect(
      commands.contains('--split-per-abi'),
      isFalse,
      reason:
          '--split-per-abi gives each APK a versionCode of 1000 times its ABI '
          'number plus the build number: a phone could no longer move to the '
          'universal APK or to Google Play.',
    );
    expect(commands, contains('--target-platform android-arm64'));
  });

  test('the APK leaves out the dependency block', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      RegExp(
        r'dependenciesInfo\s*\{[^}]*includeInApk\s*=\s*false',
      ).hasMatch(gradle),
      isTrue,
      reason:
          'android/app/build.gradle.kts must keep '
          '`dependenciesInfo { includeInApk = false }`.',
    );
  });
}
