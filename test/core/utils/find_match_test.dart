import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/find_match.dart';

void main() {
  group('foldForFind', () {
    test('lower cases and takes the marks off', () {
      expect(foldForFind('Björk'), 'bjork');
      expect(foldForFind('Mötley Crüe'), 'motley crue');
      expect(foldForFind('Sigur Rós'), 'sigur ros');
      expect(foldForFind('Dvořák'), 'dvorak');
      expect(foldForFind('Beyoncé'), 'beyonce');
    });

    test('reads a stroke and a ligature as the letters they stand for', () {
      expect(foldForFind('Mø'), 'mo');
      expect(foldForFind('Æon'), 'aeon');
      expect(foldForFind('Straße'), 'strasse');
    });

    test('leaves what is not a Latin letter with a mark as it is', () {
      expect(foldForFind('坂本龍一 2'), '坂本龍一 2');
    });
  });

  group('matchesFindQuery', () {
    test('a word typed starts a word of the name', () {
      expect(matchesFindQuery('el', 'Ella Fitzgerald'), isTrue);
      expect(matchesFindQuery('el', 'Elephants Dream'), isTrue);
      expect(matchesFindQuery('fitz', 'Ella Fitzgerald'), isTrue);
      expect(matchesFindQuery('el', 'Edward Elgar'), isTrue);
    });

    test('never a piece from the middle of a word', () {
      expect(matchesFindQuery('phants', 'Elephants Dream'), isFalse);
      expect(matchesFindQuery('zgerald', 'Ella Fitzgerald'), isFalse);
    });

    test('is blind to case and accents, both ways', () {
      expect(matchesFindQuery('bjo', 'Björk'), isTrue);
      expect(matchesFindQuery('BJÖ', 'bjork'), isTrue);
      expect(matchesFindQuery('sigur ros', 'Sigur Rós'), isTrue);
      expect(matchesFindQuery('motley', 'Mötley Crüe'), isTrue);
    });

    test('several words must each start a word, in any order', () {
      expect(matchesFindQuery('ella fitz', 'Ella Fitzgerald'), isTrue);
      expect(matchesFindQuery('fitz ella', 'Ella Fitzgerald'), isTrue);
      expect(matchesFindQuery('ella louis', 'Ella Fitzgerald'), isFalse);
    });

    test('punctuation parts words and is not typed', () {
      expect(matchesFindQuery('ac', 'AC/DC'), isTrue);
      expect(matchesFindQuery('dc', 'AC/DC'), isTrue);
      expect(
        matchesFindQuery('sintel', 'Sintel (Anniversary Edition)'),
        isTrue,
      );
      expect(matchesFindQuery('anniv', 'Sintel (Anniversary Edition)'), isTrue);
      expect(matchesFindQuery('(ann', 'Sintel (Anniversary Edition)'), isTrue);
    });

    test('digits are words too', () {
      expect(matchesFindQuery('19', '1989 (Taylor’s Version)'), isTrue);
      expect(matchesFindQuery('tay', '1989 (Taylor’s Version)'), isTrue);
    });

    test('a query with no word in it matches nothing', () {
      expect(matchesFindQuery('', 'Ella Fitzgerald'), isFalse);
      expect(matchesFindQuery('  ', 'Ella Fitzgerald'), isFalse);
      expect(matchesFindQuery('/', 'Ella Fitzgerald'), isFalse);
    });
  });

  group('findMarks', () {
    String marked(String query, String text) => [
      for (final range in findMarks(query, text))
        text.substring(range.start, range.end),
    ].join('|');

    test('marks the start of the word each typed word opened', () {
      expect(marked('the drag', 'The Dragon'), 'The Drag');
      expect(marked('fitz', 'Ella Fitzgerald'), 'Fitz');
      expect(marked('fitz ella', 'Ella Fitzgerald'), 'Ella Fitz');
      expect(marked('ella gerald', 'Ella Fitzgerald'), 'Ella');
    });

    test('marks words apart when another word lies between them', () {
      expect(marked('the drag', 'The Long Dragon'), 'The|Drag');
    });

    test('marks as many characters as were typed', () {
      expect(marked('dragon', 'Dragonfly'), 'Dragon');
    });

    test('marks the letters the text was written in, accents and all', () {
      expect(marked('cafe', 'Café au lait'), 'Café');
      expect(marked('bjo', 'Björk'), 'Bjö');
      expect(marked('strasse', 'Straße'), 'Straße');
    });

    test('marks nothing for a query that opens no word', () {
      expect(findMarks('phants', 'Elephants Dream'), isEmpty);
      expect(findMarks('', 'Elephants Dream'), isEmpty);
    });

    test('marks a word once when two typed words open the same one', () {
      expect(marked('dr dra', 'Dragon'), 'Dr');
    });
  });
}
