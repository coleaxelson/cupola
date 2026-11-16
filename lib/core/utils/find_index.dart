import 'package:cupola/core/utils/find_match.dart';

/// The names of a list of things, split into the words they are matched on
/// once, so a search can run on every keystroke over a library of thousands.
///
/// A thing is found by word prefix, blind to case and accents
/// ([matchesFindWords]), on any of the names it carries (a title and its sort
/// title). Names the query opens come before names it only meets later (`el`
/// lists `Ella Fitzgerald` before `Edward Elgar`), and each group is
/// alphabetical.
class FindIndex<T> {
  FindIndex(List<T> items, List<String> Function(T item) namesOf)
    : _entries = [
        for (final item in items)
          _Entry(
            item,
            [for (final name in namesOf(item)) foldForFind(name)],
            [for (final name in namesOf(item)) ...findWords(name)],
          ),
      ];

  final List<_Entry<T>> _entries;

  /// The things [query] names, in the order they are listed; nothing for a
  /// query with no word in it.
  List<T> find(String query) {
    final wanted = findWords(query);
    if (wanted.isEmpty) return const [];
    final opening = foldForFind(query.trim());
    final hits = [
      for (final entry in _entries)
        if (matchesFindWords(wanted, entry.words)) entry,
    ];
    int rank(_Entry<T> entry) =>
        entry.names.any((name) => name.startsWith(opening)) ? 0 : 1;
    hits.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.names.first.compareTo(b.names.first);
    });
    return [for (final entry in hits) entry.item];
  }
}

class _Entry<T> {
  _Entry(this.item, this.names, this.words);

  final T item;

  /// Each name, folded: the first is the one the list is ordered by.
  final List<String> names;
  final List<String> words;
}
