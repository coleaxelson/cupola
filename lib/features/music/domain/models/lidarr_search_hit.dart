import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// One row of `GET /api/v1/search`: an artist, or an album with its artist.
///
/// Lidarr's `SearchResource` is `{id, foreignId, artist, album}` with one of
/// the two filled. Neither carries a library id of its own: a row is *in the
/// library* when Lidarr's own front end would say so: by MusicBrainz id
/// (`foreignArtistId`, `foreignAlbumId`) against what the library holds.
sealed class LidarrSearchHit {
  const LidarrSearchHit();

  /// Null for a row that is neither (a shape this client does not know).
  static LidarrSearchHit? tryParse(Map<String, dynamic> json) {
    final album = json['album'];
    final artist = json['artist'];
    if (album is Map && album['title'] != null) {
      final raw = album.cast<String, dynamic>();
      final nested = raw['artist'] ?? artist;
      if (nested is! Map) return null;
      return LidarrAlbumHit(
        album: LidarrAlbum.fromJson(raw),
        artist: LidarrArtist.fromJson(nested.cast<String, dynamic>()),
        raw: raw,
      );
    }
    if (artist is Map) {
      return LidarrArtistHit(
        LidarrArtist.fromJson(artist.cast<String, dynamic>()),
      );
    }
    return null;
  }
}

/// An artist the catalog found. [artist] is the lookup row: its `id` is the
/// library's when Lidarr holds the artist, and 0 otherwise.
final class LidarrArtistHit extends LidarrSearchHit {
  const LidarrArtistHit(this.artist);

  final LidarrArtist artist;
}

/// An album the catalog found, with the artist it is by.
final class LidarrAlbumHit extends LidarrSearchHit {
  const LidarrAlbumHit({
    required this.album,
    required this.artist,
    required this.raw,
  });

  /// The album as the catalog describes it (remote artwork, no statistics).
  final LidarrAlbum album;

  /// The album's artist: the library's record when Lidarr holds them (a
  /// positive `id`), the catalog's otherwise.
  final LidarrArtist artist;

  /// The album resource as it came, which is what an add posts back.
  final Map<String, dynamic> raw;
}
