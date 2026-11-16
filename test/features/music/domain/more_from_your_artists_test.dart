import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/more_from_your_artists.dart';

final _now = DateTime(2026, 11, 15, 12);

LidarrArtist _artist(int id, String name) => LidarrArtist(
  id: id,
  artistName: name,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
);

LidarrAlbum _album(
  int id,
  String title, {
  int artistId = 1,
  String? released = '2008-05-01T00:00:00Z',
  bool monitored = false,
  int files = 0,
}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  releaseDate: released,
  monitored: monitored,
  images: const [],
  statistics: {'trackFileCount': files, 'totalTrackCount': 5},
);

MoreFromYourArtists _of(
  List<LidarrAlbum> albums, [
  List<LidarrArtist>? artists,
]) => MoreFromYourArtists.of(
  albums: albums,
  artists: artists ?? [_artist(1, 'Jan Morgenstern')],
  now: _now,
);

List<String> _titles(MoreFromYourArtists shelf) => [
  for (final entry in shelf.albums) entry.album.title,
];

void main() {
  group('what stays', () {
    test('an album out, not monitored and with no file', () {
      expect(_titles(_of([_album(1, 'Big Buck Bunny Suite')])), [
        'Big Buck Bunny Suite',
      ]);
    });

    test('not one Lidarr is looking for', () {
      expect(_of([_album(1, 'Wanted', monitored: true)]).isEmpty, isTrue);
    });

    test('not one with a track on disk, monitored or not', () {
      expect(_of([_album(1, 'Some', files: 1)]).isEmpty, isTrue);
      expect(
        _of([_album(2, 'Held', files: 5, monitored: true)]).isEmpty,
        isTrue,
      );
    });

    test('not one that is not out yet', () {
      expect(
        _of([_album(1, 'Next year', released: '2027-01-01')]).isEmpty,
        isTrue,
      );
    });

    test('one with no date is out, and comes last', () {
      final shelf = _of([
        _album(1, 'Undated', released: null),
        _album(2, 'Dated'),
      ]);
      expect(_titles(shelf), ['Dated', 'Undated']);
    });

    test('only albums of artists the library holds', () {
      final shelf = _of(
        [_album(1, 'Theirs'), _album(2, 'Nobody’s', artistId: 9)],
        [_artist(1, 'Jan Morgenstern')],
      );
      expect(_titles(shelf), ['Theirs']);
    });

    test('a library with nothing left is empty', () {
      expect(_of(const []).isEmpty, isTrue);
      expect(const MoreFromYourArtists.none().isEmpty, isTrue);
    });
  });

  group('the order', () {
    test('newest first', () {
      final shelf = _of([
        _album(1, 'Old', released: '1999-01-01'),
        _album(2, 'New', released: '2025-06-01'),
        _album(3, 'Middle', released: '2008-05-01'),
      ]);
      expect(_titles(shelf), ['New', 'Middle', 'Old']);
    });

    test('albums out the same day go by title, blind to case and accents, '
        'then by id', () {
      final shelf = _of([
        _album(3, 'zeta'),
        _album(2, 'Éclat'),
        _album(1, 'Alpha'),
        _album(5, 'Same'),
        _album(4, 'Same'),
      ]);
      expect(_titles(shelf), ['Alpha', 'Éclat', 'Same', 'Same', 'zeta']);
      expect(
        [for (final entry in shelf.albums) entry.album.id],
        [1, 2, 4, 5, 3],
      );
    });
  });

  group('the shelf and the whole', () {
    test('the shelf is the newest twenty; the whole keeps them all', () {
      final shelf = _of([
        for (var i = 0; i < 25; i++)
          _album(
            i + 1,
            'Album $i',
            released: '2000-01-${(i % 28 + 1).toString().padLeft(2, '0')}',
          ),
      ]);
      expect(shelf.albums, hasLength(25));
      expect(shelf.shelf, hasLength(MoreFromYourArtists.shelfLength));
      expect(shelf.shelf.first.album.id, shelf.albums.first.album.id);
      expect(
        shelf.shelf.last.album.id,
        shelf.albums[MoreFromYourArtists.shelfLength - 1].album.id,
      );
    });

    test('under their artists, the artists A to Z and each one’s albums '
        'newest first', () {
      final shelf = _of(
        [
          _album(1, 'B old', artistId: 2, released: '2001-01-01'),
          _album(2, 'A', artistId: 1, released: '2010-01-01'),
          _album(3, 'B new', artistId: 2, released: '2020-01-01'),
          _album(4, 'C', artistId: 3, released: '2015-01-01'),
        ],
        [_artist(1, 'Élan'), _artist(2, 'Birch'), _artist(3, 'cobalt')],
      );
      final groups = shelf.byArtist;
      expect(
        [for (final group in groups) group.artist.artistName],
        ['Birch', 'cobalt', 'Élan'],
      );
      expect(
        [for (final album in groups.first.albums) album.title],
        ['B new', 'B old'],
      );
    });
  });
}
