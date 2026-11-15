/// Music in Discover's search: the section the operator's music source adds
/// after the series, its three rows and what each says and does, the way to
/// the Music wall, and every state of the source.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_music_section.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_album_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _nbsp = '\u00A0';

LidarrArtist _artist(
  int id,
  String name, {
  String foreign = '',
  String? type,
  String? disambiguation,
}) => LidarrArtist(
  id: id,
  artistName: name,
  foreignArtistId: foreign,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  artistType: type,
  disambiguation: disambiguation,
);

LidarrAlbum _album(
  int id,
  String title,
  int artistId, {
  required String foreign,
  String year = '2010',
  int files = 5,
  bool monitored = true,
  String type = 'Album',
}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  foreignAlbumId: foreign,
  albumType: type,
  releaseDate: '$year-01-01T00:00:00Z',
  monitored: monitored,
  images: const [],
  statistics: {'trackFileCount': files, 'totalTrackCount': 5},
);

/// A Lidarr whose library is Jan Morgenstern and two of his albums, and whose
/// search is [answer].
class _Lidarr extends FakeLidarrService {
  _Lidarr({this.answer = const [], this.error, this.gate, this.libraryError});

  List<LidarrSearchHit> answer;
  Object? error;
  final Completer<void>? gate;
  Object? libraryError;
  final searched = <String>[];
  final monitored = <int>[];
  var albumReads = 0;

  static final jan = _artist(1, 'Jan Morgenstern', foreign: 'mb-jan');

  @override
  Future<List<LidarrArtist>> getArtists() async => [jan];

  @override
  Future<List<LidarrAlbum>> getAllAlbumsOrThrow() async {
    albumReads++;
    if (libraryError != null) throw libraryError!;
    return [
      _album(3, 'Spring Suite', 1, foreign: 'mb-spring'),
      _album(
        7,
        'The Dragon',
        1,
        foreign: 'mb-dragon',
        files: 0,
        monitored: false,
        type: 'Single',
      ),
    ];
  }

  @override
  Future<List<LidarrSearchHit>> search(
    String term, {
    CancelToken? cancelToken,
  }) async {
    searched.add(term);
    await gate?.future;
    if (error != null) throw error!;
    return answer;
  }

  @override
  Future<void> monitorAndSearchAlbum(int albumId) async {
    monitored.add(albumId);
  }
}

LidarrAlbumHit _albumHit(
  String title,
  String foreign,
  LidarrArtist artist, {
  String type = 'Album',
  String year = '2010',
}) {
  final raw = {
    'id': 0,
    'title': title,
    'foreignAlbumId': foreign,
    'albumType': type,
    'releaseDate': '$year-04-14T00:00:00Z',
    'monitored': false,
    'images': const <Object?>[],
    'artist': {
      'id': artist.id,
      'artistName': artist.artistName,
      'foreignArtistId': artist.foreignArtistId,
      'artistType': artist.artistType,
      'status': 'continuing',
      'monitored': false,
      'images': const <Object?>[],
      'genres': const <Object?>[],
    },
  };
  return LidarrAlbumHit(
    album: LidarrAlbum.fromJson(raw),
    artist: artist,
    raw: raw,
  );
}

/// What the catalog answers for the word: an album the library holds, and one it
/// holds and leaves alone, and one by Jan Morgenstern it has not got.
List<LidarrSearchHit> _spring() => [
  _albumHit('Spring Suite', 'mb-spring', _Lidarr.jan),
  _albumHit('The Dragon', 'mb-dragon', _Lidarr.jan, type: 'Single'),
  _albumHit(
    'Spring Reprise',
    'mb-reprise',
    _Lidarr.jan,
    type: 'EP',
    year: '2012',
  ),
];

/// What the catalog answers for Elbow: neither is held.
List<LidarrSearchHit> _elbow() {
  final elbow = _artist(
    0,
    'Elbow',
    foreign: 'mb-elbow',
    type: 'Group',
    disambiguation: 'Bury, England',
  );
  return [
    LidarrArtistHit(elbow),
    _albumHit('The Seldom Seen Kid', 'mb-kid', elbow, year: '2008'),
    _albumHit('Build a Rocket Boys!', 'mb-rocket', elbow, year: '2011'),
    _albumHit('Leaders of the Free World', 'mb-leaders', elbow, year: '2005'),
  ];
}

/// The profile's Radarr and Sonarr answer every word with their whole library
/// (their fakes know no better): without them a word can find nothing.
final _seerrAndLidarr = Profiles.p1
    .without(ServiceKey.radarr)
    .without(ServiceKey.sonarr);

class _Opened {
  Uri? uri;
}

Future<
  ({ProfileHarness harness, _Lidarr lidarr, GoRouter router, _Opened opened})
>
_open(
  WidgetTester tester, {
  String query = 'sprite',
  _Lidarr? lidarr,
  ConfigProfile? profile,
  bool requester = false,
  Size size = const Size(390, 2400),
  double textScale = 1,
  bool settle = true,
}) async {
  final fake = lidarr ?? _Lidarr(answer: _spring());
  final harness = await ProfileHarness.start(
    profile ?? Profiles.p1,
    overrides: [
      globalSearchQueryProvider.overrideWith((ref) => query),
      lidarrServiceProvider.overrideWithValue(fake),
      if (requester) audienceProvider.overrideWithValue(Audience.requester),
    ],
  );
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  final router = GoRouter(
    initialLocation: ServiceRoutes.discover,
    routes: [
      GoRoute(
        path: ServiceRoutes.discover,
        builder: (context, state) => const DiscoverPage(),
        routes: [
          GoRoute(
            path: 'media/movie/:id',
            builder: (context, state) => const Scaffold(body: Text('Title')),
          ),
        ],
      ),
      GoRoute(
        path: ServiceRoutes.lidarrLibrary,
        builder: (context, state) => const Scaffold(body: Text('The wall')),
        routes: [
          GoRoute(
            path: 'artist/:id',
            builder: (context, state) {
              opened.uri = state.uri;
              return Scaffold(
                body: Text('artist ${state.pathParameters['id']}'),
              );
            },
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await harness.settle(tester);
  } else {
    // A source still out draws a plate that never stops: frames, not settling.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return (harness: harness, lidarr: fake, router: router, opened: opened);
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SearchRow));

Finder _plus(String title) =>
    find.descendant(of: _row(title), matching: find.byIcon(Icons.add_rounded));

void main() {
  group('who gets the section', () {
    testWidgets('the operator with a music source: Music after the series, '
        'before the people, and the field says music', (tester) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(tester);

      expect(find.text('Movies, series, people, music'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.byType(DiscoverMusicSection), findsOneWidget);
      // Sprite Fright is on the server, in all of Seerr, Radarr and Jellyfin:
      // Music follows what the server holds, as the board draws it.
      expect(_top(tester, 'On your server'), lessThan(_top(tester, 'Music')));
      expect(_top(tester, 'Music'), lessThan(_top(tester, 'People')));

      await harness.unmount(tester);
    });

    testWidgets('the requester sees none of it, and the field keeps its '
        'words', (tester) async {
      final (:harness, :lidarr, router: _, opened: _) = await _open(
        tester,
        requester: true,
      );

      expect(find.text('Movies, series, people'), findsOneWidget);
      expect(find.text('Music'), findsNothing);
      expect(find.textContaining('Lidarr'), findsNothing);
      expect(lidarr.searched, isEmpty);

      await harness.unmount(tester);
    });

    testWidgets('without a music source, the field and the answer are as '
        'they were', (tester) async {
      final (:harness, :lidarr, router: _, opened: _) = await _open(
        tester,
        profile: Profiles.p1.without(ServiceKey.lidarr),
      );

      expect(find.text('Movies, series, people'), findsOneWidget);
      expect(find.text('Music'), findsNothing);
      expect(lidarr.searched, isEmpty);

      await harness.unmount(tester);
    });

    testWidgets('without Seerr there are no people, and the field says '
        'so', (tester) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        profile: Profiles.p1.without(ServiceKey.seerr),
      );

      expect(find.text('Movies, series, music'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('nothing found: no Music heading, no way to the wall', (
      tester,
    ) async {
      final (:harness, :lidarr, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(),
        query: 'qwxz',
      );

      expect(lidarr.searched, ['qwxz']);
      expect(find.text('Music'), findsNothing);
      expect(find.textContaining('Show all music'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the rows', () {
    testWidgets('at most three, each with the kind first, then who and when', (
      tester,
    ) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(answer: _elbow()),
        query: 'elbow',
      );

      expect(find.text('Elbow'), findsOneWidget);
      expect(
        find.text('Artist$_nbsp· Group$_nbsp· Bury, England'),
        findsOneWidget,
      );
      expect(find.text('The Seldom Seen Kid'), findsOneWidget);
      expect(find.text('Album$_nbsp· Elbow$_nbsp· 2008'), findsOneWidget);
      expect(find.text('Build a Rocket Boys!'), findsOneWidget);
      // The fourth is on the wall.
      expect(find.text('Leaders of the Free World'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('held rows say where they stand, and have no plus', (
      tester,
    ) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(tester);

      expect(
        find.text('Album$_nbsp· Jan Morgenstern$_nbsp· 2010'),
        findsOneWidget,
      );
      // Spring Suite is complete; The Dragon is held and left alone, and carries
      // the plus that monitors it; the third is not held.
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Unmonitored'), findsOneWidget);
      expect(
        find.text('Single$_nbsp· Jan Morgenstern$_nbsp· 2010'),
        findsOneWidget,
      );
      expect(_plus('Spring Suite'), findsNothing);
      expect(_plus('The Dragon'), findsOneWidget);
      expect(_plus('Spring Reprise'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Monitor The Dragon and search for it'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a row speaks one sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(answer: [..._spring(), ..._elbow().take(1)]),
      );

      expect(
        find.bySemanticsLabel(
          'Spring Suite, album by Jan Morgenstern, 2010, Complete',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Spring Reprise, EP by Jan Morgenstern, 2012, not in your library',
        ),
        findsOneWidget,
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a held artist and a held album open the artist, the album '
        'landed on', (tester) async {
      final (:harness, lidarr: _, :router, :opened) = await _open(tester);

      await tester.tap(_row('Spring Suite'));
      await harness.settle(tester);

      expect(router.state.uri.path, '${ServiceRoutes.lidarrArtistBase}/1');
      expect(opened.uri?.queryParameters[ServiceRoutes.albumParam], '3');

      await harness.unmount(tester);
    });

    testWidgets('a held artist opens their page', (tester) async {
      final (:harness, lidarr: _, :router, :opened) = await _open(
        tester,
        lidarr: _Lidarr(answer: [LidarrArtistHit(_Lidarr.jan)]),
        query: 'jan',
      );

      expect(find.text('In your library'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      await tester.tap(_row('Jan Morgenstern'));
      await harness.settle(tester);

      expect(router.state.uri.path, '${ServiceRoutes.lidarrArtistBase}/1');
      expect(opened.uri?.queryParameters, isEmpty);

      await harness.unmount(tester);
    });

    testWidgets('the plus of an album the library lacks opens its add sheet', (
      tester,
    ) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(tester);

      await tester.tap(_plus('Spring Reprise'));
      await harness.settle(tester);

      expect(find.byType(LidarrAddAlbumSheet), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('the plus of an artist the library lacks opens its add '
        'sheet', (tester) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(answer: _elbow()),
        query: 'elbow',
      );

      await tester.tap(_plus('Elbow'));
      await harness.settle(tester);

      expect(find.byType(LidarrAddArtistSheet), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('the plus of an album left alone monitors it and searches', (
      tester,
    ) async {
      final (:harness, :lidarr, router: _, opened: _) = await _open(tester);

      await tester.tap(_plus('The Dragon'));
      await harness.settle(tester);

      expect(lidarr.monitored, [7]);

      await harness.unmount(tester);
    });

    testWidgets('Show all opens the wall on Lidarr’s search, with the '
        'same words', (tester) async {
      final (:harness, lidarr: _, :router, opened: _) = await _open(tester);

      expect(find.text('Show all music for “sprite”'), findsOneWidget);
      await tester.ensureVisible(find.text('Show all music for “sprite”'));
      await tester.tap(find.text('Show all music for “sprite”'));
      await harness.settle(tester);

      expect(router.state.uri.path, ServiceRoutes.lidarrLibrary);
      final container = ProviderScope.containerOf(
        tester.element(find.text('The wall')),
      );
      expect(container.read(musicSearchQueryProvider), 'sprite');
      expect(container.read(musicFindScopeProvider), MediaFindScope.service);

      await harness.unmount(tester);
    });

    testWidgets('at twice the reading size nothing overflows', (tester) async {
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(answer: _elbow()),
        query: 'elbow',
        textScale: 2,
        size: const Size(390, 4000),
      );

      expect(find.text('Music'), findsOneWidget);
      expect(find.byType(SearchRow), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('the states of the source', () {
    testWidgets('answering after the others: Asking Lidarr over two square '
        'plates, with the rows that came already there', (tester) async {
      final gate = Completer<void>();
      final (:harness, lidarr: _, router: _, opened: _) = await _open(
        tester,
        lidarr: _Lidarr(answer: _spring(), gate: gate),
        settle: false,
      );

      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Asking Lidarr'), findsOneWidget);
      expect(find.text('Sprite Fright'), findsOneWidget);
      expect(
        _top(tester, 'Music'),
        greaterThan(_top(tester, 'On your server')),
      );

      expect(find.byType(SearchRowsPending), findsWidgets);
      gate.complete();
      await harness.settle(tester);

      expect(find.text('Asking Lidarr'), findsNothing);
      expect(find.text('Spring Reprise'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('its catalog not answering: the section goes and a line at '
        'the head says so, with Retry, which asks again', (tester) async {
      final lidarr = _Lidarr(
        error: const LidarrCatalogUnavailable('LidarrAPI is unavailable'),
      );
      final (:harness, router: _, opened: _, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );

      expect(
        find.text(
          'Lidarr answered, but its music catalog did not, so music is '
          'missing.',
        ),
        findsOneWidget,
      );
      expect(find.text('Music'), findsNothing);
      // The others still answer, below the line.
      expect(find.text('Sprite Fright'), findsOneWidget);
      expect(
        _top(
          tester,
          'Lidarr answered, but its music catalog did not, so music is missing.',
        ),
        lessThan(_top(tester, 'Sprite Fright')),
      );

      lidarr
        ..error = null
        ..answer = _spring();
      await tester.tap(find.bySemanticsLabel('Retry Lidarr'));
      await harness.settle(tester);

      expect(lidarr.searched, hasLength(2));
      expect(find.textContaining('music catalog did not'), findsNothing);
      expect(find.text('Music'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('Lidarr not answering at all: the quiet line every source '
        'has, with Retry', (tester) async {
      final lidarr = _Lidarr(
        error: DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/search'),
          reason: 'no route',
        ),
      );
      final (:harness, router: _, opened: _, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );

      expect(find.textContaining('No Lidarr results'), findsOneWidget);
      expect(find.text('Music'), findsNothing);
      expect(find.text('Sprite Fright'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry Lidarr'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a library that cannot be read says so rather than guess '
        'which rows are held', (tester) async {
      final lidarr = _Lidarr(
        answer: _spring(),
        libraryError: DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/album'),
          reason: 'no route',
        ),
      );
      final (:harness, router: _, opened: _, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );

      expect(find.textContaining('No Lidarr results'), findsOneWidget);
      expect(find.text('Music'), findsNothing);

      lidarr.libraryError = null;
      await tester.tap(find.bySemanticsLabel('Retry Lidarr'));
      await harness.settle(tester);

      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a word nothing found, music included, says so, and names '
        'music with the rest', (tester) async {
      final (:harness, router: _, opened: _, lidarr: _) = await _open(
        tester,
        // The profile's Radarr and Sonarr answer every word with their whole
        // library: the ones that can answer nothing are left out.
        profile: _seerrAndLidarr,
        lidarr: _Lidarr(),
        query: 'qwxz',
      );

      expect(find.text('Nothing called “qwxz”'), findsOneWidget);
      expect(
        find.textContaining('No movie, series, person or music by that name.'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('only music found: the section stands alone, with the people '
        'saying no one', (tester) async {
      final (:harness, router: _, opened: _, lidarr: _) = await _open(
        tester,
        profile: _seerrAndLidarr,
        lidarr: _Lidarr(answer: _elbow()),
        query: 'elbow',
      );

      expect(find.text('Nothing called “elbow”'), findsNothing);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Elbow'), findsOneWidget);
      expect(find.text('No one called “elbow”'), findsOneWidget);

      await harness.unmount(tester);
    });
  });
}
