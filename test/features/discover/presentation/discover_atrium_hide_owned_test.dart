/// "Hide what I have" on the atrium: the shelves that may list what the
/// server holds lose it with the switch on, the rest of the atrium does not
/// move, Trending is read once more at most, and nothing is drawn before the
/// choice (the person's, or Seerr's for one who never made it) is known.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/library_shelves_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// Seerr's media status 5: on the server.
const _held = {'status': 5};

/// Titles of a prefix share ids, so the same prefix is the same title.
int _base(String prefix) => prefix.codeUnitAt(0) * 1000;

/// Trending as Seerr pages it: [held] titles first, then [open] ones, named
/// `Held n` and `Open n`.
List<Map<String, dynamic>> _page(String prefix, {int held = 0, int open = 0}) =>
    [
      for (var i = 0; i < held; i++)
        {
          'id': _base(prefix) + i,
          'mediaType': 'movie',
          'title': '$prefix Held ${i + 1}',
          'mediaInfo': _held,
        },
      for (var i = 0; i < open; i++)
        {
          'id': _base(prefix) + 500 + i,
          'mediaType': 'movie',
          'title': '$prefix Open ${i + 1}',
        },
    ];

/// A Seerr that answers Trending page by page and counts every read.
class _Pages implements HttpClientAdapter {
  _Pages(this.pages, {this.failTrending = false});

  /// Whether Trending fails: Seerr is silent.
  final bool failTrending;

  /// Every path asked, in order.
  final List<String> paths = [];

  /// Page 1 and 2 of Trending, by number.
  final Map<int, List<Map<String, dynamic>>> pages;

  /// The Trending pages read, in order.
  final List<int> trendingReads = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    var body = <String, dynamic>{};
    if (failTrending && options.uri.path.endsWith('/discover/trending')) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (options.uri.path.endsWith('/discover/trending')) {
      final page = int.parse(options.uri.queryParameters['page'] ?? '1');
      trendingReads.add(page);
      body = {
        'page': page,
        'totalPages': 5,
        'totalResults': 100,
        'results': pages[page] ?? const [],
      };
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(body))),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

SeerrService _seerr(_Pages adapter) {
  final client = ApiClient(baseUrl: 'https://seerr.example.com', apiKey: 'k');
  client.dio.httpClientAdapter = adapter;
  return SeerrService(client);
}

const _best = [MediaPreview(id: 30, title: 'Metropolis', mediaType: 'movie')];

List<MediaPreview> _previews(String prefix, {int held = 0, int open = 0}) => [
  for (final json in _page(prefix, held: held, open: open))
    MediaPreview.fromJson(json),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _Pages adapter,
  bool? stored,
  bool serverHides = false,
  Future<SeerrServerFacts> Function()? facts,
  bool numberingFails = false,
  List<MediaPreview>? soon,
  WatchedShelfFixture? because,
}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({'catalog_hide_owned': ?stored});
  final prefs = await SharedPreferences.getInstance();
  final service = _seerr(adapter);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      seerrServiceProvider.overrideWithValue(service),
      seerrNumberingProvider.overrideWith(
        (ref) async => numberingFails ? throw StateError('no numbering') : null,
      ),
      seerrServerFactsProvider.overrideWith(
        (ref, id) =>
            facts?.call() ??
            Future.value(
              SeerrServerFacts.fromPublicSettings({
                'hideAvailable': serverHides,
              }),
            ),
      ),
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices([ServiceKey.seerr]),
      ),
      bestMissingProvider.overrideWith((ref) async => _best),
      comingSoonProvider.overrideWith(
        (ref) async => soon ?? _previews('Soon', held: 1, open: 1),
      ),
      catalogGenresProvider.overrideWith(
        (ref, kind) async => const [SeerrGenre(id: 16, name: 'Animation')],
      ),
      if (because != null) ...[
        hasWatchHistoryProvider.overrideWithValue(true),
        becauseYouWatchedProvider.overrideWith(
          (ref) async => (watched: because.watched, items: because.items),
        ),
      ],
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: ServiceRoutes.discover,
          routes: [
            GoRoute(
              path: ServiceRoutes.discover,
              builder: (context, state) =>
                  const Scaffold(body: DiscoverAtrium()),
            ),
          ],
        ),
      ),
    ),
  );
  return container;
}

typedef WatchedShelfFixture = ({String watched, List<MediaPreview> items});

void main() {
  group('with the switch on', () {
    testWidgets('Trending, Coming soon and Because you watched lose what the '
        'server holds; The best you\'re missing is as it was', (tester) async {
      final adapter = _Pages({1: _page('T', held: 2, open: 14)});
      await _pump(
        tester,
        adapter: adapter,
        stored: true,
        because: (watched: 'Sintel', items: _previews('Rec', held: 1, open: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hide what I have'), findsOneWidget);
      expect(find.text('Trending this week'), findsOneWidget);
      expect(find.text('T Open 1'), findsOneWidget);
      expect(find.text('T Held 1'), findsNothing);
      expect(find.text('Soon Open 1'), findsOneWidget);
      expect(find.text('Soon Held 1'), findsNothing);
      expect(find.text('Because you watched Sintel'), findsOneWidget);
      expect(find.text('Rec Open 1'), findsOneWidget);
      expect(find.text('Rec Held 1'), findsNothing);
      // Not a filtered shelf.
      expect(find.text('Metropolis'), findsOneWidget);
    });

    testWidgets('a shelf with nothing left is not drawn', (tester) async {
      final adapter = _Pages({1: _page('T', open: 14)});
      await _pump(
        tester,
        adapter: adapter,
        stored: true,
        soon: _previews('Soon', held: 3),
        because: (watched: 'Sintel', items: _previews('Rec', held: 2)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Because you watched Sintel'), findsNothing);
      expect(find.text('Trending this week'), findsOneWidget);
    });

    testWidgets('Trending is read once more when fewer than twelve are left, '
        'and never a third time', (tester) async {
      final adapter = _Pages({
        1: _page('T', held: 6, open: 6),
        2: _page('P2', held: 1, open: 8),
        3: _page('P3', open: 8),
      });
      await _pump(tester, adapter: adapter, stored: true);
      await tester.pumpAndSettle();

      expect(adapter.trendingReads, [1, 2]);
      expect(find.text('T Open 1'), findsOneWidget);
      expect(find.text('P2 Open 1'), findsOneWidget);
      expect(find.text('P2 Held 1'), findsNothing);
      expect(find.text('P3 Open 1'), findsNothing);
    });

    testWidgets('a refill never lists a title twice: Trending moves between '
        'the two reads', (tester) async {
      final adapter = _Pages({
        1: _page('T', held: 6, open: 6),
        // The same six open titles again, and two new ones.
        2: [..._page('T', open: 6), ..._page('N', open: 2)],
      });
      final container = await _pump(tester, adapter: adapter, stored: true);
      await tester.pumpAndSettle();

      final shelf = await container.read(atriumTrendingShelfProvider.future);
      final keys = [for (final item in shelf) '${item.mediaType}:${item.id}'];
      expect(keys.toSet(), hasLength(keys.length));
      expect(shelf, hasLength(8));
    });

    testWidgets('a numbering that did not come leaves the shelves up, '
        'filtered by the standard codes', (tester) async {
      final adapter = _Pages({1: _page('T', held: 2, open: 14)});
      await _pump(
        tester,
        adapter: adapter,
        stored: true,
        numberingFails: true,
        soon: _previews('Soon', held: 1, open: 1),
      );
      await tester.pumpAndSettle();

      expect(find.text('T Open 1'), findsOneWidget);
      expect(find.text('T Held 1'), findsNothing);
      expect(find.text('Soon Open 1'), findsOneWidget);
      expect(find.text('Soon Held 1'), findsNothing);
    });

    testWidgets('a first page that leaves enough is the only read', (
      tester,
    ) async {
      final adapter = _Pages({
        1: _page('T', held: 3, open: 14),
        2: _page('P2', open: 10),
      });
      await _pump(tester, adapter: adapter, stored: true);
      await tester.pumpAndSettle();

      expect(adapter.trendingReads, [1]);
    });

    testWidgets('the canary, the doors and the faces still read the whole '
        'first page', (tester) async {
      final adapter = _Pages({1: _page('T', held: 2, open: 3)});
      final container = await _pump(tester, adapter: adapter, stored: true);
      await tester.pumpAndSettle();

      final whole = await container.read(atriumTrendingProvider.future);
      expect(whole, hasLength(5));
      expect(whole.first.title, 'T Held 1');
      // The faces come from the first title of the whole page, held or not.
      await container.read(atriumFacesProvider.future);
      expect(adapter.paths, contains('/api/v1/movie/${_base('T')}'));
      final shelf = await container.read(atriumTrendingShelfProvider.future);
      expect(shelf.any((item) => item.title.contains('Held')), isFalse);
      // The same page, read once for all three.
      expect(adapter.trendingReads.where((page) => page == 1), hasLength(1));
    });
  });

  group('with the switch off', () {
    testWidgets('every shelf lists what the server holds, and Trending is '
        'read once', (tester) async {
      final adapter = _Pages({
        1: _page('T', held: 8, open: 2),
        2: _page('P2', open: 10),
      });
      await _pump(tester, adapter: adapter, stored: false);
      await tester.pumpAndSettle();

      expect(find.text('T Held 1'), findsOneWidget);
      expect(find.text('Soon Held 1'), findsOneWidget);
      expect(adapter.trendingReads, [1]);
    });
  });

  group('the value', () {
    testWidgets('one who never chose follows Seerr: its hideAvailable turns '
        'the switch on and the shelves filter', (tester) async {
      final adapter = _Pages({1: _page('T', held: 1, open: 14)});
      await _pump(tester, adapter: adapter, serverHides: true);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('T Held 1'), findsNothing);
      expect(find.text('T Open 1'), findsOneWidget);
    });

    testWidgets('and Seerr off leaves it off', (tester) async {
      final adapter = _Pages({1: _page('T', held: 1, open: 14)});
      await _pump(tester, adapter: adapter);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('T Held 1'), findsOneWidget);
    });

    testWidgets('their own choice wins over the server\'s, and turning the '
        'switch changes the shelves and is kept', (tester) async {
      final adapter = _Pages({1: _page('T', held: 1, open: 14)});
      final container = await _pump(
        tester,
        adapter: adapter,
        stored: false,
        serverHides: true,
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('T Held 1'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('T Held 1'), findsNothing);
      expect(
        container.read(sharedPreferencesProvider).getBool('catalog_hide_owned'),
        isTrue,
      );
    });
  });

  group('nothing is drawn before the value is known', () {
    testWidgets('the row keeps its place and its height, the switch and the '
        'shelves wait for Seerr\'s answer', (tester) async {
      final adapter = _Pages({1: _page('T', held: 1, open: 14)});
      final facts = Completer<SeerrServerFacts>();
      await _pump(tester, adapter: adapter, facts: () => facts.future);
      await tester.pump();
      await tester.pump();

      final waiting = tester.getSize(find.text('Hide what I have'));
      final row = tester.getRect(
        find
            .ancestor(
              of: find.text('Hide what I have'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(find.text('Hide what I have'), findsOneWidget);
      expect(find.byType(Switch).hitTestable(), findsNothing);
      expect(find.text('T Open 1'), findsNothing);
      expect(find.text('T Held 1'), findsNothing);
      expect(find.text('Soon Open 1'), findsNothing);

      facts.complete(
        SeerrServerFacts.fromPublicSettings({'hideAvailable': true}),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsOneWidget);
      expect(tester.getSize(find.text('Hide what I have')), waiting);
      expect(
        tester
            .getRect(
              find
                  .ancestor(
                    of: find.text('Hide what I have'),
                    matching: find.byType(ConstrainedBox),
                  )
                  .first,
            )
            .height,
        row.height,
      );
      expect(find.text('T Held 1'), findsNothing);
      expect(find.text('T Open 1'), findsOneWidget);
    });

    testWidgets('a Seerr that does not say leaves it off', (tester) async {
      final adapter = _Pages({1: _page('T', held: 1, open: 14)});
      await _pump(
        tester,
        adapter: adapter,
        facts: () => Future.error(StateError('no answer')),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('T Held 1'), findsOneWidget);
    });
  });

  testWidgets('a Seerr that is silent leaves no switch: the atrium says so '
      'once and has nothing under it', (tester) async {
    final adapter = _Pages(const {}, failTrending: true);
    await _pump(tester, adapter: adapter, stored: true);
    await tester.pumpAndSettle();

    expect(find.text('Hide what I have'), findsNothing);
    expect(find.byType(Switch).hitTestable(), findsNothing);
  });

  testWidgets('the row sits under the quiet links and above the shelves', (
    tester,
  ) async {
    final adapter = _Pages({1: _page('T', open: 14)});
    await _pump(tester, adapter: adapter, stored: false);
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Languages'), lessThan(top('Hide what I have')));
    expect(top('Hide what I have'), lessThan(top('Trending this week')));
  });
}
