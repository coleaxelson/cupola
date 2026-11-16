import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/widgets/hide_owned_switch.dart';

/// One row, with or without its value: the switch comes into a place that
/// was kept for it.
void main() {
  Future<void> pump(
    WidgetTester tester,
    bool? value, {
    ValueChanged<bool>? onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(
        body: HideOwnedSwitch(value: value, onChanged: onChanged ?? (_) {}),
      ),
    ),
  );

  testWidgets('without a value the row has its words and its height, and '
      'no switch', (tester) async {
    await pump(tester, null);
    final waiting = tester.getSize(find.byType(HideOwnedSwitch));

    expect(find.text('Hide what I have'), findsOneWidget);
    expect(find.byType(Switch).hitTestable(), findsNothing);

    await pump(tester, false);
    expect(tester.getSize(find.byType(HideOwnedSwitch)), waiting);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the words do not move when the switch comes', (tester) async {
    await pump(tester, null);
    final before = tester.getRect(find.text('Hide what I have'));

    await pump(tester, true);

    expect(tester.getRect(find.text('Hide what I have')), before);
  });

  testWidgets('without a value the row takes no tap', (tester) async {
    var taps = 0;
    await pump(tester, null, onChanged: (_) => taps++);

    await tester.tap(find.text('Hide what I have'));

    expect(taps, 0);
  });

  testWidgets('with a value the whole row turns it', (tester) async {
    bool? seen;
    await pump(tester, false, onChanged: (v) => seen = v);

    await tester.tap(find.text('Hide what I have'));

    expect(seen, isTrue);
  });
}
