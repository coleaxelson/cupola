import 'package:cupola/core/utils/find_index.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// What the library holds that a typed word names.
typedef MusicFound = ({List<LidarrArtist> artists, List<LidarrAlbum> albums});

/// The artists' names and the albums' titles of a library, indexed once so
/// the search can run on every keystroke over a library of thousands (see
/// [FindIndex] for the matching and the order).
class MusicFindIndex {
  MusicFindIndex({
    required List<LidarrArtist> artists,
    required List<LidarrAlbum> albums,
  }) : _artists = FindIndex(artists, (artist) => [artist.artistName]),
       _albums = FindIndex(albums, (album) => [album.title]);

  final FindIndex<LidarrArtist> _artists;
  final FindIndex<LidarrAlbum> _albums;

  /// The artists and albums [query] names; nothing for a query with no word
  /// in it.
  MusicFound find(String query) =>
      (artists: _artists.find(query), albums: _albums.find(query));
}
