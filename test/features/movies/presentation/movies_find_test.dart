/// The Movies wall's search: its library first, Radarr on request, and what a
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
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

RadarrMovie _movie(
  int id,
  String title, {
  int year = 1924,
  int runtime = 0,
  int tmdbId = 0,
  bool hasFile = false,
  String sortTitle = '',
}) => RadarrMovie.fromJson({
  'id': id,
  'title': title,
  'sortTitle': sortTitle.isEmpty ? title.toLowerCase() : sortTitle,
  'year': year,
  'runtime': runtime,
  'tmdbId': tmdbId,
  'hasFile': hasFile,
  'monitored': true,
  'isAvailable': true,
  'status': 'released',
});

/// A Radarr with a library to find in and a script for its lookup.
class _Radarr extends FakeRadarrService {
  _Radarr({
    this.library = const [],
    this.lookup = const [],
    this.lookupError,
    this.gate,
  });

  List<RadarrMovie> library;
  final List<RadarrMovie> lookup;
  var reads = 0;
  final Object? lookupError;
  final Completer<void>? gate;
  final asked = <String>[];

  @override
  Future<List<RadarrMovie>> getMovies() async {
    reads++;
    return library;
  }

  @override
  Future<List<RadarrMovie>> lookupMovies(
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
  _movie(1, 'Sherlock Jr.', runtime: 45, tmdbId: 1, hasFile: true),
  _movie(2, 'The Sheik', year: 1921, runtime: 80, tmdbId: 2),
  _movie(3, 'Nosferatu', year: 1922, runtime: 94, tmdbId: 3, hasFile: true),
  _movie(4, 'Amélie', year: 2001, runtime: 122, tmdbId: 4, hasFile: true),
  _movie(5, 'No Id Film', year: 1930, tmdbId: 0, hasFile: true),
];

Future<({GoRouter router, _Radarr radarr})> _open(
  WidgetTester tester, {
  _Radarr? radarr,
  double textScale = 1,
}) async {
  final fake = radarr ?? _Radarr(library: _library);
  tester.view
    ..physicalSize = const Size(390, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MoviesScreen()),
      GoRoute(
        path: '${ServiceRoutes.radarrMovieBase}/:id',
        builder: (context, state) =>
            Scaffold(body: Text('library movie ${state.pathParameters['id']}')),
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
        ...await settingsScopeOverrides(configured: const [ServiceKey.radarr]),
        radarrServiceProvider.overrideWithValue(fake),
        radarrQueueSnapshotProvider.overrideWith(
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
  return (router: router, radarr: fake);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

Future<void> _askRadarr(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MediaFindScopeControl),
      matching: find.text('Radarr'),
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
    testWidgets('finds movies by the start of a word, with the count as its '
        'noun', (tester) async {
      await _open(tester);

      await _type(tester, 'sh');

      expect(find.text('2\u00A0movies'), findsOneWidget);
      expect(find.text('Sherlock Jr.'), findsOneWidget);
      expect(find.text('The Sheik'), findsOneWidget);
      expect(find.text('Nosferatu'), findsNothing);
      // The wall is behind the results, not beside them.
      expect(find.byType(MediaGrid<RadarrMovie>), findsNothing);
    });

    testWidgets('one movie is `1 movie`', (tester) async {
      await _open(tester);

      await _type(tester, 'nosf');

      expect(find.text('1\u00A0movie'), findsOneWidget);
    });

    testWidgets('is blind to case and accents, both ways', (tester) async {
      await _open(tester);

      await _type(tester, 'AMELIE');
      expect(find.text('Amélie'), findsOneWidget);

      await _type(tester, 'amél');
      expect(find.text('Amélie'), findsOneWidget);
    });

    testWidgets('finds by the sort title as well as the title', (tester) async {
      await _open(
        tester,
        radarr: _Radarr(
          library: [
            _movie(
              9,
              '20,000 Leagues Under the Sea',
              sortTitle: '20000 leagues under sea',
              tmdbId: 9,
            ),
          ],
        ),
      );

      await _type(tester, '20000');

      expect(find.text('20,000 Leagues Under the Sea'), findsOneWidget);
    });

    testWidgets('a row says the year and the runtime when Radarr knows it', (
      tester,
    ) async {
      await _open(tester);

      await _type(tester, 'sh');

      expect(
        find.descendant(
          of: _row('Sherlock Jr.'),
          matching: find.text('1924\u00A0· 45\u00A0min'),
        ),
        findsOneWidget,
      );
      await _type(tester, 'no id');
      expect(
        find.descendant(of: _row('No Id Film'), matching: find.text('1930')),
        findsOneWidget,
      );
    });

    testWidgets('a row says where the movie stands in the word the wall '
        'says it in', (tester) async {
      await _open(tester);

      await _type(tester, 'sh');

      expect(
        find.descendant(
          of: _row('Sherlock Jr.'),
          matching: find.text('Available'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row('The Sheik'), matching: find.text('Missing')),
        findsOneWidget,
      );
    });

    testWidgets('a movie still in the queue that has not answered has no '
        'word yet, as on the wall', (tester) async {
      final radarr = _Radarr(library: _library);
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr],
            ),
            radarrServiceProvider.overrideWithValue(radarr),
            radarrQueueSnapshotProvider.overrideWith(
              (ref) => Completer<ArrQueueSnapshot>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const MoviesScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'sheik');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('The Sheik'), findsOneWidget);
      expect(find.text('Missing'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
    });

    testWidgets('each row is one spoken sentence', (tester) async {
      await _open(tester);
      await _type(tester, 'sh');
      final handle = tester.ensureSemantics();

      final node = _node(tester, 'Sherlock Jr.');
      expect(
        '${node.label}, ${node.value}'.replaceAll('\u00A0', ' '),
        'Sherlock Jr., 1924 · 45 min, Available',
      );

      handle.dispose();
    });

    testWidgets('a tap opens the movie as the wall\'s tile does: its title '
        'page on this Radarr', (tester) async {
      await _open(tester);
      await _type(tester, 'sherlock');

      await tester.tap(find.text('Sherlock Jr.'));
      await tester.pumpAndSettle();

      expect(find.textContaining('title movie 1'), findsOneWidget);
      expect(find.textContaining('i=radarr'), findsOneWidget);
    });

    testWidgets('a movie with no TMDB id opens the copy Radarr holds', (
      tester,
    ) async {
      await _open(tester);
      await _type(tester, 'no id');

      await tester.tap(find.text('No Id Film'));
      await tester.pumpAndSettle();

      expect(find.text('library movie 5'), findsOneWidget);
    });

    testWidgets('nothing found says so once, and offers Radarr', (
      tester,
    ) async {
      final (:router, :radarr) = await _open(tester);

      await _type(tester, 'zzz');

      expect(find.text('Nothing in your library called “zzz”'), findsOneWidget);
      expect(find.text('Radarr can look further.'), findsOneWidget);
      expect(find.text('Search Radarr for “zzz”'), findsOneWidget);

      await tester.tap(find.text('Search Radarr for “zzz”'));
      await tester.pumpAndSettle();

      expect(radarr.asked, ['zzz']);
    });

    testWidgets('a few thousand movies build only what is on screen', (
      tester,
    ) async {
      await _open(
        tester,
        radarr: _Radarr(
          library: [
            for (var i = 0; i < 3000; i++)
              _movie(100 + i, 'The Film $i', tmdbId: 100 + i),
          ],
        ),
      );

      await _type(tester, 'the');

      expect(find.text('3000\u00A0movies'), findsOneWidget);
      expect(find.byType(SearchRow).evaluate().length, lessThan(30));
    });
  });

  group('Radarr', () {
    final lookup = [
      _movie(1, 'Sherlock Jr.', runtime: 45, tmdbId: 1, hasFile: true),
      _movie(0, 'Sherlock Holmes', year: 2009, runtime: 128, tmdbId: 77),
    ];

    testWidgets('rows are the ones Discover draws: held says where, not held '
        'carries the plus', (tester) async {
      final (:router, :radarr) = await _open(
        tester,
        radarr: _Radarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askRadarr(tester);

      expect(radarr.asked, ['sherlock']);
      expect(find.text('2\u00A0movies'), findsOneWidget);
      expect(find.byType(MediaGrid<RadarrMovie>), findsNothing);
      // Held, it says what the wall says (Available), not Discover's word.
      expect(
        find.descendant(
          of: _row('Sherlock Jr.'),
          matching: find.text('Available'),
        ),
        findsOneWidget,
      );
      expect(find.text('In Radarr'), findsNothing);
      expect(_disc('Sherlock Jr.'), findsNothing);
      expect(_disc('Sherlock Holmes'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('Sherlock Holmes'),
          matching: find.text('2009\u00A0· 2\u00A0h 8\u00A0min'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a title the library holds reads the word the wall gives it, '
        'in both scopes: one title, one word', (tester) async {
      final radarr = _Radarr(
        library: _library,
        lookup: [_movie(0, 'The Sheik', year: 1921, runtime: 80, tmdbId: 2)],
      );
      await _open(tester, radarr: radarr);
      await _type(tester, 'sheik');
      final inLibrary = find.descendant(
        of: _row('The Sheik'),
        matching: find.text('Missing'),
      );
      expect(inLibrary, findsOneWidget);

      await _askRadarr(tester);

      // The same title in the service's own scope: the wall's word, hollow,
      // and neither Discover's `In Radarr` nor a plus.
      expect(
        find.descendant(of: _row('The Sheik'), matching: find.text('Missing')),
        findsOneWidget,
      );
      expect(find.text('In Radarr'), findsNothing);
      expect(_disc('The Sheik'), findsNothing);
    });

    testWidgets('a held title has no word in the service scope while the '
        'queue is unread, as on the wall', (tester) async {
      final radarr = _Radarr(
        library: _library,
        lookup: [_movie(0, 'The Sheik', year: 1921, runtime: 80, tmdbId: 2)],
      );
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr],
            ),
            radarrServiceProvider.overrideWithValue(radarr),
            radarrQueueSnapshotProvider.overrideWith(
              (ref) => Completer<ArrQueueSnapshot>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const MoviesScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'sheik');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.descendant(
          of: find.byType(MediaFindScopeControl),
          matching: find.text('Radarr'),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('The Sheik'), findsOneWidget);
      expect(find.text('Missing'), findsNothing);
      expect(find.text('In Radarr'), findsNothing);
      expect(_disc('The Sheik'), findsNothing);
    });

    testWidgets('after an add the wall knows: its library and the lookup are '
        'read again, the row turns held in place and the title is on the '
        'wall', (tester) async {
      final radarr = _Radarr(
        library: _library,
        lookup: [
          _movie(0, 'Sherlock Holmes', year: 2009, runtime: 128, tmdbId: 77),
        ],
      );
      await _open(tester, radarr: radarr);
      await _type(tester, 'sherlock');
      await _askRadarr(tester);
      expect(_disc('Sherlock Holmes'), findsOneWidget);
      final reads = radarr.reads;
      final asked = radarr.asked.length;

      // What the add sheet's flow leaves behind: Radarr holds it now, and the
      // row tells the page.
      radarr.library = [
        ..._library,
        _movie(50, 'Sherlock Holmes', year: 2009, runtime: 128, tmdbId: 77),
      ];
      tester
          .widget<CatalogTitleRow>(find.byType(CatalogTitleRow).first)
          .onChanged();
      await tester.pumpAndSettle();

      expect(radarr.reads, greaterThan(reads));
      expect(radarr.asked.length, greaterThan(asked));
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
      final radarr = _Radarr(
        library: _library,
        lookup: [_movie(0, 'Ghost', tmdbId: 0)],
      );
      await _open(tester, radarr: radarr);
      await _type(tester, 'ghost');
      await _askRadarr(tester);

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
        radarr: _Radarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askRadarr(tester);

      await tester.tap(_disc('Sherlock Holmes'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaAddSheet), findsOneWidget);
    });

    testWidgets('a tap keeps the lookup tile\'s behaviour: the title\'s page '
        'on this Radarr', (tester) async {
      await _open(
        tester,
        radarr: _Radarr(library: _library, lookup: lookup),
      );
      await _type(tester, 'sherlock');
      await _askRadarr(tester);

      await tester.tap(find.text('Sherlock Holmes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('title movie 77'), findsOneWidget);
      expect(find.textContaining('i=radarr'), findsOneWidget);
    });

    testWidgets('while Radarr is asked, a heading over four plates', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _open(
        tester,
        radarr: _Radarr(library: _library, lookup: lookup, gate: gate),
      );
      await _type(tester, 'sherlock');
      await tester.tap(find.text('Radarr'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Asking Radarr'), findsOneWidget);
      expect(find.byType(ShimmerPlaceholder), findsNWidgets(12));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Asking Radarr'), findsNothing);
    });

    testWidgets('nothing found says so, with the glyph', (tester) async {
      await _open(tester, radarr: _Radarr(library: _library));
      await _type(tester, 'smells');
      await _askRadarr(tester);

      expect(find.text('Radarr found nothing called “smells”'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsWidgets);
    });

    testWidgets('a Radarr that did not answer is the app\'s own failure '
        'state, with Retry', (tester) async {
      await _open(
        tester,
        radarr: _Radarr(
          library: _library,
          lookupError: DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/movie/lookup'),
            reason: 'Connection refused',
          ),
        ),
      );
      await _type(tester, 'sherlock');
      await _askRadarr(tester);

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Radarr did not answer'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('the field invites: its hint names what is found', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Movies'), findsWidgets);
    final field = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(field.hintText, 'Movies');
  });

  testWidgets('text at 200% fits without overflow in both scopes', (
    tester,
  ) async {
    await _open(
      tester,
      radarr: _Radarr(
        library: _library,
        lookup: [_movie(0, 'Sherlock Holmes', tmdbId: 77, runtime: 128)],
      ),
      textScale: 2,
    );

    await _type(tester, 'sh');
    expect(tester.takeException(), isNull);
    await _askRadarr(tester);
    expect(tester.takeException(), isNull);
  });
}
