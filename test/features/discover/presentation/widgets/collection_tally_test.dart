import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';

/// The legend says what the headline does not: alone, "on your server"
/// would only repeat it.
void main() {
  CollectionShelf shelf(List<int?> statuses) => CollectionShelf.of(
    CollectionDetail(
      id: 1,
      name: 'Blender Open Movies',
      parts: [
        for (final (i, status) in statuses.indexed)
          MediaPreview(
            id: i + 1,
            title: 'Part ${i + 1}',
            mediaType: 'movie',
            releaseDate: '${2000 + i}-04-10',
            mediaInfo: status == null ? null : {'status': status},
          ),
      ],
    ),
  );

  Future<void> pump(WidgetTester tester, Widget tally, double width) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: tally),
              ),
            ),
          ),
        ),
      );

  for (final width in [390.0, 1068.0]) {
    testWidgets('on the server and missing only: no legend, at $width', (
      tester,
    ) async {
      await pump(
        tester,
        CollectionTally.invitation(
          shelf: shelf([5, 5, null]),
          name: 'Blender Open Movies',
          onTap: () {},
        ),
        width,
      );
      expect(
        find.text('Blender Open Movies\u00A0· 2 of 3 on your server'),
        findsOneWidget,
      );
      expect(find.text('2 on your server'), findsNothing);
    });
  }

  testWidgets('all on the server: the headline alone', (tester) async {
    await pump(tester, CollectionTally(shelf: shelf([5, 5, 5])), 390);
    expect(find.text('All 3 on your server'), findsOneWidget);
    expect(find.text('3 on your server'), findsNothing);
  });

  testWidgets('two kinds or more: the legend stays whole', (tester) async {
    await pump(tester, CollectionTally(shelf: shelf([5, 5, 3, null])), 390);
    expect(find.text('2 of 4 on your server'), findsOneWidget);
    expect(find.text('2 on your server'), findsOneWidget);
    expect(find.text('1 on the way'), findsOneWidget);
  });

  testWidgets('the sentence says the count once', (tester) async {
    await pump(tester, CollectionTally(shelf: shelf([5, 5, null])), 390);
    expect(find.bySemanticsLabel('2 of 3 on your server'), findsOneWidget);
  });
}
