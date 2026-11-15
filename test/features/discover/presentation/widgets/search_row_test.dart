import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';

/// A title takes a second line only when it is long, and a row with no state
/// does not grow for it.
void main() {
  Future<Size> pumpRow(WidgetTester tester, SearchRow row) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 390 - 32, child: row),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(SearchRow));
  }

  SearchRow titled(String title) => SearchRow.title(
    title: title,
    meta: 'Movie · 2001',
    onTap: () {},
    action: SearchRowRequest(
      label: 'Request $title',
      verdict: const Live(),
      onTap: () {},
    ),
  );

  int lines(WidgetTester tester, String text) {
    final box = tester.renderObject<RenderParagraph>(find.text(text));
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    return {for (final b in boxes) b.top.round()}.length;
  }

  testWidgets('a long title takes two lines beside Request, and the row '
      'stays as tall as one with a short title', (tester) async {
    const long = 'The Lord of the Rings: The Fellowship of the Ring';
    final short = await pumpRow(tester, titled('Sintel'));
    expect(lines(tester, 'Sintel'), 1);

    final tall = await pumpRow(tester, titled(long));
    expect(lines(tester, long), 2);
    expect(tall.height, short.height);
  });

  testWidgets('a person\'s name keeps one line', (tester) async {
    const name = 'Alexandre Desplat and the Orchestre de Paris Ensemble Name';
    await pumpRow(
      tester,
      SearchRow.person(name: name, line: 'Composer', onTap: () {}),
    );
    expect(lines(tester, name), 1);
  });
}
