# mobile_scanner, Cupola's copy

This is [mobile_scanner](https://github.com/juliansteenbakker/mobile_scanner)
7.4.2 by Julian Steenbakker and its contributors (BSD-3-Clause, see `LICENSE`),
with one change: **on Android it reads codes with
[zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) instead of Google ML Kit.**

Cupola uses it for one screen, *Copy from another device*, which reads the QR
code another device shows. Upstream's Android decoder is Google ML Kit's
bundled barcode scanner: it is proprietary, it reports diagnostics and usage to
Google with no way to turn that off, and it keeps the app out of F-Droid and
IzzyOnDroid. zxing-cpp is free software (Apache-2.0), runs on the device and
sends nothing anywhere.

## What changed

Only the Android sources and this package's metadata. The iOS and macOS code
(Apple Vision) is upstream's, byte for byte. The Dart API and the web code are
upstream's too, laid out by our `dart format` (six files, line breaks only).

- `android/build.gradle.kts`: `io.github.zxing-cpp:android:3.1.1` from Maven
  Central replaces ML Kit, in both of upstream's variants (bundled and
  through Google Play services); the unit test setup is gone with the tests.
- `android/proguard-rules.pro`: ML Kit's keep rules removed; zxing-cpp's AAR
  ships its own.
- `MobileScanner.kt`: each camera frame is read by `zxingcpp.BarcodeReader`
  on the analysis thread; a still image (`analyzeImage`) is decoded off the
  main thread. The camera, preview, torch, zoom, lifecycle and the scan window
  are upstream's code.
- `MobileScannerHandler.kt`: the decoder options are zxing-cpp's.
- `MobileScannerUtilities.kt`: a zxing-cpp result becomes the map the Dart
  side reads.
- `objects/BarcodeFormats.kt`: the same format integers as upstream, each
  paired with its zxing-cpp format.
- `analysis_options.yaml`: upstream's include of `very_good_analysis`, which
  Cupola does not depend on, removed. Cupola's own analysis skips this folder.
- Removed: `example/`, `test/`, `android/src/test/` (written against ML Kit's
  types), and upstream's repository files that do not apply here.

## What Android no longer does

- **Structured values.** zxing-cpp decodes a code and does not interpret it:
  `Barcode.type` is `unknown`, and the contact, Wi-Fi, URL, calendar, email,
  phone, SMS, geo point and driver licence fields are `null`. `rawValue`,
  `displayValue`, `rawBytes`, `format` and `corners` are filled.
- **Auto zoom** (`autoZoom`), which was a feature of ML Kit's decoder.

`invertImage` still works: zxing-cpp reads light-on-dark codes itself
(`tryInvert`) instead of the plugin inverting every frame.

## Keeping it

`test/tool/android_dependency_guard_test.dart` fails if any Android plugin the
app builds names ML Kit, Google Play services or Firebase in its Gradle files.

To move to a newer upstream release, copy that release over this folder
without `example/`, `test/` and `android/src/test/`, then apply the changes
listed above again. They live in the files named there; everything else
should be upstream's. Compare with the release in `~/.pub-cache` to see the
whole difference.
