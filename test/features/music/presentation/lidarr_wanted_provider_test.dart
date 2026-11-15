import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';

import '../../../test_helpers/fake_services.dart';

/// A Lidarr whose `wanted/missing` walk is scripted.
class _Lidarr extends FakeLidarrService {
  _Lidarr({this.page, this.error});

  final ArrRecordPage? page;
  final Object? error;
  final asked = <Map<String, dynamic>?>[];

  @override
  Future<ArrRecordPage> getAllMissingPage({
    Map<String, dynamic>? queryParameters,
  }) async {
    asked.add(queryParameters);
    if (error != null) throw error!;
    return page!;
  }
}

ProviderContainer _container(_Lidarr lidarr) {
  final container = ProviderContainer(
    overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('lidarrWantedArtistIdsProvider', () {
    test(
      'answers the artists with a wanted album and how many each has',
      () async {
        final lidarr = _Lidarr(
          page: const ArrRecordPage(
            records: [
              {'id': 1, 'artistId': 7},
              {'id': 2, 'artistId': 7},
              {'id': 3, 'artistId': 9},
            ],
            total: 3,
          ),
        );
        final container = _container(lidarr);

        final wanted = await container.read(
          lidarrWantedArtistIdsProvider.future,
        );

        expect(wanted.ids, {7, 9});
        expect(wanted.countById, {7: 2, 9: 1});
        expect(wanted.isFloor, isFalse);
      },
    );

    test(
      'reads the ids alone: the artist is not embedded in every album',
      () async {
        final lidarr = _Lidarr(
          page: const ArrRecordPage(records: [], total: 0),
        );
        final container = _container(lidarr);

        await container.read(lidarrWantedArtistIdsProvider.future);

        expect(lidarr.asked.single, {'includeArtist': false});
      },
    );

    test('a walk that stopped before the end is a floor', () async {
      final lidarr = _Lidarr(
        page: const ArrRecordPage(
          records: [
            {'id': 1, 'artistId': 7},
          ],
          total: 30000,
          cutShort: true,
        ),
      );
      final container = _container(lidarr);

      final wanted = await container.read(lidarrWantedArtistIdsProvider.future);

      expect(wanted.isFloor, isTrue);
    });

    test(
      'a Lidarr that does not answer is a failure, never an empty set',
      () async {
        final lidarr = _Lidarr(
          error: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/wanted/missing'),
            reason: 'Connection refused',
          ),
        );
        final container = _container(lidarr);

        await expectLater(
          container.read(lidarrWantedArtistIdsProvider.future),
          throwsA(isA<DioException>()),
        );
        expect(container.read(lidarrWantedArtistIdsProvider).hasError, isTrue);
        expect(container.read(lidarrWantedArtistIdsProvider).hasValue, isFalse);
      },
    );

    test('is not read again on its own after a failure', () async {
      final lidarr = _Lidarr(
        error: DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/wanted/missing'),
          reason: 'Connection refused',
        ),
      );
      final container = _container(lidarr);
      final subscription = container.listen(
        lidarrWantedArtistIdsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await expectLater(
        container.read(lidarrWantedArtistIdsProvider.future),
        throwsA(isA<DioException>()),
      );
      // Long past the first backoff a retrying provider would have used.
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(lidarr.asked, hasLength(1));
    });
  });
}
