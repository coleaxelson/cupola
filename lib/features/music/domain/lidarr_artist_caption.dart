import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// `6 albums · complete` / `9 albums · 34 tracks missing`: the caption the
/// circular artist tile carries instead of a status dot.
///
/// Top-level and pure so the wording is assertable without a pumped wall.
///
/// Three honest answers, and the third is why this is not a one-liner:
/// * Lidarr omits `statistics` entirely on an artist it has not scanned. That
///   is not "0 albums", it is *no answer*, and it reads as an em dash.
/// * With tracks counted, the shortfall is stated **in tracks**, because tracks
///   are what Lidarr counts. The board writes `9 albums · 1 missing`, but the
///   artist payload carries no per-album file state, so saying "1 missing"
///   beside an album count would be a number in the wrong unit.
/// * An artist with albums but no tracks counted gets the album count alone
///   rather than a completeness claim nothing supports.
String lidarrArtistCaption(LidarrArtist artist) {
  if (artist.statistics == null) return '\u2014';

  final albums = artist.albumCount;
  final albumTerm = albums > 0
      ? '$albums${unitSpace}album${albums == 1 ? '' : 's'}'
      : null;

  final tracks = artist.trackCount;
  if (tracks <= 0) return albumTerm ?? '\u2014';

  final missing = tracks - artist.trackFileCount;
  final completeness = missing <= 0
      ? 'complete'
      : '$missing${unitSpace}track${missing == 1 ? '' : 's'} missing';

  return albumTerm == null ? completeness : '$albumTerm\u00A0· $completeness';
}
