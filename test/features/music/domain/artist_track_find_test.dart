/// Finding a track among an artist's albums: the matching, the order, and the
/// words of a row, which never contradict the album's own.
library;

import 'package:flutter/painting.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/music/domain/artist_track_find.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';

final _now = DateTime(2026, 11, 15);

LidarrAlbum _album(
  int id,
  String title, {
  String year = '2010',
  int files = 5,
  int tracks = 5,
  bool monitored = true,
  String? date,
}) => LidarrAlbum.fromJson({
  'id': id,
  'title': title,
  'monitored': monitored,
  'releaseDate': date ?? '$year-01-01T00:00:00Z',
  'statistics': {'trackFileCount': files, 'totalTrackCount': tracks},
});

LidarrTrack _track(
  int id,
  int albumId,
  String title, {
  int number = 1,
  int duration = 0,
  bool hasFile = true,
  int? medium,
}) => LidarrTrack.fromJson({
  'id': id,
  'albumId': albumId,
  'title': title,
  'trackNumber': '$number',
  'mediumNumber': ?medium,
  'duration': duration,
  'hasFile': hasFile,
});

List<String> _titles(List<ArtistTrackHit> hits) => [
  for (final hit in hits) '${hit.track.title} @ ${hit.album.title}',
];

void main() {
  final sintel = _album(3, 'Sintel');
  final single = _album(9, 'The Dragon', files: 0, tracks: 1);
  final cafe = _album(5, 'Café Lumière', year: '2006');
  final albums = [sintel, single, cafe];
  final tracks = [
    _track(301, 3, 'Opening', number: 1),
    _track(303, 3, 'The Dragon', number: 3, duration: 336000),
    _track(304, 3, 'Snow', number: 4),
    _track(901, 9, 'The Dragon', hasFile: false),
    _track(501, 5, 'Café au lait'),
    _track(502, 5, 'Dragonfly'),
    _track(777, 404, 'The Dragon of an album the artist does not list'),
  ];
  final index = ArtistTrackIndex(tracks: tracks, albums: albums);

  group('finding', () {
    test('a word typed starts a word of the title', () {
      expect(_titles(index.find('snow')), ['Snow @ Sintel']);
      expect(_titles(index.find('drag')), [
        'Dragonfly @ Café Lumière',
        'The Dragon @ Sintel',
        'The Dragon @ The Dragon',
      ]);
      expect(index.find('ragon'), isEmpty);
    });

    test('is blind to case and accents, both ways', () {
      expect(_titles(index.find('CAFE')), ['Café au lait @ Café Lumière']);
      expect(_titles(index.find('café')), ['Café au lait @ Café Lumière']);
    });

    test('several words must each start a word, in any order', () {
      expect(_titles(index.find('dragon the')), [
        'The Dragon @ Sintel',
        'The Dragon @ The Dragon',
      ]);
      expect(index.find('dragon opening'), isEmpty);
    });

    test('finds nothing for a query with no word in it', () {
      expect(index.find(''), isEmpty);
      expect(index.find('  '), isEmpty);
      expect(index.find('!?'), isEmpty);
    });

    test('leaves out a track whose album the artist does not list', () {
      expect(index.length, 6);
      expect(index.find('album'), isEmpty);
    });

    test('lists a title the query opens before one it meets later, then '
        'newest album first, then in track order', () {
      final extra = ArtistTrackIndex(
        tracks: [
          _track(1, 3, 'Winter Dragon', number: 2),
          _track(2, 9, 'Dragon', number: 1),
          _track(3, 5, 'Dragon', number: 7),
          _track(4, 3, 'Dragon', number: 2),
          _track(5, 3, 'Dragon', number: 1, medium: 2),
        ],
        albums: albums,
      );
      // The same year, so the album with the lower id leads; the older
      // `Café Lumière` follows, and the title the query only meets later is
      // last. Within an album, by disc and then by number.
      expect(
        [for (final hit in extra.find('dragon')) hit.track.id],
        [4, 5, 2, 3, 1],
      );
    });
  });

  group('the marks', () {
    test('mark what was typed at the start of the word it opened', () {
      final hit = index.find('the drag').first;
      expect(hit.track.title, 'The Dragon');
      expect(hit.marks, const [TextRange(start: 0, end: 8)]);
    });

    test('mark an accented title where the plain letters were typed', () {
      final hit = index.find('cafe').single;
      expect(hit.marks, const [TextRange(start: 0, end: 4)]);
    });
  });

  group('a row', () {
    test('says the album, the place on it and the length when known', () {
      expect(trackMeta(tracks[1], sintel), 'Sintel\u00A0· track 3\u00A0· 5:36');
      expect(trackMeta(tracks[0], sintel), 'Sintel\u00A0· track 1');
    });

    test('a track with a file is on disk, in green', () {
      final state = trackState(
        tracks[1],
        sintel,
        queue: ArrQueueSnapshot.empty,
        now: _now,
      );
      expect(state?.word, 'On disk');
      expect(state?.tone, StatusTone.success);
      expect(state?.hollow, isFalse);
    });

    test('a track without one takes its album\'s word, so it never '
        'contradicts the album', () {
      final wanted = trackState(
        tracks[3],
        single,
        queue: ArrQueueSnapshot.empty,
        now: _now,
      );
      expect(wanted?.word, 'Wanted');
      expect(wanted?.hollow, isTrue);

      final unmonitored = _album(11, 'B-sides', files: 0, monitored: false);
      expect(
        trackState(
          _track(1, 11, 'x', hasFile: false),
          unmonitored,
          queue: ArrQueueSnapshot.empty,
          now: _now,
        )?.word,
        'Unmonitored',
      );

      final coming = _album(12, 'Next', date: '2027-01-01T00:00:00Z', files: 0);
      expect(
        trackState(
          _track(1, 12, 'x', hasFile: false),
          coming,
          queue: ArrQueueSnapshot.empty,
          now: _now,
        )?.word,
        contains('not out yet'),
      );
    });

    test('waits for the queue where its album does', () {
      expect(
        trackState(
          tracks[3],
          single,
          queue: ArrQueueSnapshot.unknown,
          now: _now,
        ),
        isNull,
      );
      // Once the queue has failed it says it does not know.
      expect(
        trackState(
          tracks[3],
          single,
          queue: ArrQueueSnapshot.failed(Exception('down')),
          now: _now,
        )?.word,
        'Unknown',
      );
    });

    test('is one sentence', () {
      final on = trackState(
        tracks[1],
        sintel,
        queue: ArrQueueSnapshot.empty,
        now: _now,
      );
      expect(
        trackSpoken(tracks[1], sintel, state: on),
        'The Dragon, track 3 on Sintel, 5:36, on disk',
      );
      expect(
        trackSpoken(tracks[3], single, state: null),
        'The Dragon, track 1 on The Dragon',
      );
    });

    test('counts its heading with the figure kept to its noun', () {
      expect(trackCountWords(2), '2\u00A0tracks');
      expect(trackCountWords(1), '1\u00A0track');
    });
  });
}
