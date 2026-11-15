/// The album and the artist shapes of [SearchRow]: where they stand, the
/// ring for the backlog, the plus while its write is out, and what they say.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';

Future<void> _pump(WidgetTester tester, Widget row, {double scale = 1}) async {
  tester.view
    ..physicalSize = const Size(390, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: row),
      ),
    ),
  );
}

/// The 7pt dot of a row's state word: a filled disc, or a ring.
BoxDecoration _dot(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .firstWhere(
      (d) =>
          d.shape == BoxShape.circle && (d.border != null || d.color != null),
      orElse: () => throw StateError('no dot'),
    );

void main() {
  testWidgets('an album with no cover shows its initials on a square', (
    tester,
  ) async {
    await _pump(
      tester,
      SearchRow.album(
        title: 'Elephants Dream',
        meta: 'Jan Morgenstern',
        onTap: () {},
      ),
    );

    expect(find.text('ED'), findsOneWidget);
    expect(tester.getSize(find.text('ED').first).width, lessThan(44));
  });

  testWidgets('a state is a filled dot, or the ring of the backlog', (
    tester,
  ) async {
    await _pump(
      tester,
      SearchRow.album(
        title: 'Elephants Dream',
        meta: 'Jan Morgenstern',
        status: (label: 'Complete', tone: StatusTone.success),
        onTap: () {},
      ),
    );
    expect(find.text('Complete'), findsOneWidget);
    expect(_dot(tester).color, isNotNull);

    await _pump(
      tester,
      SearchRow.album(
        title: 'Ella and Louis',
        meta: 'Ella Fitzgerald',
        status: (label: 'Wanted', tone: StatusTone.neutral),
        statusHollow: true,
        onTap: () {},
      ),
    );
    final ring = _dot(tester);
    expect(ring.color, isNull);
    expect(ring.border, isNotNull);
  });

  testWidgets('a plus whose write is out is a spinner and takes no tap', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      SearchRow.album(
        title: 'Electric Ladyland',
        meta: 'The Jimi Hendrix Experience',
        onTap: () {},
        action: SearchRowAdd(
          label: 'Monitor Electric Ladyland and search for it',
          busy: true,
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    await tester.tap(find.byType(CircularProgressIndicator));
    expect(taps, 0);
  });

  testWidgets('the plus at rest is tapped', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      SearchRow.artist(
        name: 'Elbow',
        line: 'Group',
        onTap: () {},
        action: SearchRowAdd(label: 'Add Elbow to Lidarr', onTap: () => taps++),
      ),
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(taps, 1);
  });

  testWidgets('a music row speaks one sentence: the dots are commas', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      SearchRow.album(
        title: 'Elephants Dream',
        meta: 'Jan Morgenstern\u00A0· 2006\u00A0· 7\u00A0tracks',
        status: (
          label: 'Out Fri 2 Oct\u00A0· not out yet',
          tone: StatusTone.neutral,
        ),
        statusHollow: true,
        hint: 'Opens Jan Morgenstern',
        onTap: () {},
      ),
    );

    final node = tester.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Elephants Dream',
      ),
    );
    expect(
      node.value.replaceAll('\u00A0', ' '),
      'Jan Morgenstern, 2006, 7 tracks, Out Fri 2 Oct, not out yet',
    );
    expect(node.hint, 'Opens Jan Morgenstern');
    handle.dispose();
  });

  testWidgets('the title and the meta take two lines at a large size', (
    tester,
  ) async {
    await _pump(
      tester,
      SearchRow.album(
        title: 'Leaders of the Free World',
        meta: 'The Jimi Hendrix Experience\u00A0· 1968\u00A0· Album',
        onTap: () {},
      ),
      scale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Leaders of the Free World'), findsOneWidget);
  });
}
