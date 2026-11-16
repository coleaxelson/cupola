import 'dart:ui' show TextRange;

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/find_match.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';

/// A track the finder found: the track, the album it is on, and the stretches
/// of its title the words typed matched. The marks are worked out when a row
/// asks for them, so a query that matches thousands of tracks pays only for
/// the rows on screen.
class ArtistTrackHit {
  ArtistTrackHit(this.track, this.album, this._query);

  final LidarrTrack track;
  final LidarrAlbum album;
  final String _query;

  late final List<TextRange> marks = findMarks(_query, track.title);
}

/// The tracks of one artist's albums, split into the words they are matched
/// on once, so the finder can run on every keystroke over a discography of
/// thousands.
///
/// A track is found by the start of a word of its title, blind to case and
/// accents ([matchesFindWords]). Titles the query opens come before titles it
/// only meets later; then alphabetical; the same title on several albums is
/// listed newest album first, in track order. A track whose album the artist's
/// list does not hold is left out: there is no album to open it on.
class ArtistTrackIndex {
  ArtistTrackIndex({
    required List<LidarrTrack> tracks,
    required List<LidarrAlbum> albums,
  }) {
    final byId = {for (final album in albums) album.id: album};
    for (final track in tracks) {
      final album = byId[track.albumId];
      if (album == null) continue;
      _entries.add(
        _Entry(
          track,
          album,
          foldForFind(track.title),
          findWords(track.title),
          DateTime.tryParse(album.releaseDate ?? '') ?? DateTime(0),
        ),
      );
    }
  }

  final _entries = <_Entry>[];

  /// How many tracks can be found.
  int get length => _entries.length;

  /// The tracks [query] names, in the order they are listed; nothing for a
  /// query with no word in it.
  List<ArtistTrackHit> find(String query) {
    final wanted = findWords(query);
    if (wanted.isEmpty) return const [];
    final opening = foldForFind(query.trim());
    final hits = [
      for (final entry in _entries)
        if (matchesFindWords(wanted, entry.words)) entry,
    ];
    int rank(_Entry e) => e.folded.startsWith(opening) ? 0 : 1;
    hits.sort((a, b) {
      var order = rank(a).compareTo(rank(b));
      if (order == 0) order = a.folded.compareTo(b.folded);
      // Newest album first, as the page lists albums.
      if (order == 0) order = b.released.compareTo(a.released);
      if (order == 0) order = a.album.id.compareTo(b.album.id);
      if (order == 0) {
        order = (a.track.mediumNumber ?? 0).compareTo(
          b.track.mediumNumber ?? 0,
        );
      }
      if (order == 0) {
        order = a.track.sortableTrackNumber.compareTo(
          b.track.sortableTrackNumber,
        );
      }
      return order != 0 ? order : a.track.id.compareTo(b.track.id);
    });
    return [
      for (final entry in hits) ArtistTrackHit(entry.track, entry.album, query),
    ];
  }
}

class _Entry {
  _Entry(this.track, this.album, this.folded, this.words, this.released);

  final LidarrTrack track;
  final LidarrAlbum album;
  final String folded;
  final List<String> words;
  final DateTime released;
}

/// `2 tracks`: the finder's heading.
String trackCountWords(int count) =>
    '$count$unitSpace${count == 1 ? 'track' : 'tracks'}';

/// Where a found track stands: `On disk` when it has a file, otherwise its
/// album's own state, so that a track never says anything its album's row
/// contradicts. Null while the album's word waits for the queue.
AlbumState? trackState(
  LidarrTrack track,
  LidarrAlbum album, {
  required ArrQueueSnapshot queue,
  required DateTime now,
}) {
  if (track.hasFile) {
    return (word: 'On disk', tone: StatusTone.success, hollow: false);
  }
  return albumState(album, queue: queue, now: now);
}

/// What a found track's row says under its title: `Sintel · track 3 · 5:36`;
/// the length only when Lidarr knows it.
String trackMeta(LidarrTrack track, LidarrAlbum album) => [
  album.title,
  'track ${track.displayTrackNumber}',
  if (track.duration > 0) track.formattedDuration,
].join(dotSeparator);

/// The same row as one sentence: `The Dragon, track 3 on Sintel, 5:36, on
/// disk`.
String trackSpoken(
  LidarrTrack track,
  LidarrAlbum album, {
  required AlbumState? state,
}) {
  final word = state?.word;
  return [
    track.title,
    'track ${track.displayTrackNumber} on ${album.title}',
    if (track.duration > 0) track.formattedDuration,
    if (word != null) '${word[0].toLowerCase()}${word.substring(1)}',
  ].join(', ');
}
