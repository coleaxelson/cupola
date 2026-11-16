import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';

/// What the library holds, by MusicBrainz id: how a row of Lidarr's search is
/// told held from not, as Lidarr's own front end does it. A search row carries
/// no library id of its own (see [LidarrSearchHit]).
class MusicHeld {
  MusicHeld({
    required List<LidarrArtist> artists,
    required List<LidarrAlbum> albums,
  }) : _artists = {
         for (final artist in artists)
           if (artist.foreignArtistId.isNotEmpty)
             artist.foreignArtistId: artist,
       },
       _artistsById = {for (final artist in artists) artist.id: artist},
       _albums = {
         for (final album in albums)
           if (album.foreignAlbumId.isNotEmpty) album.foreignAlbumId: album,
       };

  final Map<String, LidarrArtist> _artists;
  final Map<int, LidarrArtist> _artistsById;
  final Map<String, LidarrAlbum> _albums;

  /// The library's record of [found], an artist the catalog named, or null
  /// when the library does not hold them.
  LidarrArtist? artistOf(LidarrArtist found) => _artists[found.foreignArtistId];

  /// The library's record of the album [hit] found, or null.
  LidarrAlbum? albumOf(LidarrAlbumHit hit) => _albums[hit.album.foreignAlbumId];

  /// The artist the library keeps [album] under, or null.
  LidarrArtist? artistOfAlbum(LidarrAlbum album) =>
      _artistsById[album.artistId];
}
