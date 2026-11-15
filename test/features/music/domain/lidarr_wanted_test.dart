import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/music/domain/lidarr_wanted.dart';

void main() {
  group('lidarrWantedFrom', () {
    test('folds the albums Lidarr answers with to one entry per artist', () {
      final wanted = lidarrWantedFrom(
        const ArrRecordPage(
          records: [
            {'id': 1, 'artistId': 7},
            {'id': 2, 'artistId': 7},
            {'id': 3, 'artistId': 9},
            {'id': 4, 'artistId': 7},
          ],
          total: 4,
        ),
      );

      expect(wanted.countById, {7: 3, 9: 1});
      expect(wanted.ids, {7, 9});
      expect(wanted.isFloor, isFalse);
    });

    test('drops a row that names no artist, rather than inventing one', () {
      final wanted = lidarrWantedFrom(
        const ArrRecordPage(
          records: [
            {'id': 1},
            {'id': 2, 'artistId': 'seven'},
            'not a map',
            {'id': 3, 'artistId': 5},
          ],
          total: 4,
        ),
      );

      expect(wanted.countById, {5: 1});
    });

    test('a whole answer with nothing in it is the answer that nothing is '
        'wanted', () {
      final wanted = lidarrWantedFrom(
        const ArrRecordPage(records: [], total: 0),
      );

      expect(wanted.countById, isEmpty);
      expect(wanted.isFloor, isFalse);
    });

    test('a walk that stopped short is a floor', () {
      final wanted = lidarrWantedFrom(
        const ArrRecordPage(
          records: [
            {'id': 1, 'artistId': 7},
          ],
          total: 30000,
          cutShort: true,
        ),
      );

      expect(wanted.isFloor, isTrue);
    });
  });

  group('the words', () {
    test('an artist\'s caption counts albums, with a no-break space', () {
      expect(lidarrWantedCaption(1, false), '1\u00A0album wanted');
      expect(lidarrWantedCaption(3, false), '3\u00A0albums wanted');
      expect(lidarrWantedCaption(12, false), '12\u00A0albums wanted');
    });

    test('a floor reads as one and is never singular', () {
      expect(lidarrWantedCaption(50, true), '50+\u00A0albums wanted');
      expect(lidarrWantedCaption(1, true), '1+\u00A0albums wanted');
    });

    test('the line says what wanted means, in the singular for one', () {
      expect(
        lidarrWantedSummary(34, false),
        '34\u00A0artists have a wanted album: released, monitored, '
        'nothing on disk.',
      );
      expect(
        lidarrWantedSummary(1, false),
        '1\u00A0artist has a wanted album: released, monitored, '
        'nothing on disk.',
      );
      expect(
        lidarrWantedSummary(34, true),
        '34+\u00A0artists have a wanted album: released, monitored, '
        'nothing on disk.',
      );
    });
  });
}
