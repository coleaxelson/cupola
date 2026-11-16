/// The Series wall's search: its library first, Sonarr on request, and what a
/// row says and does in each.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

SonarrSeries _series(
  int id,
  String title, {
  int year = 2015,
  int seasons = 0,
  int tmdbId = 0,
  bool complete = false,
  String sortTitle = '',
}) => SonarrSeries.fromJson({
  'id': id,
  'title': title,
  'sortTitle': sortTitle.isEmpty ? title.toLowerCase() : sortTitle,
  'year': year,
  'tmdbId': tmdbId,
  'monitored': true,
  'status': 'ended',
  'seasons': [
    {'seasonNumber': 0, 'monitored': false},
    for (var n = 1; n <= seasons; n++) {'seasonNumber': n, 'monitored': true},
  ],
  'statistics': {'episodeFileCount': complete ? 8 : 0, 'episodeCount': 8},
});

/// A Sonarr with a library to find in and a script for its lookup.
class _Sonarr extends FakeSonarrService {
  _Sonarr({
    this.library = const [],
    this.lookup = const [],
    this.lookupError,
    this.gate,
  });

  List<SonarrSeries> library;
  final List<SonarrSeries> lookup;
  var reads = 0;
  final Object? lookupError;
  final Completer<void>? gate;
  final asked = <String>[];

  @override
  Future<List<SonarrSeries>> getSeries() async {
    reads++;
    return library;
  }

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    asked.add(term);
    await gate?.future;
    if (lookupError != null) throw lookupError!;
    return lookup;
  }
}

final _library = [
  _series(1, 'Sherlock', seasons: 4, tmdbId: 1, complete: true),
  _series(2, 'Shetland', year: 2013, seasons: 1, tmdbId: 2),
  _series(3, 'Hero', year: 2018, seasons: 3, tmdbId: 3, complete: true),
  _series(4, 'Élite', year: 2018, seasons: 2, tmdbId: 4, complete: true),
  _series(5, 'No Id Show', year: 2000, tmdbId: 0, complete: true),
];

Future<({GoRouter router, _Sonarr sonarr})> _open(
  WidgetTester tester, {
  _Sonarr? sonarr,
  double textScale = 1,
}) async {
  final fake = sonarr ?? _Sonarr(library: _library);
  tester.view
    ..physicalSize = const Size(390, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SeriesScreen()),
      GoRoute(
        path: '${ServiceRoutes.sonarrSeriesBase}/:id',
        builder: (context, state) => Scaffold(
          body: Text('library series ${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/media/:kind/:id',
        builder: (context, state) => Scaffold(
          body: Text(
            'title ${state.pathParameters['kind']} '
            '${state.pathParameters['id']} i=${state.uri.queryParameters['i']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.sonarr]),
        sonarrServiceProvider.overrideWithValue(fake),
        sonarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.empty,
        ),
      ],
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
  await tester.pumpAndSettle();
  return (router: router, sonarr: fake);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

Future<void> _askSonarr(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MediaFindScopeControl),
      matching: find.text('Sonarr'),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SearchRow));

Finder _disc(String title) =>
    find.descendant(of: _row(title), matching: find.byIcon(Icons.add_rounded));

SemanticsNode _node(WidgetTester tester, String title) => tester.getSemantics(
  find
      .descendant(
        of: _row(title),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == title,
        ),
      )
      .first,
);

void main() {
  group('your library', () {
    testWidgets('finds series by the start of a word, with the count as its '
        'noun', (tester) async {
      await _open(tester);

      await _type(tester, 'she');

      expect(find.text('2\u00A0series'), findsOneWidget);
      expect(find.text('Sherlock'), findsOneWidget);
      expect(find.text('Shetland'), findsOneWidget);
      expect(find.text('Hero'), findsNothing);
      // The wall is behind the results, not beside them.
      expect(find.byType(MediaGrid<SonarrSeries>), findsNothing);
    });

    testWidgets('one movie is `1 series`', (tester) async {
      await _open(tester);

      await _type(tester, 'her');

      expect(find.text('1\u00A0series'), findsOneWidget);
    });

    testWidgets('is blind to case and accents, both ways', (tester) async {
      await _open(tester);

      await _type(tester, 'ELITE');
      expect(find.text('Élite'), findsOneWidget);

      await _type(tester, 'él');
      expect(find.text('Élite'), findsOneWidget);
    });

    testWidgets('finds by the sort title as well as the title', (tester) async {
      await _open(
        tester,
        sonarr: _Sonarr(
          library: [
            _series(
              9,
              'Twenty-One: The Show',
              sortTitle: '21 the show',
              tmdbId: 9,
            ),
          ],
        ),
      );

      await _type(tester, '21');

      expect(find.text('Twenty-One: The Show'), findsOneWidget);
    });

    testWidgets('a row says the year and the seasons when Sonarr lists them', (
      tester,
    ) async {
      await _open(tester);

      await _type(tester, 'sh');

      expect(
        find.descendant(
          of: _row('Sherlock'),
          matching: find.text('2015\u00A0· 4\u00A0seasons'),
        ),
        findsOneWidget,
      );
      await _type(tester, 'no id');
      expect(
        find.descendant(of: _row('No Id Show'), matching: find.text('2000')),
        findsOneWidget,
      );
    });

    testWidgets('a row says where the series stands in the word the wall '
        'says it in', (tester) async {
      await _open(tester);

      await _type(tester, 'sh');

      expect(
        find.descendant(of: _row('Sherlock'), matching: find.text('Available')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row('Shetland'), matching: find.text('Missing')),
        findsOneWidget,
      );
    });

    testWidgets('a series still in the queue that has not answered has no '
        'word yet, as on the wall', (tester) async {
      final sonarr = _Sonarr(library: _library);
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.sonarr],
            ),
            sonarrServiceProvider.overrideWithValue(sonarr),
            sonarrQueueSnapshotProvider.overrideWith(
              (ref) => Completer<ArrQueueSnapshot>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const SeriesScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'shetl');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Shetland'), findsOneWidget);
      expect(find.text('Missing'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
    });

    testWidgets('each row is one spoken sentence', (tester) async {
      await _open(tester);
      await _type(tester, 'sh');
      final handle = tester.ensureSemantics();

      final node = _node(tester, 'Sherlock');
      expect(
        '${node.label}, ${node.value}'.replaceAll('\u00A0', ' '),
        'Sherlock, 2015 · 4 seasons, Available',
      );

      handle.dispose();
    });

    testWidgets('a tap opens the series as the wall\'s tile does: its title '
        'page on this Sonarr', (tester) async {
      await _open(tester);
      await _type(tester, 'sherlock');

      await tester.tap(find.text('Sherlock'));
      await tester.pumpAndSettle();

      expect(find.textContaining('title tv 1'), findsOneWidget);
      expect(find.textContaining('i=sonarr'), findsOneWidget);
    });

    testWidgets('a series with no TMDB id opens the copy Sonarr holds', (
      tester,
    ) async {
      await _open(tester);
      await _type(tester, 'no id');

      await tester.tap(find.text('No Id Show'));
      await tester.pumpAndSettle();

      expect(find.text('library series 5'), findsOneWidget);
    });

    testWidgets('nothing found says so once, and offers Sonarr', (
      tester,
    ) async {
      final (:router, :sonarr) = await _open(tester);

      await _type(tester, 'zzz');

      expect(find.text('Nothing in your library called “zzz”'), findsOneWidget);
      expect(find.text('Sonarr can look further.'), findsOneWidget);
      expect(find.text('Search Sonarr for “zzz”'), findsOneWidget);

      await tester.tap(find.text('Search Sonarr for “zzz”'));
      await tester.pumpAndSettle();

      expect(sonarr.asked, ['zzz']);
    });

    testWidgets('a few thousand series build only what is on screen', (
      tester,
    ) async {
      await _open(
        tester,
        sonarr: _Sonarr(
          library: [
            for (var i = 0; i < 3000; i++)
              _series(100 + i, 'The Show $i', tmdbId: 100 + i),
          ],
        ),
      );

      await _type(tester, 'the');

      expect(find.text('3000\u00A0series'), findsOneWidget);
      expect(find.byType(SearchRow).evaluate().length, lessThan(30));
    });
  });

  group('Sonarr', () {
    final lookup = [
      _series(1, 'Sherlock', seasons: 4, tmdbId: 1, complete: true),
      _series(0, 'Sherlock Holmes', year: 2009, seasons: 2, tmdbId: 77),
    ];

    testWidgets('rows are the ones Discover draws: held says where, not held '
        'carries the plus', (tester) async {
      final (:router, :sonarr) = await _open(
        tester,
        sonarr: _Sonarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askSonarr(tester);

      expect(sonarr.asked, ['sherlock']);
      expect(find.text('2\u00A0series'), findsOneWidget);
      expect(find.byType(MediaGrid<SonarrSeries>), findsNothing);
      // Held, it says what the wall says (Available), not Discover's word.
      expect(
        find.descendant(of: _row('Sherlock'), matching: find.text('Available')),
        findsOneWidget,
      );
      expect(find.text('In Sonarr'), findsNothing);
      expect(_disc('Sherlock'), findsNothing);
      expect(_disc('Sherlock Holmes'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('Sherlock Holmes'),
          matching: find.text('2009\u00A0· 2\u00A0seasons'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a title the library holds reads the word the wall gives it, '
        'in both scopes: one title, one word', (tester) async {
      final sonarr = _Sonarr(
        library: _library,
        lookup: [_series(0, 'Shetland', year: 2013, seasons: 1, tmdbId: 2)],
      );
      await _open(tester, sonarr: sonarr);
      await _type(tester, 'shetl');
      final inLibrary = find.descendant(
        of: _row('Shetland'),
        matching: find.text('Missing'),
      );
      expect(inLibrary, findsOneWidget);

      await _askSonarr(tester);

      // The same title in the service's own scope: the wall's word, hollow,
      // and neither Discover's `In Sonarr` nor a plus.
      expect(
        find.descendant(of: _row('Shetland'), matching: find.text('Missing')),
        findsOneWidget,
      );
      expect(find.text('In Sonarr'), findsNothing);
      expect(_disc('Shetland'), findsNothing);
    });

    testWidgets('a held title has no word in the service scope while the '
        'queue is unread, as on the wall', (tester) async {
      final sonarr = _Sonarr(
        library: _library,
        lookup: [_series(0, 'Shetland', year: 2013, seasons: 1, tmdbId: 2)],
      );
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.sonarr],
            ),
            sonarrServiceProvider.overrideWithValue(sonarr),
            sonarrQueueSnapshotProvider.overrideWith(
              (ref) => Completer<ArrQueueSnapshot>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const SeriesScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'shetl');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.descendant(
          of: find.byType(MediaFindScopeControl),
          matching: find.text('Sonarr'),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('Shetland'), findsOneWidget);
      expect(find.text('Missing'), findsNothing);
      expect(find.text('In Sonarr'), findsNothing);
      expect(_disc('Shetland'), findsNothing);
    });

    testWidgets('after an add the wall knows: its library and the lookup are '
        'read again, the row turns held in place and the title is on the '
        'wall', (tester) async {
      final sonarr = _Sonarr(
        library: _library,
        lookup: [
          _series(0, 'Sherlock Holmes', year: 2009, seasons: 2, tmdbId: 77),
        ],
      );
      await _open(tester, sonarr: sonarr);
      await _type(tester, 'sherlock');
      await _askSonarr(tester);
      expect(_disc('Sherlock Holmes'), findsOneWidget);
      final reads = sonarr.reads;
      final asked = sonarr.asked.length;

      // What the add sheet's flow leaves behind: Radarr holds it now, and the
      // row tells the page.
      sonarr.library = [
        ..._library,
        _series(50, 'Sherlock Holmes', year: 2009, seasons: 2, tmdbId: 77),
      ];
      tester
          .widget<CatalogTitleRow>(find.byType(CatalogTitleRow).first)
          .onChanged();
      await tester.pumpAndSettle();

      expect(sonarr.reads, greaterThan(reads));
      expect(sonarr.asked.length, greaterThan(asked));
      expect(_disc('Sherlock Holmes'), findsNothing);
      expect(
        find.descendant(
          of: _row('Sherlock Holmes'),
          matching: find.text('Missing'),
        ),
        findsOneWidget,
      );

      // Cleared, the wall draws the title it did not have.
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Sherlock Holmes'), findsOneWidget);
    });

    testWidgets('a row the library does not hold and that has no TMDB id is '
        'no button: it opens nothing', (tester) async {
      final sonarr = _Sonarr(
        library: _library,
        lookup: [_series(0, 'Ghost', tmdbId: 0)],
      );
      await _open(tester, sonarr: sonarr);
      await _type(tester, 'ghost');
      await _askSonarr(tester);

      final row = tester.widget<SearchRow>(find.byType(SearchRow));
      expect(row.onTap, isNull);
      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              find
                  .descendant(
                    of: _row('Ghost'),
                    matching: find.byWidgetPredicate(
                      (w) => w is Semantics && w.properties.label == 'Ghost',
                    ),
                  )
                  .first,
            )
            .flagsCollection
            .isButton,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('the plus opens the add sheet', (tester) async {
      await _open(
        tester,
        sonarr: _Sonarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askSonarr(tester);

      await tester.tap(_disc('Sherlock Holmes'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaAddSheet), findsOneWidget);
    });

    testWidgets('a tap keeps the lookup tile\'s behaviour: the title\'s page '
        'on this Sonarr', (tester) async {
      await _open(
        tester,
        sonarr: _Sonarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askSonarr(tester);

      await tester.tap(find.text('Sherlock Holmes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('title tv 77'), findsOneWidget);
      expect(find.textContaining('i=sonarr'), findsOneWidget);
    });

    testWidgets('while Sonarr is asked, a heading over four plates', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _open(
        tester,
        sonarr: _Sonarr(library: _library, lookup: lookup, gate: gate),
      );
      await _type(tester, 'sherlock');
      await tester.tap(find.text('Sonarr'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Asking Sonarr'), findsOneWidget);
      expect(find.byType(ShimmerPlaceholder), findsNWidgets(12));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Asking Sonarr'), findsNothing);
    });

    testWidgets('nothing found says so, with the glyph', (tester) async {
      await _open(tester, sonarr: _Sonarr(library: _library));
      await _type(tester, 'smells');
      await _askSonarr(tester);

      expect(find.text('Sonarr found nothing called “smells”'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsWidgets);
    });

    testWidgets('a Sonarr that did not answer is the app\'s own failure '
        'state, with Retry', (tester) async {
      await _open(
        tester,
        sonarr: _Sonarr(
          library: _library,
          lookupError: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/series/lookup'),
            reason: 'Connection refused',
          ),
        ),
      );
      await _type(tester, 'sherlock');
      await _askSonarr(tester);

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Sonarr did not answer'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('the field invites: its hint names what is found', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Series'), findsWidgets);
    final field = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(field.hintText, 'Series');
  });

  testWidgets('text at 200% fits without overflow in both scopes', (
    tester,
  ) async {
    await _open(
      tester,
      sonarr: _Sonarr(
        library: _library,
        lookup: [_series(0, 'Sherlock Holmes', tmdbId: 77, seasons: 2)],
      ),
      textScale: 2,
    );

    await _type(tester, 'sh');
    expect(tester.takeException(), isNull);
    await _askSonarr(tester);
    expect(tester.takeException(), isNull);
  });
}
