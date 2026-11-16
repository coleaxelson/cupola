/// The two letters a search row wears without a picture.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/widgets/search_row.dart';

void main() {
  group('SearchRow.initialsOf', () {
    test('skips brackets and symbols: a punctuation mark is no initial', () {
      expect(SearchRow.initialsOf('Sintel (Anniversary Edition)'), 'SA');
      expect(SearchRow.initialsOf('Sintel - Anniversary'), 'SA');
      expect(SearchRow.initialsOf('(Untitled) Live'), 'UL');
    });

    test('keeps numbers, one word, and nothing', () {
      expect(SearchRow.initialsOf('Agent 327'), 'A3');
      expect(SearchRow.initialsOf('Caminandes 3'), 'C3');
      expect(SearchRow.initialsOf('Nosferatu'), 'N');
      expect(SearchRow.initialsOf('Night Shift Radio'), 'NS');
      expect(SearchRow.initialsOf('  '), '');
      expect(SearchRow.initialsOf(''), '');
      expect(SearchRow.initialsOf('( )'), '');
    });
  });
}
