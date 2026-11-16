/// The Music wall in selection mode over the profiles' Lidarr: the app's own
/// service, providers and wall, and a network that answers as Lidarr does.
/// What is asserted is what Lidarr was asked and what the wall then says.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _alder = 'Alder Quartet';
const _amber = 'Amber Static';

/// The artists of the shelf by name: ids 1001 on, in the order the demo lists
/// them, which Title A–Z leaves in place for these two.
const _alderId = 1001;
const _amberId = 1002;

Future<ProfileHarness> _open(WidgetTester tester) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  // The shelf of artists these tests select from is the living world's.
  harness.network.live();
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = const Size(390, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const MusicScreen(),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// What Lidarr was asked of the editor and the command queue, in order.
List<NetworkRequest> _writes(ProfileHarness harness) => [
  for (final request in harness.network.requestsTo(WorldIds.lidarr))
    if (request.method != 'GET') request,
];

Future<void> _select(WidgetTester tester, ProfileHarness harness) async {
  await tester.longPress(find.text(_alder));
  await harness.settle(tester);
  await tester.tap(find.text(_amber));
  await harness.settle(tester);
}

void main() {
  testWidgets('Search asks Lidarr for each artist and says how many', (
    tester,
  ) async {
    final harness = await _open(tester);
    await _select(tester, harness);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-selection-search')));
    await harness.settle(tester);

    final commands = _writes(harness);
    expect(commands, hasLength(2));
    expect(
      {for (final c in commands) (c.json as Map)['name']},
      {'ArtistSearch'},
    );
    expect(
      {for (final c in commands) (c.json as Map)['artistId']},
      {_alderId, _amberId},
    );
    expect(find.text('Lidarr is searching 2 artists'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('Monitor asks for the sheet, then Lidarr for one edit of the '
      'two artists, and reads the library again', (tester) async {
    final harness = await _open(tester);
    await _select(tester, harness);
    final readsBefore = harness.network
        .requestsTo(WorldIds.lidarr)
        .where((r) => r.method == 'GET' && r.path == '/api/v1/artist')
        .length;

    await tester.tap(find.byKey(const ValueKey('library-selection-monitor')));
    await harness.settle(tester);
    expect(find.text('Monitor 2 artists'), findsOneWidget);
    expect(find.text('Alder Quartet and Amber Static'), findsOneWidget);
    await tester.tap(find.text('Stop monitoring'));
    await harness.settle(tester);
    await tester.tap(find.text('Apply to 2 artists'));
    await harness.settle(tester);

    final edits = _writes(harness);
    expect(edits, hasLength(1));
    expect(edits.single.method, 'PUT');
    expect(edits.single.path, '/api/v1/artist/editor');
    // Both artists have `all` for the albums to come, so that is what the
    // sheet started on and sends: nothing is changed by saying it again.
    expect(edits.single.json, {
      'artistIds': [_alderId, _amberId],
      'monitored': false,
      'monitorNewItems': 'all',
    });
    expect(find.text('Updated 2 artists'), findsOneWidget);
    final readsAfter = harness.network
        .requestsTo(WorldIds.lidarr)
        .where((r) => r.method == 'GET' && r.path == '/api/v1/artist')
        .length;
    expect(readsAfter, greaterThan(readsBefore), reason: 'read again');

    await harness.unmount(tester);
  });

  testWidgets('one artist Lidarr refuses is named in a notice, and Try '
      'again asks for that artist alone', (tester) async {
    final harness = await _open(tester);
    // The editor refuses any request that holds Amber Static, as Lidarr does
    // for a folder it cannot reach, and names no artist when it does.
    var refusing = true;
    harness.network.on(WorldIds.lidarr, 'PUT', '/api/v1/artist/editor', (
      request,
    ) {
      final ids = (request.json as Map)['artistIds'] as List;
      if (!refusing || !ids.contains(_amberId)) return null;
      return NetworkReply(
        400,
        body: jsonEncode([
          {
            'propertyName': 'RootFolderPath',
            'errorMessage': 'The folder is not reachable',
          },
        ]),
      );
    });
    await _select(tester, harness);

    await tester.tap(find.byKey(const ValueKey('library-selection-monitor')));
    await harness.settle(tester);
    await tester.tap(find.text('Stop monitoring'));
    await harness.settle(tester);
    await tester.tap(find.text('Apply to 2 artists'));
    await harness.settle(tester);

    // The set, which Lidarr refused whole, then each artist alone.
    final first = _writes(harness);
    expect(first.map((r) => (r.json as Map)['artistIds']).toList(), [
      [_alderId, _amberId],
      [_alderId],
      [_amberId],
    ]);
    expect(find.text('1 of 2 artists updated'), findsOneWidget);
    expect(
      find.text('Lidarr refused $_amber: The folder is not reachable.'),
      findsOneWidget,
    );
    expect(find.text('2 selected'), findsNothing, reason: 'it has ended');

    refusing = false;
    await tester.tap(find.text('Try $_amber again'));
    await harness.settle(tester);

    final retry = _writes(harness).skip(first.length);
    expect(retry.map((r) => (r.json as Map)['artistIds']).toList(), [
      [_amberId],
    ]);
    expect((retry.single.json as Map)['monitored'], isFalse);
    expect(find.text('1 of 2 artists updated'), findsNothing);
    expect(find.text('Updated 2 artists'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Remove confirms first, and sends the choices with the two '
      'artists', (tester) async {
    final harness = await _open(tester);
    await _select(tester, harness);

    await tester.tap(find.byKey(const ValueKey('library-selection-remove')));
    await harness.settle(tester);
    expect(find.text('Remove 2 artists from Lidarr?'), findsOneWidget);
    expect(_writes(harness), isEmpty, reason: 'nothing before the answer');

    await tester.tap(find.text('Don’t add them again'));
    await tester.pump();
    await tester.tap(find.text('Remove 2 artists and don’t add them again'));
    await harness.settle(tester);

    final removed = _writes(harness);
    expect(removed, hasLength(1));
    expect(removed.single.method, 'DELETE');
    expect(removed.single.json, {
      'artistIds': [_alderId, _amberId],
      'deleteFiles': false,
      'addImportListExclusion': true,
    });
    expect(find.text('Removed 2 artists from Lidarr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a Lidarr that stops answering keeps the selection, with its '
      'failure line', (tester) async {
    final harness = await _open(tester);
    harness.network.on(
      WorldIds.lidarr,
      'PUT',
      '/api/v1/artist/editor',
      (request) => const NetworkReply(503, body: '{"message":"unavailable"}'),
    );
    await _select(tester, harness);

    await tester.tap(find.byKey(const ValueKey('library-selection-monitor')));
    await harness.settle(tester);
    await tester.tap(find.text('Apply to 2 artists'));
    await harness.settle(tester);

    expect(find.text('2 selected'), findsOneWidget);
    // A 5xx may have come after the write: Lidarr is not said to be untouched.
    expect(find.textContaining('nothing was changed'), findsNothing);
    expect(find.textContaining('may have changed'), findsOneWidget);
    // One request: nothing was asked artist by artist of a server that
    // answered with a fault.
    expect(_writes(harness), hasLength(1));

    await harness.unmount(tester);
  });
}
