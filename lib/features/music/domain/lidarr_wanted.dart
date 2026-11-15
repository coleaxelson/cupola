import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/media_browse_wanted.dart';

/// What Lidarr's `wanted/missing` says, folded to the grain the library
/// browses at: one entry per artist, with how many of its albums are wanted.
///
/// Lidarr answers that route with *albums* (released, monitored, nothing on
/// disk), so the fold is over `artistId`. [ArrRecordPage.cutShort] makes the
/// whole set a floor: the walk gave up before the end of the list, so there
/// may be more artists than it saw and more albums for each.
///
/// Top-level and pure so the grain and the floor are assertable without a
/// service.
MediaBrowseWantedSet lidarrWantedFrom(ArrRecordPage page) {
  final counts = <int, int>{};
  for (final record in page.records.whereType<Map>()) {
    if (record['artistId'] case final int id) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return MediaBrowseWantedSet(countById: counts, isFloor: page.cutShort);
}

/// `1 album wanted` / `3 albums wanted` / `50+ albums wanted`: the caption of
/// an artist's tile under the Wanted chip. A floor is never singular.
String lidarrWantedCaption(int albums, bool isFloor) {
  final figure = isFloor ? '$albums+' : '$albums';
  final noun = albums == 1 && !isFloor ? 'album' : 'albums';
  return '$figure$unitSpace$noun wanted';
}

/// The line under the chips: `34 artists have a wanted album: released,
/// monitored, nothing on disk.` It says what *wanted* means because the word
/// is the service's and the reader's own sense of it differs (a missing track
/// is not a wanted album).
String lidarrWantedSummary(int artists, bool isFloor) {
  final figure = isFloor ? '$artists+' : '$artists';
  final one = artists == 1 && !isFloor;
  return '$figure$unitSpace${one ? 'artist has' : 'artists have'} a wanted '
      'album: released, monitored, nothing on disk.';
}
