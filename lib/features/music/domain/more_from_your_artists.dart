import 'package:cupola/core/utils/find_match.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// An album with the library artist it is by.
typedef ArtistAlbum = ({LidarrAlbum album, LidarrArtist artist});

/// One artist and the albums of theirs the shelf holds, newest first.
typedef ArtistAlbums = ({LidarrArtist artist, List<LidarrAlbum> albums});

/// What the library's artists made that nothing is looking for: the albums
/// Lidarr knows of, out already, with no file on disk and told not to look.
///
/// Discover's shelf `More from your artists` is the head of it and its See all
/// page the whole. Lidarr's own `/album` lists only what its library holds, so
/// every album is an artist's the library has; an album whose artist is not in
/// the list read beside it (a library read again between the two) is left out,
/// since a tile with no one to open names no one.
///
/// Newest first: what an artist put out last is what a person has most likely
/// not heard of yet. Albums out on the same day go by title, then by id, so the
/// shelf does not change its mind between two reads.
class MoreFromYourArtists {
  const MoreFromYourArtists._(this.albums);

  /// Nothing to show: no music source, or a library with every album
  /// monitored or on disk.
  const MoreFromYourArtists.none() : albums = const [];

  factory MoreFromYourArtists.of({
    required List<LidarrAlbum> albums,
    required List<LidarrArtist> artists,
    required DateTime now,
  }) {
    final byId = {for (final artist in artists) artist.id: artist};
    final left = <ArtistAlbum>[
      for (final album in albums)
        if (!albumIsComing(album, now: now) &&
            album.trackFileCount <= 0 &&
            !album.monitored)
          if (byId[album.artistId] case final artist?)
            (album: album, artist: artist),
    ];
    final titles = {
      for (final entry in left) entry.album.id: foldForFind(entry.album.title),
    };
    left.sort((a, b) {
      final newer = albumReleasedOn(
        b.album,
      ).compareTo(albumReleasedOn(a.album));
      if (newer != 0) return newer;
      final byTitle = titles[a.album.id]!.compareTo(titles[b.album.id]!);
      return byTitle != 0 ? byTitle : a.album.id.compareTo(b.album.id);
    });
    return MoreFromYourArtists._(List.unmodifiable(left));
  }

  /// How many tiles the shelf holds; See all holds the rest.
  static const shelfLength = 20;

  /// Every album, newest first.
  final List<ArtistAlbum> albums;

  bool get isEmpty => albums.isEmpty;

  /// The newest [shelfLength] albums: the shelf's tiles.
  List<ArtistAlbum> get shelf => albums.take(shelfLength).toList();

  /// The albums under their artists, the artists A to Z (blind to case and
  /// accents, as the walls' index is) and each artist's albums newest first:
  /// See all's page, which is read by who made a record.
  List<ArtistAlbums> get byArtist {
    final groups = <int, ArtistAlbums>{};
    for (final entry in albums) {
      groups
          .putIfAbsent(
            entry.artist.id,
            () => (artist: entry.artist, albums: <LidarrAlbum>[]),
          )
          .albums
          .add(entry.album);
    }
    final names = {
      for (final group in groups.values)
        group.artist.id: foldForFind(group.artist.artistName),
    };
    return groups.values.toList()..sort((a, b) {
      final byName = names[a.artist.id]!.compareTo(names[b.artist.id]!);
      return byName != 0 ? byName : a.artist.id.compareTo(b.artist.id);
    });
  }
}
