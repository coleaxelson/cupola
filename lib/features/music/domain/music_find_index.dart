import 'package:cupola/core/utils/find_match.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// What the library holds that a typed word names.
typedef MusicFound = ({List<LidarrArtist> artists, List<LidarrAlbum> albums});

/// The artists' names and the albums' titles of a library, split into the
/// words they are matched on once, so the search can run on every keystroke
/// over a library of thousands.
///
/// Matching is by word prefix, blind to case and accents ([matchesFindWords]):
/// `bjo` finds `Björk`, `el` finds `Ella Fitzgerald` and `Elephants Dream`.
/// Names the query opens come before names it only meets later (`el` lists
/// `Ella Fitzgerald` before `Edward Elgar`), and each group is alphabetical.
class MusicFindIndex {
  MusicFindIndex({
    required List<LidarrArtist> artists,
    required List<LidarrAlbum> albums,
  }) : _artists = [
         for (final artist in artists)
           _Entry(artist, artist.artistName, findWords(artist.artistName)),
       ],
       _albums = [
         for (final album in albums)
           _Entry(album, album.title, findWords(album.title)),
       ];

  final List<_Entry<LidarrArtist>> _artists;
  final List<_Entry<LidarrAlbum>> _albums;

  /// The artists and albums [query] names; nothing for a query with no word
  /// in it.
  MusicFound find(String query) {
    final wanted = findWords(query);
    if (wanted.isEmpty) return (artists: const [], albums: const []);
    final opening = foldForFind(query.trim());
    return (
      artists: _match(_artists, wanted, opening),
      albums: _match(_albums, wanted, opening),
    );
  }

  static List<T> _match<T>(
    List<_Entry<T>> entries,
    List<String> wanted,
    String opening,
  ) {
    final hits = [
      for (final entry in entries)
        if (matchesFindWords(wanted, entry.words)) entry,
    ];
    int rank(_Entry<T> entry) => entry.folded.startsWith(opening) ? 0 : 1;
    hits.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.folded.compareTo(b.folded);
    });
    return [for (final entry in hits) entry.item];
  }
}

class _Entry<T> {
  _Entry(this.item, String name, this.words) : folded = foldForFind(name);

  final T item;
  final String folded;
  final List<String> words;
}
