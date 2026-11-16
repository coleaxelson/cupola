/// The Music wall's Wanted chip, in the place of Missing: what Lidarr reports
/// under `wanted/missing`, folded to artists, with its failure said in the
/// house way.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/profiles/profiles.dart';

LidarrArtist _artist(int id, String name, {Map<String, dynamic>? statistics}) =>
    LidarrArtist(
      id: id,
      artistName: name,
      foreignArtistId: 'mb-$id',
      status: 'continuing',
      monitored: true,
      images: const [],
      genres: const [],
      statistics: statistics,
    );

/// Lidarr with three artists, one of them complete, and a scripted
/// `wanted/missing`.
class _Lidarr extends FakeLidarrService {
  _Lidarr(this.answer);

  /// Called on each read of the wanted walk.
  final Future<ArrRecordPage> Function(int read) answer;
  var reads = 0;

  @override
  Future<List<LidarrArtist>> getArtists() async => [
    _artist(
      1,
      'Anton Bruckner',
      statistics: const {
        'albumCount': 11,
        'trackCount': 60,
        'trackFileCount': 60,
      },
    ),
    // Short of 30 of its 31 albums, with a track of one on disk: the artist
    // Missing would have put under Available.
    _artist(
      2,
      'Bill Evans',
      statistics: const {
        'albumCount': 31,
        'trackCount': 400,
        'trackFileCount': 12,
      },
    ),
    _artist(
      3,
      'Brian Eno',
      statistics: const {
        'albumCount': 26,
        'trackCount': 300,
        'trackFileCount': 290,
      },
    ),
  ];

  @override
  Future<ArrRecordPage> getAllMissingPage({
    Map<String, dynamic>? queryParameters,
  }) => answer(reads++);
}

ArrRecordPage _page(List<int> artistIds, {bool cutShort = false}) =>
    ArrRecordPage(
      records: [
        for (final (index, artistId) in artistIds.indexed)
          {'id': index + 1, 'artistId': artistId},
      ],
      total: artistIds.length,
      cutShort: cutShort,
    );

Future<_Lidarr> _open(
  WidgetTester tester,
  Future<ArrRecordPage> Function(int read) answer, {
  Size size = const Size(390, 1000),
}) async {
  final lidarr = _Lidarr(answer);
  final harness = await ProfileHarness.start(
    Profiles.p1,
    overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
  );
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MusicScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await harness.settle(tester);
  return lidarr;
}

Future<void> _selectWanted(WidgetTester tester) async {
  // The chips scroll, and the test font is wide: the third may be past the
  // strip's edge.
  await tester.ensureVisible(find.text('Wanted'));
  await tester.pump();
  await tester.tap(find.text('Wanted'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('reads Wanted where the other walls read Missing', (
    tester,
  ) async {
    await _open(tester, (_) async => _page([2]));

    expect(find.text('Wanted'), findsOneWidget);
    expect(find.text('Missing'), findsNothing);
  });

  testWidgets('keeps the artists with a wanted album, says how many albums '
      'each, and says what wanted means', (tester) async {
    await _open(tester, (_) async => _page([2, 2, 2, 3]));
    expect(find.text('Anton Bruckner'), findsOneWidget);

    await _selectWanted(tester);

    expect(find.text('Anton Bruckner'), findsNothing);
    expect(find.text('Bill Evans'), findsOneWidget);
    expect(find.text('Brian Eno'), findsOneWidget);
    expect(find.text('3\u00A0albums wanted'), findsOneWidget);
    expect(find.text('1\u00A0album wanted'), findsOneWidget);
    // The completeness caption the wall draws elsewhere gives way to it.
    expect(find.textContaining('tracks missing'), findsNothing);
    expect(
      find.text(
        '2\u00A0artists have a wanted album: released, monitored, '
        'nothing on disk.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('finds the artist Missing would not: nearly nothing on disk is '
      'still a wanted album', (tester) async {
    await _open(tester, (_) async => _page([2]));

    await tester.tap(find.text('Available'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bill Evans'), findsOneWidget);

    await _selectWanted(tester);
    expect(find.text('Bill Evans'), findsOneWidget);
    expect(find.text('Brian Eno'), findsNothing);
  });

  testWidgets('a walk that stopped before the end reads as a floor', (
    tester,
  ) async {
    await _open(tester, (_) async => _page([2, 3], cutShort: true));

    await _selectWanted(tester);

    expect(find.text('1+\u00A0albums wanted'), findsNWidgets(2));
    expect(
      find.text(
        '2+\u00A0artists have a wanted album: released, monitored, '
        'nothing on disk.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('nothing wanted after a whole read says so', (tester) async {
    await _open(tester, (_) async => _page(const []));

    await _selectWanted(tester);

    expect(find.text('Nothing is wanted'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);
  });

  testWidgets('waits while Lidarr is asked, and never claims that nothing is '
      'wanted', (tester) async {
    await _open(tester, (_) => Completer<ArrRecordPage>().future);

    await _selectWanted(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nothing is wanted'), findsNothing);
    expect(find.text('Bill Evans'), findsNothing);
  });

  testWidgets('a Lidarr that does not answer is named, with the connection '
      'that failed, and Retry asks again', (tester) async {
    final lidarr = await _open(
      tester,
      (read) async => read == 0
          ? throw DioException.connectionError(
              requestOptions: RequestOptions(path: '/api/v1/wanted/missing'),
              reason: 'Connection refused',
            )
          : _page([3]),
    );

    await _selectWanted(tester);

    final failure = tester.widget<InlineErrorRetry>(
      find.byType(InlineErrorRetry),
    );
    final lens = ProviderScope.containerOf(
      tester.element(find.byType(MusicScreen)),
    ).read(activeInstanceProvider(ServiceKey.lidarr))?.id;
    expect(lens, isNotNull);
    expect(failure.service, ServiceKey.lidarr);
    expect(failure.instanceId, lens);
    expect(
      failure.message,
      endsWith(', so the artists with a wanted album are not shown.'),
    );
    expect(find.text('Nothing is wanted'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(lidarr.reads, 2);
    expect(find.byType(InlineErrorRetry), findsNothing);
    expect(find.text('Brian Eno'), findsOneWidget);
    expect(find.text('Bill Evans'), findsNothing);
  });

  testWidgets('a failure of the wanted read leaves the rest of the wall '
      'alone', (tester) async {
    await _open(
      tester,
      (_) async => throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/v1/wanted/missing'),
        reason: 'Connection refused',
      ),
    );

    // The wall, the chips and the library read as they did.
    expect(find.text('Anton Bruckner'), findsOneWidget);
    expect(find.byType(InlineErrorRetry), findsNothing);
  });
}
