import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _query = StateProvider<String>((ref) => '');

const _titles = ['Anton Bruckner', 'Bill Evans', 'Brian Eno', 'Clara Schumann'];

/// The wanted counts by title: three of the four have something wanted.
final _counts = {
  for (final (title, count) in const [
    ('Bill Evans', 3),
    ('Brian Eno', 7),
    ('Clara Schumann', 1),
  ])
    title.hashCode: count,
};

/// Words that are the wall's own, so that the scaffold is shown to say none.
String _caption(int count, bool isFloor) =>
    '$count${isFloor ? '+' : ''} things wanted';
String _summary(int count, bool isFloor) =>
    '$count${isFloor ? '+' : ''} titles want something';

DioException get _unreachable => DioException.connectionError(
  requestOptions: RequestOptions(path: '/api/v1/wanted/missing'),
  reason: 'Connection refused',
);

Widget _wall({
  MediaBrowseWanted? wanted,
  List<String> titles = _titles,
  Set<int>? cutoff = const {},
}) {
  final library = FutureProvider<List<String>>((ref) async => titles);
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: MediaBrowseScaffold<String>(
        title: 'Music',
        searchHint: 'Search',
        activityRoute: '/activity',
        navigationSection: NavigationSection.stack,
        serviceName: 'Lidarr',
        service: ServiceKey.lidarr,
        heroTagPrefix: 'artist',
        libraryProvider: library,
        searchQueryProvider: _query,
        find: MediaFind.libraryOnly(
          libraryBody: (context, query) => Text('find:$query'),
        ),
        titleExtractor: (title) => title,
        subtitleExtractor: (_) => '6 albums',
        imagesExtractor: (_) => null,
        idExtractor: (title) => title.hashCode,
        // Every artist is "available": Missing would find none of them, which
        // is the case the Wanted chip exists for.
        statusExtractor: (_) =>
            const MediaStatusInfo(availability: MediaAvailability.available),
        settingsSelector: (_) => ('', '', const NoAccess()),
        onItemTap: (_, _, _) {},
        tileShape: MediaBrowseTileShape.circle,
        cutoffUnmetIds: cutoff,
        wanted: wanted,
      ),
    ),
  );
}

MediaBrowseWanted _wanted(
  AsyncValue<MediaBrowseWantedSet> answer, {
  VoidCallback? onRetry,
  MediaBrowseWantedWords? caption,
  MediaBrowseWantedWords? summary,
}) => MediaBrowseWanted(
  answer: answer,
  service: ServiceKey.lidarr,
  instanceId: 'lidarr-two',
  failureConsequence: 'the artists with a wanted album are not shown',
  onRetry: onRetry ?? () {},
  captionOf: caption ?? _caption,
  summaryOf: summary ?? _summary,
);

AsyncValue<MediaBrowseWantedSet> _answered({bool isFloor = false}) =>
    AsyncData(MediaBrowseWantedSet(countById: _counts, isFloor: isFloor));

Future<void> _pump(WidgetTester tester, Widget wall) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wall);
  await tester.pumpAndSettle();
}

Future<void> _selectWanted(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.text('Wanted'));
  // A wall that waits draws a spinner, which never settles.
  settle
      ? await tester.pumpAndSettle()
      : await tester.pump(const Duration(milliseconds: 300));
}

/// The chips, left to right.
List<String> _chips(WidgetTester tester) {
  final labels = [
    for (final label in const [
      'All',
      'Available',
      'Missing',
      'Wanted',
      'In queue',
      'Cutoff unmet',
      'Unmonitored',
    ])
      if (find.text(label).evaluate().isNotEmpty) label,
  ];
  labels.sort(
    (a, b) => tester
        .getTopLeft(find.text(a))
        .dx
        .compareTo(tester.getTopLeft(find.text(b)).dx),
  );
  return labels;
}

void main() {
  group('the chips', () {
    testWidgets('a wall with a wanted answer reads Wanted where Missing '
        'would stand', (tester) async {
      await _pump(tester, _wall(wanted: _wanted(_answered())));

      expect(_chips(tester), [
        'All',
        'Available',
        'Wanted',
        'In queue',
        'Cutoff unmet',
        'Unmonitored',
      ]);
      expect(find.text('Missing'), findsNothing);
    });

    testWidgets('every other wall keeps Missing and has no Wanted', (
      tester,
    ) async {
      await _pump(tester, _wall());

      expect(_chips(tester), [
        'All',
        'Available',
        'Missing',
        'In queue',
        'Cutoff unmet',
        'Unmonitored',
      ]);
      expect(find.text('Wanted'), findsNothing);
    });

    testWidgets('the chip is there while the answer is out, so the row does '
        'not shift when it lands', (tester) async {
      await _pump(tester, _wall(wanted: _wanted(const AsyncLoading())));
      final before = tester.getTopLeft(find.text('In queue')).dx;

      await tester.pumpWidget(_wall(wanted: _wanted(_answered())));
      await tester.pumpAndSettle();

      expect(find.text('Wanted'), findsOneWidget);
      expect(tester.getTopLeft(find.text('In queue')).dx, before);
    });
  });

  group('under the Wanted chip', () {
    testWidgets('only the artists with something wanted stay, each captioned '
        'with its count', (tester) async {
      await _pump(tester, _wall(wanted: _wanted(_answered())));
      expect(find.text('Anton Bruckner'), findsOneWidget);

      await _selectWanted(tester);

      expect(find.text('Anton Bruckner'), findsNothing);
      expect(find.text('Bill Evans'), findsOneWidget);
      expect(find.text('Brian Eno'), findsOneWidget);
      expect(find.text('Clara Schumann'), findsOneWidget);
      expect(find.text('3 things wanted'), findsOneWidget);
      expect(find.text('7 things wanted'), findsOneWidget);
      expect(find.text('1 things wanted'), findsOneWidget);
      // The wall's own caption is replaced, not added to.
      expect(find.text('6 albums'), findsNothing);
    });

    testWidgets('a line under the chips says how many titles are wanted', (
      tester,
    ) async {
      await _pump(tester, _wall(wanted: _wanted(_answered())));
      expect(find.text('3 titles want something'), findsNothing);

      await _selectWanted(tester);
      expect(find.text('3 titles want something'), findsOneWidget);
      // Under the chips, above the wall.
      expect(
        tester.getTopLeft(find.text('3 titles want something')).dy,
        greaterThan(tester.getBottomLeft(find.text('Wanted')).dy),
      );
      expect(
        tester.getTopLeft(find.text('3 titles want something')).dy,
        lessThan(tester.getTopLeft(find.text('Bill Evans')).dy),
      );

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('3 titles want something'), findsNothing);
      expect(find.text('6 albums'), findsWidgets);
    });

    testWidgets('counts the titles the wall holds, not the ids the service '
        'sent', (tester) async {
      // Two of the service's ids belong to artists this library no longer
      // holds.
      final answer = AsyncData(
        MediaBrowseWantedSet(countById: {..._counts, 1: 2, 2: 9}),
      );
      await _pump(tester, _wall(wanted: _wanted(answer)));

      await _selectWanted(tester);

      expect(find.text('3 titles want something'), findsOneWidget);
    });

    testWidgets('a floor is a floor in the caption and in the line', (
      tester,
    ) async {
      await _pump(tester, _wall(wanted: _wanted(_answered(isFloor: true))));

      await _selectWanted(tester);

      expect(find.text('7+ things wanted'), findsOneWidget);
      expect(find.text('3+ titles want something'), findsOneWidget);
    });

    testWidgets('the tile speaks the count, not the caption it replaced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _wall(wanted: _wanted(_answered())));
      await _selectWanted(tester);

      expect(
        tester.getSemantics(find.text('Brian Eno')),
        matchesSemantics(
          label: 'Brian Eno',
          value: '7 things wanted, Available',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('nothing wanted after a whole read says so, with the way '
        'back', (tester) async {
      await _pump(
        tester,
        _wall(
          wanted: _wanted(const AsyncData(MediaBrowseWantedSet(countById: {}))),
        ),
      );

      await _selectWanted(tester);

      expect(find.text('Nothing is wanted'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('Anton Bruckner'), findsOneWidget);
    });
  });

  group('while the answer is out or failed', () {
    testWidgets('selected before it lands, the wall waits instead of '
        'filtering to nothing', (tester) async {
      await _pump(tester, _wall(wanted: _wanted(const AsyncLoading())));

      await _selectWanted(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Nothing is wanted'), findsNothing);
      expect(find.text('Bill Evans'), findsNothing);

      // The answer lands: the same chip, now filtering.
      await tester.pumpWidget(_wall(wanted: _wanted(_answered())));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Bill Evans'), findsOneWidget);
      expect(find.text('Anton Bruckner'), findsNothing);
    });

    testWidgets('the rest of the wall is untouched while it is out', (
      tester,
    ) async {
      await _pump(tester, _wall(wanted: _wanted(const AsyncLoading())));

      expect(find.text('Anton Bruckner'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a failure says so in the house way, never that nothing is '
        'wanted', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        _wall(
          wanted: _wanted(
            AsyncError(_unreachable, StackTrace.empty),
            onRetry: () => retried++,
          ),
        ),
      );

      await _selectWanted(tester);

      final failure = tester.widget<InlineErrorRetry>(
        find.byType(InlineErrorRetry),
      );
      expect(failure.service, ServiceKey.lidarr);
      expect(failure.instanceId, 'lidarr-two');
      expect(failure.error, isA<DioException>());
      expect(
        failure.message,
        endsWith(', so the artists with a wanted album are not shown.'),
      );
      expect(find.text('Nothing is wanted'), findsNothing);
      expect(find.text('Bill Evans'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('a failure is only the Wanted chip\'s: every other chip still '
        'shows its wall', (tester) async {
      await _pump(
        tester,
        _wall(wanted: _wanted(AsyncError(_unreachable, StackTrace.empty))),
      );
      await _selectWanted(tester);
      expect(find.byType(InlineErrorRetry), findsOneWidget);

      await tester.tap(find.text('Available'));
      await tester.pumpAndSettle();

      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(find.text('Anton Bruckner'), findsOneWidget);
    });

    testWidgets('an answer kept through a refresh keeps filtering', (
      tester,
    ) async {
      // A refresh puts the next read in flight over the last answer.
      var inFlight = false;
      final provider = FutureProvider<MediaBrowseWantedSet>(
        (ref) => inFlight
            ? Completer<MediaBrowseWantedSet>().future
            : Future.value(MediaBrowseWantedSet(countById: _counts)),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(provider.future);
      inFlight = true;
      container.invalidate(provider);
      final refreshing = container.read(provider);
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.hasValue, isTrue);
      await _pump(tester, _wall(wanted: _wanted(refreshing)));

      await _selectWanted(tester);

      expect(find.text('Bill Evans'), findsOneWidget);
      expect(find.text('Anton Bruckner'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
