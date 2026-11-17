import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/fold.dart';

// The opened iPhone Duo: 951 x 669, creased down the middle.
const _screen = Size(951, 669);
const _fold = DisplayFeature(
  bounds: Rect.fromLTRB(475.5, 0, 475.5, 669),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

Future<void> _pumpOpened(
  WidgetTester tester,
  Widget child, {
  bool folded = true,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(displayFeatures: folded ? const [_fold] : const []),
        child: FoldHost(child: app!),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

Widget _row() => const Padding(
  padding: EdgeInsets.only(left: 118),
  child: Align(
    alignment: Alignment.topLeft,
    child: ClearOfFold(
      maxWidth: 440,
      child: SizedBox(key: Key('row'), height: 48, width: double.infinity),
    ),
  ),
);

void main() {
  group('ClearOfFold', () {
    testWidgets('stops a row short of the crease it would cross', (
      tester,
    ) async {
      await _pumpOpened(tester, _row());
      final row = tester.getRect(find.byKey(const Key('row')));
      expect(row.left, 118);
      expect(row.right, 475.5 - Fold.clearance);
    });

    testWidgets('leaves it its full width with no fold', (tester) async {
      await _pumpOpened(tester, _row(), folded: false);
      expect(tester.getRect(find.byKey(const Key('row'))).width, 440);
    });
  });

  testWidgets('a dialog opens in one half, not across the crease', (
    tester,
  ) async {
    await _pumpOpened(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const Dialog(
              child: SizedBox(key: Key('dialog'), width: 300, height: 200),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byKey(const Key('dialog')));
    expect(
      dialog.right <= 475.5 || dialog.left >= 475.5,
      isTrue,
      reason: 'the dialog at $dialog crosses the fold',
    );
  });

  group('FoldHost on iOS', () {
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FoldHost.channel, null);
    });

    Future<List<DisplayFeature>> features(
      WidgetTester tester,
      Object? answer,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FoldHost.channel, (call) async => answer);
      late List<DisplayFeature> seen;
      await tester.pumpWidget(
        FoldHost(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.displayFeaturesOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      return seen;
    }

    testWidgets('publishes the fold the native side reports', (tester) async {
      final seen = await features(tester, {
        'axis': 'vertical',
        'at': 475.5,
        'from': 0.0,
        'to': 669.0,
        'flat': true,
      });
      expect(seen, hasLength(1));
      expect(seen.single.type, DisplayFeatureType.fold);
      expect(
        seen.single.bounds,
        const Rect.fromLTRB(
          475.5 - Fold.clearance,
          0,
          475.5 + Fold.clearance,
          669,
        ),
        reason: 'the line, widened to the band controls keep out of',
      );
      expect(seen.single.state, DisplayFeatureState.postureFlat);
    }, variant: ios);

    testWidgets('publishes nothing while the device is closed', (tester) async {
      expect(await features(tester, null), isEmpty);
    }, variant: ios);
  });
}
