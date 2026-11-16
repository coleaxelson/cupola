/// What kind an album is: one kind each, so that the kinds add up to the
/// artist's albums.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/album_kind.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';

LidarrAlbum _album(
  int id, {
  String? type = 'Album',
  List<Object?> secondary = const [],
}) => LidarrAlbum.fromJson({
  'id': id,
  'title': 'Album $id',
  'albumType': type,
  'secondaryTypes': secondary,
  'monitored': true,
});

void main() {
  group('the kind of an album', () {
    test('is its primary type when it has no secondary one', () {
      expect(AlbumKind.of(_album(1)), AlbumKind.album);
      expect(AlbumKind.of(_album(1, type: 'EP')), AlbumKind.ep);
      expect(AlbumKind.of(_album(1, type: 'Single')), AlbumKind.single);
      expect(AlbumKind.of(_album(1, type: 'Broadcast')), AlbumKind.broadcast);
      expect(AlbumKind.of(_album(1, type: 'Other')), AlbumKind.other);
    });

    test('is its first secondary type that means something, over the '
        'primary one', () {
      expect(AlbumKind.of(_album(1, secondary: ['Live'])), AlbumKind.live);
      expect(
        AlbumKind.of(_album(1, type: 'EP', secondary: ['Soundtrack'])),
        AlbumKind.soundtrack,
      );
      expect(
        AlbumKind.of(_album(1, secondary: ['Live', 'Compilation'])),
        AlbumKind.live,
      );
      expect(
        AlbumKind.of(_album(1, secondary: ['Compilation', 'Live'])),
        AlbumKind.compilation,
      );
    });

    test('is never Studio: that is what an album is, not a kind', () {
      expect(AlbumKind.of(_album(1, secondary: ['Studio'])), AlbumKind.album);
      expect(
        AlbumKind.of(_album(1, type: 'Single', secondary: ['Studio'])),
        AlbumKind.single,
      );
      expect(
        AlbumKind.of(_album(1, secondary: ['Studio', 'Remix'])),
        AlbumKind.remix,
      );
    });

    test('reads every secondary type MusicBrainz has', () {
      const named = {
        'Live': AlbumKind.live,
        'Compilation': AlbumKind.compilation,
        'Soundtrack': AlbumKind.soundtrack,
        'Spokenword': AlbumKind.spokenWord,
        'Interview': AlbumKind.interview,
        'Audiobook': AlbumKind.audiobook,
        'Remix': AlbumKind.remix,
        'DJ-mix': AlbumKind.djMix,
        'Mixtape/Street': AlbumKind.mixtape,
        'Demo': AlbumKind.demo,
        'Audio drama': AlbumKind.audioDrama,
      };
      for (final MapEntry(:key, :value) in named.entries) {
        expect(AlbumKind.of(_album(1, secondary: [key])), value, reason: key);
      }
    });

    test('is Other when Lidarr says nothing, or something unheard of', () {
      expect(AlbumKind.of(_album(1, type: null)), AlbumKind.other);
      expect(AlbumKind.of(_album(1, type: 'Podcast')), AlbumKind.other);
      expect(
        AlbumKind.of(_album(1, secondary: ['Field recording'])),
        AlbumKind.album,
      );
    });
  });

  group('the kinds of an artist', () {
    final albums = [
      _album(1, secondary: ['Soundtrack']),
      _album(2, type: 'Single'),
      _album(3, type: 'EP'),
      _album(4, type: 'Single'),
      _album(5, secondary: ['Soundtrack', 'Studio']),
      _album(6),
      _album(7, type: 'Single'),
      _album(8, secondary: ['Soundtrack']),
      _album(9, type: 'Single'),
    ];

    test('add up to the albums, each album under exactly one', () {
      final kinds = albumKindsOf(albums);
      expect(kinds.fold<int>(0, (sum, kind) => sum + kind.count), 9);
      expect(kinds.map((kind) => (kind.kind, kind.count)), [
        (AlbumKind.album, 1),
        (AlbumKind.ep, 1),
        (AlbumKind.single, 4),
        (AlbumKind.soundtrack, 3),
      ]);
    });

    test('keep a fixed order: the usual kinds, the rest, Other last', () {
      final every = [
        _album(1, type: 'Other'),
        _album(2, secondary: ['Demo']),
        _album(3, secondary: ['Remix']),
        _album(4, secondary: ['Compilation']),
        _album(5, type: 'Single'),
        _album(6, type: 'EP'),
        _album(7),
      ];
      expect(albumKindsOf(every).map((entry) => entry.kind), [
        AlbumKind.album,
        AlbumKind.ep,
        AlbumKind.single,
        AlbumKind.compilation,
        AlbumKind.remix,
        AlbumKind.demo,
        AlbumKind.other,
      ]);
      expect(AlbumKind.values.take(7), [
        AlbumKind.album,
        AlbumKind.ep,
        AlbumKind.single,
        AlbumKind.live,
        AlbumKind.compilation,
        AlbumKind.soundtrack,
        AlbumKind.remix,
      ]);
      expect(AlbumKind.values.last, AlbumKind.other);
    });

    test('leave a kind with no album out', () {
      expect(albumKindsOf([_album(1), _album(2)]).map((k) => k.kind), [
        AlbumKind.album,
      ]);
      expect(albumKindsOf(const []), isEmpty);
    });

    test('filter the albums to one kind, and to all without one', () {
      expect(albumsOfKind(albums, null), hasLength(9));
      expect(albumsOfKind(albums, AlbumKind.single).map((a) => a.id), [
        2,
        4,
        7,
        9,
      ]);
      expect(albumsOfKind(albums, AlbumKind.live), isEmpty);
    });
  });

  group('the words', () {
    test('a pill and a fact say the kind', () {
      expect(AlbumKind.single.label, 'Singles');
      expect(AlbumKind.ep.label, 'EPs');
      expect(AlbumKind.djMix.label, 'DJ mixes');
      // MusicBrainz's `Live`, in a word the Never list allows.
      expect(AlbumKind.live.label, 'Concerts');
      expect(AlbumKind.live.fact, 'Concert');
      expect(
        unmonitoredWords(1, kind: AlbumKind.live),
        '1\u00A0unmonitored concert',
      );
      expect(AlbumKind.single.fact, 'Single');
      expect(AlbumKind.ep.fact, 'EP');
    });

    test('a count keeps its figure with its noun', () {
      expect(AlbumKind.single.count(1), '1\u00A0single');
      expect(AlbumKind.single.count(2), '2\u00A0singles');
      expect(albumCountWords(3), '3\u00A0albums');
      expect(albumCountWords(1), '1\u00A0album');
      expect(albumCountWords(2, kind: AlbumKind.single), '2\u00A0singles');
    });

    test('the unmonitored line speaks the kind', () {
      expect(unmonitoredWords(3), '3\u00A0unmonitored albums');
      expect(unmonitoredWords(1), '1\u00A0unmonitored album');
      expect(
        unmonitoredWords(1, kind: AlbumKind.single),
        '1\u00A0unmonitored single',
      );
      expect(
        unmonitoredWords(2, kind: AlbumKind.soundtrack),
        '2\u00A0unmonitored soundtracks',
      );
      expect(unmonitoredWords(2, kind: AlbumKind.ep), '2\u00A0unmonitored EPs');
    });

    test('a kind with no noun of its own falls back to releases', () {
      expect(
        unmonitoredWords(2, kind: AlbumKind.other),
        '2\u00A0unmonitored releases',
      );
      expect(
        unmonitoredWords(1, kind: AlbumKind.spokenWord),
        '1\u00A0unmonitored release',
      );
    });

    test('a row says the kind after the year only when asked to', () {
      final single = _album(1, type: 'Single');
      expect(albumFacts(single), isEmpty);
      expect(albumFacts(single, withKind: true), ['Single']);
      final dated = LidarrAlbum.fromJson({
        'id': 1,
        'title': 'x',
        'albumType': 'Single',
        'releaseDate': '2010-01-01T00:00:00Z',
        'statistics': {'totalTrackCount': 1},
      });
      expect(albumFacts(dated, withKind: true), [
        '2010',
        'Single',
        '1\u00A0track',
      ]);
      expect(albumSpokenFacts(dated, withKind: true), [
        '2010',
        'Single',
        '1\u00A0track',
      ]);
    });
  });
}
