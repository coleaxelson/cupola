/// The matching a library's own search field does: instant, local, and
/// forgiving of case and accents.
///
/// A word typed is the *start* of a word in the name, never a piece from the
/// middle of one: `el` finds `Elephants Dream` and `Ella Fitzgerald`, `fitz`
/// finds `Ella Fitzgerald`, and `phants` finds neither. Several words must each
/// start some word of the name, in any order (`fitz ella`).
library;

import 'dart:ui' show TextRange;

/// What the Latin letters with a mark, or a stroke, or a ligature, read as
/// when typed on a keyboard without them: `Björk` is `bjork`, `Mötley Crüe`
/// is `motley crue`, `Sigur Rós` is `sigur ros`.
const Map<String, String> _plain = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ß': 'ss',
  'ť': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ž': 'z',
  'ż': 'z',
};

/// [text] as it is compared: lower case, with the marks taken off.
String foldForFind(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}

final RegExp _notAWordCharacter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The words of [text] as they are compared, [foldForFind]ed.
List<String> findWords(String text) => [
  for (final word in foldForFind(text).split(_notAWordCharacter))
    if (word.isNotEmpty) word,
];

/// Whether every word of [query] starts a word of [text].
///
/// An empty query matches nothing: a field with nothing in it is not a search.
bool matchesFindQuery(String query, String text) {
  final wanted = findWords(query);
  if (wanted.isEmpty) return false;
  return matchesFindWords(wanted, findWords(text));
}

/// [matchesFindQuery] over words already split, for a list searched on every
/// keystroke: the query is folded once and each name once.
bool matchesFindWords(List<String> wanted, List<String> words) {
  for (final prefix in wanted) {
    if (!words.any((word) => word.startsWith(prefix))) return false;
  }
  return true;
}

/// The stretches of [text] that [query] matched, for a row that marks them:
/// each word typed marks the start of the first word of [text] it opens
/// (`the drag` in `The Dragon` marks `The Drag`), as many characters as were
/// typed, in the characters [text] was written in (a typed `ss` marks the `ß`
/// it matched whole). Sorted, never overlapping; empty for a query that
/// opens no word. Marks with only spaces or punctuation between them are one.
List<TextRange> findMarks(String query, String text) {
  final wanted = findWords(query);
  if (wanted.isEmpty) return const [];
  final words = [
    for (final match in _wordSpan.allMatches(text))
      (start: match.start, end: match.end, folded: foldForFind(match[0]!)),
  ];
  final used = <int>{};
  final marks = <TextRange>[];
  for (final prefix in wanted) {
    final at = words.indexWhere(
      (word) => !used.contains(word.start) && word.folded.startsWith(prefix),
    );
    // Two typed words that open the same single word mark it once.
    if (at < 0) continue;
    final word = words[at];
    used.add(word.start);
    var consumed = 0;
    var end = word.start;
    final runes = text.substring(word.start, word.end).runes.iterator;
    while (consumed < prefix.length && runes.moveNext()) {
      final char = String.fromCharCode(runes.current);
      consumed += foldForFind(char).length;
      end += char.length;
    }
    marks.add(TextRange(start: word.start, end: end));
  }
  marks.sort((a, b) => a.start.compareTo(b.start));
  // Words typed one after the other read as one line: only a space or a
  // mark of punctuation lies between them.
  final merged = <TextRange>[];
  for (final mark in marks) {
    if (merged.isNotEmpty &&
        !_wordSpan.hasMatch(text.substring(merged.last.end, mark.start))) {
      merged.last = TextRange(start: merged.last.start, end: mark.end);
    } else {
      merged.add(mark);
    }
  }
  return merged;
}

final RegExp _wordSpan = RegExp(r'[\p{L}\p{N}]+', unicode: true);
