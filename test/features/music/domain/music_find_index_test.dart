import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/music_find_index.dart';

LidarrArtist _artist(int id, String name) => LidarrArtist(
  id: id,
  artistName: name,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
);

LidarrAlbum _album(int id, String title, {int artistId = 1}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  monitored: true,
  images: const [],
);

void main() {
  final index = MusicFindIndex(
    artists: [
      _artist(1, 'Edward Elgar'),
      _artist(2, 'Ella Fitzgerald'),
      _artist(3, 'Björk'),
      _artist(4, 'Jan Morgenstern'),
    ],
    albums: [
      _album(10, 'Elegy for Strings', artistId: 1),
      _album(11, 'Ella and Louis', artistId: 2),
      _album(12, 'Elephants Dream', artistId: 4),
      _album(13, 'Debut', artistId: 3),
      _album(14, 'Live at the Elgar Hall', artistId: 1),
    ],
  );

  List<String> names(MusicFound found) => [
    for (final artist in found.artists) artist.artistName,
  ];
  List<String> titles(MusicFound found) => [
    for (final album in found.albums) album.title,
  ];

  test('finds artists by name and albums by title', () {
    final found = index.find('el');

    expect(names(found), ['Ella Fitzgerald', 'Edward Elgar']);
    expect(titles(found), [
      'Elegy for Strings',
      'Elephants Dream',
      'Ella and Louis',
      'Live at the Elgar Hall',
    ]);
  });

  test('a name the query opens comes before one it only meets later', () {
    // `Ella Fitzgerald` opens with `el`; `Edward Elgar` meets it at its second
    // word. Each group is alphabetical.
    expect(names(index.find('el')), ['Ella Fitzgerald', 'Edward Elgar']);
    expect(titles(index.find('el')).last, 'Live at the Elgar Hall');
  });

  test('is blind to accents', () {
    expect(names(index.find('bjo')), ['Björk']);
    expect(names(index.find('BJÖ')), ['Björk']);
  });

  test('a second word narrows', () {
    expect(names(index.find('fitz')), ['Ella Fitzgerald']);
    expect(names(index.find('ella fitz')), ['Ella Fitzgerald']);
    expect(titles(index.find('ella fitz')), isEmpty);
  });

  test('says nothing for a query with no word in it', () {
    final found = index.find('  ');

    expect(found.artists, isEmpty);
    expect(found.albums, isEmpty);
  });

  test('says nothing for a word nobody starts', () {
    final found = index.find('zzz');

    expect(found.artists, isEmpty);
    expect(found.albums, isEmpty);
  });
}
