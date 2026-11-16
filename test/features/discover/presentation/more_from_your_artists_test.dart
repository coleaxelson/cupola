/// `More from your artists` in Discover: the shelf of albums the library's
/// artists made that nothing is looking for, where it stands and when it is
/// absent, the tile that opens the artist on the album, and See all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/more_from_your_artists_page.dart';
import 'package:cupola/features/discover/presentation/widgets/more_from_your_artists_shelf.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _heading = 'More from your artists';
const _lead = 'Albums Lidarr knows from artists you have, not monitored.';

Map<String, Object?> _artist(int id, String name) => {
  'id': id,
  'artistName': name,
  'foreignArtistId': 'mb-$id',
  'status': 'continuing',
  'monitored': true,
  'images': const <Object?>[],
  'statistics': {'albumCount': 3, 'trackCount': 15, 'trackFileCount': 10},
};

Map<String, Object?> _album(
  int id,
  String title, {
  int artistId = 1,
  String type = 'Album',
  String date = '2008-05-01T00:00:00Z',
  bool monitored = false,
  int files = 0,
}) => {
  'id': id,
  'artistId': artistId,
  'title': title,
  'foreignAlbumId': 'mb-album-$id',
  'albumType': type,
  'monitored': monitored,
  'releaseDate': date,
  'images': const <Object?>[],
  'statistics': {'trackFileCount': files, 'totalTrackCount': 5},
};

/// Jan Morgenstern's three, the board's: an EP and two singles, out and left
/// alone, with one on disk and one wanted among them that stay off the shelf.
List<Map<String, Object?>> _albums() => [
  _album(11, 'Big Buck Bunny Suite', type: 'EP'),
  _album(12, 'The Dragon', type: 'Single', date: '2010-03-01T00:00:00Z'),
  _album(13, 'Snow', type: 'Single', date: '2010-09-01T00:00:00Z'),
  _album(14, 'Sintel', files: 5, monitored: true),
  _album(15, 'Wanted one', monitored: true),
];

class _Opened {
  Uri? uri;
  Object? extra;
}

Future<({ProfileHarness harness, _Opened opened, GoRouter router})> _open(
  WidgetTester tester, {
  ConfigProfile? profile,
  List<Map<String, Object?>>? albums,
  List<Map<String, Object?>>? artists,
  NetworkReply Function()? albumsReply,
  String location = ServiceRoutes.discover,
  Size size = const Size(390, 2600),
  double textScale = 1,
  bool requester = false,
  Widget? alone,
}) async {
  final harness = await ProfileHarness.start(
    profile ?? Profiles.p1,
    overrides: [
      if (requester) audienceProvider.overrideWithValue(Audience.requester),
    ],
  );
  harness.network.followFakeTime(tester.binding);
  if (harness.profile.settings.isServiceConfigured(ServiceKey.lidarr)) {
    harness.network
      ..on(
        WorldIds.lidarr,
        'GET',
        '/api/v1/album',
        (r) => r.query.containsKey('artistId')
            ? null
            : albumsReply?.call() ?? NetworkReply.json(albums ?? _albums()),
      )
      ..on(
        WorldIds.lidarr,
        'GET',
        '/api/v1/artist',
        (r) => r.path == '/api/v1/artist'
            ? NetworkReply.json(
                artists ?? [_artist(1, 'Jan Morgenstern'), _artist(2, 'Birch')],
              )
            : null,
      );
  }
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: ServiceRoutes.discover,
        builder: (context, state) => const DiscoverPage(),
        routes: [
          GoRoute(
            path: 'artists',
            builder: (context, state) => const MoreFromYourArtistsPage(),
          ),
        ],
      ),
      GoRoute(
        path: '${ServiceRoutes.lidarrArtistBase}/:id',
        builder: (context, state) {
          opened
            ..uri = state.uri
            ..extra = state.extra;
          return Scaffold(body: Text('artist ${state.pathParameters['id']}'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  Widget scaled(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: alone != null
          ? MaterialApp(
              theme: AppTheme.darkTheme(),
              builder: scaled,
              home: Scaffold(body: ListView(children: [alone])),
            )
          : MaterialApp.router(
              theme: AppTheme.darkTheme(),
              routerConfig: router,
              builder: scaled,
            ),
    ),
  );
  await harness.settle(tester);
  return (harness: harness, opened: opened, router: router);
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('the shelf', () {
    testWidgets('with Seerr it comes after what Seerr says is missing, and '
        'before what is trending', (tester) async {
      final (:harness, opened: _, router: _) = await _open(tester);

      expect(find.text(_heading), findsOneWidget);
      expect(find.text(_lead), findsOneWidget);
      expect(find.byType(ArtistAlbumTile), findsNWidgets(3));
      expect(
        _top(tester, 'The best you’re missing'),
        lessThan(_top(tester, _heading)),
      );
      expect(
        _top(tester, _heading),
        lessThan(_top(tester, 'Trending this week')),
      );

      await harness.unmount(tester);
    });

    testWidgets('without Seerr it sits under the calendar, over the note '
        'about the catalog', (tester) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        profile: Profiles.p1.without(ServiceKey.seerr),
      );

      expect(find.text(_heading), findsOneWidget);
      expect(find.byType(ArtistAlbumTile), findsNWidgets(3));
      expect(
        _top(tester, _heading),
        lessThan(_top(tester, 'The catalog comes from Seerr')),
      );

      await harness.unmount(tester);
    });

    testWidgets('a tile says the album, who made it, what it is and when, and '
        'nothing else: no plus', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, opened: _, router: _) = await _open(tester);

      // Newest first: Snow and The Dragon (2010) lead the EP (2008).
      final tops = [
        for (final title in ['Snow', 'The Dragon', 'Big Buck Bunny Suite'])
          tester.getTopLeft(find.text(title)).dx,
      ];
      expect(tops, [...tops]..sort());
      expect(
        find.text('Jan Morgenstern\u00A0· EP\u00A0· 2008'),
        findsOneWidget,
      );
      expect(
        find.text('Jan Morgenstern\u00A0· Single\u00A0· 2010'),
        findsNWidgets(2),
      );
      expect(
        find.bySemanticsLabel(
          'Big Buck Bunny Suite, EP by Jan Morgenstern, 2008, unmonitored',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      // One album on disk, one wanted: neither is on it.
      for (final left in ['Sintel', 'Wanted one']) {
        expect(
          find.descendant(
            of: find.byType(ArtistAlbumTile),
            matching: find.text(left),
          ),
          findsNothing,
          reason: left,
        );
      }

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a tap opens the artist’s page, landed on the album', (
      tester,
    ) async {
      final (:harness, :opened, :router) = await _open(tester);

      await tester.tap(find.text('The Dragon'));
      await harness.settle(tester);

      expect(router.state.uri.path, '${ServiceRoutes.lidarrArtistBase}/1');
      expect(opened.uri?.queryParameters[ServiceRoutes.albumParam], '12');
      expect(opened.extra, isNotNull);

      await harness.unmount(tester);
    });

    testWidgets('its heading opens every album', (tester) async {
      final (:harness, opened: _, :router) = await _open(tester);

      await tester.tap(find.text(_heading));
      await harness.settle(tester);

      expect(router.state.uri.path, ServiceRoutes.discoverMoreFromYourArtists);
      expect(find.byType(MoreFromYourArtistsPage), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('at twice the reading size the tile grows and nothing '
        'overflows', (tester) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        textScale: 2,
        size: const Size(390, 800),
        alone: const MoreFromYourArtistsShelf(),
      );

      expect(find.text(_heading), findsOneWidget);
      expect(find.byType(ArtistAlbumTile), findsWidgets);
      expect(tester.takeException(), isNull);

      await harness.unmount(tester);
    });

    group('is not drawn', () {
      testWidgets('for the requester', (tester) async {
        final (:harness, opened: _, router: _) = await _open(
          tester,
          requester: true,
        );

        expect(find.text(_heading), findsNothing);
        expect(find.byType(ArtistAlbumTile), findsNothing);

        await harness.unmount(tester);
      });

      testWidgets('without a Lidarr', (tester) async {
        final (:harness, opened: _, router: _) = await _open(
          tester,
          profile: Profiles.p1.without(ServiceKey.lidarr),
        );

        expect(find.text(_heading), findsNothing);

        await harness.unmount(tester);
      });

      testWidgets('with nothing to show: every album monitored or on disk', (
        tester,
      ) async {
        final (:harness, opened: _, router: _) = await _open(
          tester,
          albums: [
            _album(14, 'Sintel', files: 5, monitored: true),
            _album(15, 'Wanted one', monitored: true),
          ],
        );

        expect(find.text(_heading), findsNothing);
        expect(find.text('The best you’re missing'), findsOneWidget);

        await harness.unmount(tester);
      });

      testWidgets('over a failed read, and says nothing of it', (tester) async {
        final (:harness, opened: _, router: _) = await _open(
          tester,
          albumsReply: () =>
              NetworkReply.json({'message': 'boom'}, status: 500),
        );

        expect(find.text(_heading), findsNothing);
        expect(find.textContaining('did not answer'), findsNothing);
        expect(find.textContaining('Lidarr'), findsNothing);
        expect(find.text('Trending this week'), findsOneWidget);

        await harness.unmount(tester);
      });
    });
  });

  group('See all', () {
    testWidgets('lists the albums under their artists, the artists A to Z', (
      tester,
    ) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        albums: [
          ..._albums(),
          _album(21, 'Leaves', artistId: 2, type: 'Single', date: '2015-01-01'),
        ],
        location: ServiceRoutes.discoverMoreFromYourArtists,
      );

      expect(find.text(_heading), findsOneWidget);
      expect(find.text(_lead), findsOneWidget);
      expect(find.byType(SearchRow), findsNWidgets(4));
      // Birch before Jan Morgenstern, each with how many albums.
      expect(_top(tester, 'Birch'), lessThan(_top(tester, 'Jan Morgenstern')));
      expect(_top(tester, 'Leaves'), lessThan(_top(tester, 'Jan Morgenstern')));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // Newest first inside an artist.
      expect(_top(tester, 'Snow'), lessThan(_top(tester, 'The Dragon')));
      expect(
        _top(tester, 'The Dragon'),
        lessThan(_top(tester, 'Big Buck Bunny Suite')),
      );
      // What each is, and the word the library keeps for it.
      expect(find.text('EP\u00A0· 2008\u00A0· 5\u00A0tracks'), findsOneWidget);
      expect(find.text('Unmonitored'), findsNWidgets(4));

      await harness.unmount(tester);
    });

    testWidgets('a row opens the artist’s page, landed on the album', (
      tester,
    ) async {
      final (:harness, :opened, :router) = await _open(
        tester,
        location: ServiceRoutes.discoverMoreFromYourArtists,
      );

      await tester.tap(find.text('Snow'));
      await harness.settle(tester);

      expect(router.state.uri.path, '${ServiceRoutes.lidarrArtistBase}/1');
      expect(opened.uri?.queryParameters[ServiceRoutes.albumParam], '13');

      await harness.unmount(tester);
    });

    testWidgets('is lazy: a library of hundreds builds the rows on screen', (
      tester,
    ) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        albums: [
          for (var i = 1; i <= 400; i++)
            _album(i, 'Record $i', date: '${1900 + i % 100}-01-01T00:00:00Z'),
        ],
        location: ServiceRoutes.discoverMoreFromYourArtists,
        size: const Size(390, 800),
      );

      final built = find.byType(SearchRow).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));

      await harness.unmount(tester);
    });

    testWidgets('with nothing left says so', (tester) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        albums: [_album(14, 'Sintel', files: 5, monitored: true)],
        location: ServiceRoutes.discoverMoreFromYourArtists,
      );

      expect(find.text('Nothing left to find'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a failed read names Lidarr and Retry reads again', (
      tester,
    ) async {
      var failing = true;
      final (:harness, opened: _, router: _) = await _open(
        tester,
        albumsReply: () => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : NetworkReply.json(_albums()),
        location: ServiceRoutes.discoverMoreFromYourArtists,
      );

      expect(find.textContaining('Lidarr'), findsWidgets);
      expect(find.byType(SearchRow), findsNothing);

      failing = false;
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);

      expect(find.byType(SearchRow), findsNWidgets(3));

      await harness.unmount(tester);
    });

    testWidgets('without a Lidarr it is the way to set one up', (tester) async {
      final (:harness, opened: _, router: _) = await _open(
        tester,
        profile: Profiles.p1.without(ServiceKey.lidarr),
        location: ServiceRoutes.discoverMoreFromYourArtists,
      );

      expect(find.byType(SearchRow), findsNothing);
      expect(find.textContaining('Lidarr'), findsWidgets);

      await harness.unmount(tester);
    });
  });
}
