import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android ships no Google library: **no Gradle file of the app or of an
/// Android plugin it builds names ML Kit, Google Play services or Firebase.**
///
/// mobile_scanner from pub.dev reads codes with Google ML Kit, which is
/// proprietary and reports diagnostics and usage to Google with no way to
/// turn it off. Cupola builds its own copy (`packages/mobile_scanner`), which
/// reads them with zxing-cpp. Pointing the dependency back at pub.dev, or
/// adding a plugin that pulls one of these libraries, would bring the
/// reporting back without a single visible change.
///
/// The Gradle text is what is checked, not only what ends up in the APK:
/// F-Droid's scanner reads the plugins' Gradle files too, and refuses a build
/// whose plugin names ML Kit even in a branch that is never taken.
void main() {
  final google = RegExp(
    r'com\.google\.mlkit|com\.google\.android\.gms|play-services|'
    r'com\.google\.firebase',
  );

  List<Map<String, Object?>> androidPlugins() {
    final file = File('.flutter-plugins-dependencies');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'flutter pub get writes .flutter-plugins-dependencies; run it.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final plugins = json['plugins']! as Map<String, Object?>;
    return (plugins['android']! as List<Object?>).cast<Map<String, Object?>>();
  }

  Iterable<File> gradleFiles(Directory android) => android
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) => f.path.endsWith('.gradle') || f.path.endsWith('.gradle.kts'),
      )
      .where(
        (f) => !f.path.contains(
          '${Platform.pathSeparator}build${Platform.pathSeparator}',
        ),
      );

  test('mobile_scanner is our copy, not the one from pub.dev', () {
    final scanner = androidPlugins().singleWhere(
      (p) => p['name'] == 'mobile_scanner',
    );
    final path = Directory(scanner['path']! as String).absolute.path;
    expect(
      path,
      endsWith(
        'packages${Platform.pathSeparator}mobile_scanner${Platform.pathSeparator}',
      ),
      reason:
          'pubspec.yaml must keep mobile_scanner on path: '
          'packages/mobile_scanner (see its README).',
    );
  });

  test('no Android plugin names a Google library in its Gradle files', () {
    final offenders = <String>[];
    for (final plugin in androidPlugins()) {
      final android = Directory('${plugin['path']}android');
      if (!android.existsSync()) continue;
      for (final file in gradleFiles(android)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (google.hasMatch(lines[i])) {
            offenders.add('${plugin['name']}: ${file.path}:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test("the app's own Gradle files name no Google library", () {
    final offenders = [
      for (final file in gradleFiles(Directory('android')))
        if (google.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
