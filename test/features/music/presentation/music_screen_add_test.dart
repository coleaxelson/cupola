/// A search result Lidarr does not hold opens the add sheet; one it holds
/// opens its page. Never the page of an artist with no id.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Music wall on the profiles' Lidarr, with the artist's page standing in
/// as a line that says which artist it was opened for and how.
Future<({ProfileHarness harness, GoRouter router})> _open(
  WidgetTester tester,
) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = const Size(390, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MusicScreen()),
      GoRoute(
        path: '${ServiceRoutes.lidarrArtistBase}/:id',
        builder: (context, state) => Scaffold(
          body: Text(
            'artist page ${state.pathParameters['id']} '
            'added=${state.uri.queryParameters['added']}',
          ),
        ),
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
      ),
    ),
  );
  await harness.settle(tester);
  return (harness: harness, router: router);
}

/// Searches the wall for [term], as typing it in the field does, and waits for
/// Lidarr's lookup.
Future<void> _search(
  WidgetTester tester,
  ProfileHarness harness,
  String term,
) async {
  ProviderScope.containerOf(
    tester.element(find.byType(MusicScreen)),
  ).read(musicSearchQueryProvider.notifier).state = term;
  // The lookup is parsed in an isolate, which answers on the real event loop.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
  await harness.settle(tester);
}

void main() {
  testWidgets('a result Lidarr does not hold opens the add sheet, not a '
      'page', (tester) async {
    final (:harness, :router) = await _open(tester);
    await _search(tester, harness, 'elbow');

    await tester.tap(find.byType(ContentCard).first);
    await harness.settle(tester);

    expect(find.byType(LidarrAddArtistSheet), findsOneWidget);
    expect(find.textContaining('artist page'), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/',
      reason: 'nothing was pushed',
    );

    await harness.unmount(tester);
  });

  testWidgets('a result Lidarr holds opens its page, as it always did', (
    tester,
  ) async {
    final (:harness, :router) = await _open(tester);
    await _search(tester, harness, 'jan');

    await tester.tap(find.byType(ContentCard).first);
    await harness.settle(tester);

    expect(find.byType(LidarrAddArtistSheet), findsNothing);
    expect(find.text('artist page 1 added=null'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('adding says so, and opens the new artist waiting for its '
      'albums', (tester) async {
    final (:harness, :router) = await _open(tester);
    await _search(tester, harness, 'elbow');
    await tester.tap(find.byType(ContentCard).first);
    await harness.settle(tester);

    await tester.tap(find.text('Add and search'));
    await harness.settle(tester);

    // The profiles' Lidarr answers an add with the record it was sent, under
    // id 100.
    expect(find.text('artist page 100 added=1'), findsOneWidget);
    expect(find.text('Elbow added to Lidarr'), findsOneWidget);
    expect(find.byType(LidarrAddArtistSheet), findsNothing);

    await harness.unmount(tester);
  });
}
