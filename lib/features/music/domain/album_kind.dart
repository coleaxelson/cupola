import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';

/// What kind of release an album is, the way an artist's page sorts them.
///
/// MusicBrainz gives a release a primary type (`Album`, `EP`, `Single`,
/// `Broadcast`, `Other`) and any number of secondary ones (`Live`,
/// `Compilation`, `Soundtrack`...). The page needs each album under exactly
/// one kind, so that the kinds' counts add up to the whole: a secondary type
/// that means something wins over the primary one (a live album is a
/// `Concert`, not an `Album`; the Never list keeps the bare word `Live` out of
/// the app), `Studio` means nothing (it is what an album is by default), and
/// with neither the primary type is the kind.
///
/// The declaration order is the order the pills read in: the usual ones
/// first, `Other` last.
enum AlbumKind {
  album('Albums', 'Album', 'album', 'albums'),
  ep('EPs', 'EP', 'EP', 'EPs'),
  single('Singles', 'Single', 'single', 'singles'),
  live('Concerts', 'Concert', 'concert', 'concerts'),
  compilation('Compilations', 'Compilation', 'compilation', 'compilations'),
  soundtrack('Soundtracks', 'Soundtrack', 'soundtrack', 'soundtracks'),
  remix('Remixes', 'Remix', 'remix', 'remixes'),
  djMix('DJ mixes', 'DJ mix', 'DJ mix', 'DJ mixes'),
  mixtape('Mixtapes', 'Mixtape', 'mixtape', 'mixtapes'),
  demo('Demos', 'Demo', 'demo', 'demos'),
  spokenWord('Spoken word', 'Spoken word', 'release', 'releases'),
  audiobook('Audiobooks', 'Audiobook', 'audiobook', 'audiobooks'),
  interview('Interviews', 'Interview', 'interview', 'interviews'),
  audioDrama('Audio dramas', 'Audio drama', 'audio drama', 'audio dramas'),
  broadcast('Broadcasts', 'Broadcast', 'broadcast', 'broadcasts'),
  other('Other', 'Other', 'release', 'releases');

  const AlbumKind(this.label, this.fact, this._one, this._many);

  /// The pill's word: `Singles`.
  final String label;

  /// The kind as a row's facts say it: `Single`, `EP`.
  final String fact;

  final String _one;
  final String _many;

  /// The kind as a sentence says it of one release: `album`, `EP`, `single`;
  /// `release` for a kind with no noun of its own.
  String get noun => _one;

  /// `1 single`, `4 singles`; a kind with no noun of its own (spoken word,
  /// other) counts `releases`.
  String count(int n) => '$n$unitSpace${n == 1 ? _one : _many}';

  /// `1 unmonitored single`, `3 unmonitored albums`.
  String countUnmonitored(int n) =>
      '$n${unitSpace}unmonitored ${n == 1 ? _one : _many}';

  /// The kind of [album].
  static AlbumKind of(LidarrAlbum album) {
    for (final type in album.secondaryTypes) {
      final kind = _secondary[_key(type)];
      if (kind != null) return kind;
    }
    return _primary[_key(album.albumType ?? '')] ?? AlbumKind.other;
  }

  static String _key(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// `Studio` is absent on purpose: it names what an album is, not a kind.
  static const _secondary = {
    'live': AlbumKind.live,
    'compilation': AlbumKind.compilation,
    'soundtrack': AlbumKind.soundtrack,
    'remix': AlbumKind.remix,
    'djmix': AlbumKind.djMix,
    'mixtapestreet': AlbumKind.mixtape,
    'mixtape': AlbumKind.mixtape,
    'demo': AlbumKind.demo,
    'spokenword': AlbumKind.spokenWord,
    'audiobook': AlbumKind.audiobook,
    'interview': AlbumKind.interview,
    'audiodrama': AlbumKind.audioDrama,
  };

  static const _primary = {
    'album': AlbumKind.album,
    'ep': AlbumKind.ep,
    'single': AlbumKind.single,
    'broadcast': AlbumKind.broadcast,
    'other': AlbumKind.other,
  };
}

/// A kind and how many of an artist's albums are of it.
typedef AlbumKindCount = ({AlbumKind kind, int count});

/// The kinds [albums] fall under with how many each, in the pills' order; a
/// kind with no album is absent. The counts add up to `albums.length`.
List<AlbumKindCount> albumKindsOf(List<LidarrAlbum> albums) {
  final counts = <AlbumKind, int>{};
  for (final album in albums) {
    counts.update(AlbumKind.of(album), (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final kind in AlbumKind.values)
      if (counts[kind] case final count?) (kind: kind, count: count),
  ];
}
