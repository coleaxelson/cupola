import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/music/domain/more_from_your_artists.dart';
import 'package:cupola/features/music/presentation/more_from_your_artists_provider.dart';
import 'package:cupola/demo/world/fakes/arr_fakes.dart';
import 'package:cupola/demo/world/profiles.dart';

import '../test_helpers/profiles/profiles.dart' show ProfileHarness;

/// The shelf of made-up artists is the demo's alone. The profiles' Lidarr, which
/// every test and the testlab read, holds what it held before the shelf: the
/// world's own artist and its four albums, so a figure folded over it (the
/// stack card's albums, a count of artists) does not move when the demo's wall
/// is given something to scroll. The same goes for the albums the demo leaves
/// alone, which Discover's `More from your artists` is made of: out already,
/// nothing on disk, not monitored.
void main() {
  Future<Object?> get(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  Future<List<Object?>> list(String url) async =>
      await get(url) as List<Object?>;

  const lidarr = '${WorldHosts.lidarr}/api/v1';

  /// The albums of [all] the shelf is made of.
  List<Map<String, Object?>> leftAlone(List<Object?> all) => [
    for (final album in all.cast<Map<String, Object?>>())
      if (album['monitored'] == false &&
          ((album['statistics'] as Map)['trackFileCount'] as int) == 0)
        album,
  ];

  test('a profile read as written has one artist and four albums', () async {
    final network = ProfileNetwork(Profiles.p1);
    addTearDown(network.install());

    expect(await list('$lidarr/artist'), hasLength(1));
    expect(await list('$lidarr/album'), hasLength(4));
  });
  test(
    'a profile has no album left alone, and its wishlist is as it was',
    () async {
      final network = ProfileNetwork(Profiles.p1);
      addTearDown(network.install());

      expect(leftAlone(await list('$lidarr/album')), isEmpty);
      // The catalog knows no album of that name the library holds.
      for (final hit in await list('$lidarr/search?term=dragon')) {
        final album = (hit as Map)['album'];
        expect(album == null || (album as Map)['id'] == 0, isTrue);
      }
    },
  );

  test('the demo, once the world lives, has the shelf as well', () async {
    final network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());

    expect(await list('$lidarr/artist'), hasLength(LidarrFake.shelfCount + 1));
    expect(
      (await list('$lidarr/album')).length,
      greaterThan(4),
      reason: 'the shelf has albums',
    );
  });

  test(
    'the demo leaves albums alone: the world\'s three of the board, and '
    'enough of the shelf\'s that See all holds more than the shelf',
    () async {
      final network = ProfileNetwork(demoProfile)..live();
      addTearDown(network.install());

      final left = leftAlone(await list('$lidarr/album'));
      final world = left.where((album) => album['artistId'] == 1);
      expect(world.map((album) => album['title']), [
        'Big Buck Bunny Suite',
        'The Dragon',
        'Snow',
      ]);
      // More than the twenty the shelf holds, each by an artist the library
      // holds (the album carries its artist's id).
      expect(left.length, greaterThan(20));
      final artists = (await list(
        '$lidarr/artist',
      )).map((a) => (a as Map)['id']);
      expect(
        left.every((album) => artists.contains(album['artistId'])),
        isTrue,
      );
      // None of them is wanted: Lidarr was told to leave them alone.
      final wanted = await get('$lidarr/wanted/missing?pageSize=1000') as Map;
      expect(wanted['records'], isNotEmpty);
      expect(
        leftAlone(wanted['records'] as List<Object?>),
        isEmpty,
        reason: 'a monitored album only is on the wishlist',
      );
    },
  );

  test('the albums the demo leaves alone list their tracks, none on disk, as '
      'many as their statistics count', () async {
    final network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());

    final left = leftAlone(await list('$lidarr/album'));
    expect(left, isNotEmpty);
    for (final album in left) {
      final tracks = await list('$lidarr/track?albumId=${album['id']}');
      expect(
        tracks,
        hasLength((album['statistics'] as Map)['totalTrackCount'] as int),
        reason: '${album['title']}',
      );
      expect(
        tracks.every((t) => (t as Map)['hasFile'] == false),
        isTrue,
        reason: '${album['title']}',
      );
    }
    // The finder reads an artist's tracks at once: the world's own now hold
    // the three albums left alone beside Sintel's five.
    final jan = await list('$lidarr/track?artistId=1');
    expect(jan, hasLength(5 + 3 * 5));
    // A monitored shelf album still lists its ten, by album as by artist.
    expect(await list('$lidarr/track?albumId=100100'), hasLength(10));
  });

  test('a profile\'s tracks are as they were: Sintel\'s five, and nothing '
      'for an album left alone', () async {
    final network = ProfileNetwork(Profiles.p1);
    addTearDown(network.install());

    expect(await list('$lidarr/track?artistId=1'), hasLength(5));
    expect(await list('$lidarr/track?albumId=12'), isEmpty);
  });

  test('the catalog finds an album the demo leaves alone as the library '
      'holds it', () async {
    final network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());

    final found = await list('$lidarr/search?term=dragon');
    final album = found.single as Map;
    expect((album['album'] as Map)['id'], 12);
    expect((album['album'] as Map)['monitored'], isFalse);
  });

  test('the shelf Discover draws from them is full, newest first, and the '
      'world\'s three are on it', () async {
    final harness = await ProfileHarness.start(demoProfile);
    harness.network.live();
    final container = harness.container();

    final shelf = await container.read(moreFromYourArtistsProvider.future);

    expect(shelf.albums.length, greaterThan(MoreFromYourArtists.shelfLength));
    expect(shelf.shelf, hasLength(MoreFromYourArtists.shelfLength));
    final dates = [for (final entry in shelf.albums) entry.album.releaseDate!];
    expect(dates, [...dates]..sort((a, b) => b.compareTo(a)));
    expect(
      shelf.albums
          .where((entry) => entry.artist.artistName == 'Jan Morgenstern')
          .map((entry) => entry.album.title),
      ['Snow', 'The Dragon', 'Big Buck Bunny Suite'],
    );
  });
}
