/// An artist's page opened right after Lidarr took the artist: it says Lidarr
/// is still reading the albums, reads them again until they arrive, and gives
/// up the wait with the page's usual words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _reading =
    'Lidarr is reading Jan Morgenstern’s albums. '
    'They appear here in a moment.';

/// Opens the page on the profiles' Lidarr, whose albums answer [albums] for
/// the read number it is on (counted in [ArtistReads.count]).
Future<({ProfileHarness harness, ArtistReads reads})> _open(
  WidgetTester tester, {
  required List<Map<String, Object?>> Function(int read) albums,
  bool justAdded = true,
}) async {
  final reads = ArtistReads();
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.followFakeTime(tester.binding);
  harness.network.on(WorldIds.lidarr, 'GET', '/api/v1/album', (request) {
    if (request.query['artistId'] != '1') return null;
    return NetworkReply.json(albums(++reads.count));
  });
  tester.view
    ..physicalSize = const Size(390, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(home: ArtistPage(artistId: 1, justAdded: justAdded)),
    ),
  );
  // The skeleton shimmers for ever: let the first reads land by hand.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return (harness: harness, reads: reads);
}

class ArtistReads {
  var count = 0;
}

List<Map<String, Object?>> _albums() => [
  for (final (id, title, year) in [
    (1, 'Elephants Dream', 2006),
    (2, 'Big Buck Bunny', 2008),
  ])
    {
      'id': id,
      'artistId': 1,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'images': const <Object?>[],
      'statistics': {'trackFileCount': 0, 'totalTrackCount': 5},
    },
];

/// Lets the page's timer fire and the read it asks for land.
Future<void> _wait(WidgetTester tester, Duration time) async {
  await tester.pump(time);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('says Lidarr is reading the albums, over three rows that are '
      'not there yet', (tester) async {
    final (:harness, :reads) = await _open(tester, albums: (_) => const []);

    expect(find.text('Added just now'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text(_reading), findsOneWidget);
    expect(find.byType(ShimmerPlaceholder), findsAtLeastNWidgets(9));
    // Not what a page that gave up says.
    expect(find.textContaining('knows of no albums'), findsNothing);
    expect(reads.count, 1);

    await harness.unmount(tester);
  });

  testWidgets('reads the albums again every 3 seconds and shows them when '
      'they arrive, then stops asking', (tester) async {
    final (:harness, :reads) = await _open(
      tester,
      albums: (read) => read < 3 ? const [] : _albums(),
    );
    expect(reads.count, 1);

    await _wait(tester, artistReadEvery);
    expect(reads.count, 2);
    expect(find.text(_reading), findsOneWidget);

    await _wait(tester, artistReadEvery);
    expect(reads.count, 3);
    expect(find.text(_reading), findsNothing);
    expect(find.text('Added just now'), findsNothing);
    expect(find.text('Elephants Dream'), findsOneWidget);
    expect(find.text('Big Buck Bunny'), findsOneWidget);

    // Albums are there: the page has nothing left to wait for.
    await _wait(tester, artistReadEvery);
    await _wait(tester, artistReadEvery * 5);
    expect(reads.count, 3);

    await harness.unmount(tester);
  });

  testWidgets('gives up after a minute with what the page says of an artist '
      'with no albums', (tester) async {
    final (:harness, :reads) = await _open(tester, albums: (_) => const []);

    await _wait(tester, artistReadFor - artistReadEvery);
    expect(find.text(_reading), findsOneWidget);

    await _wait(tester, artistReadEvery);
    expect(find.text(_reading), findsNothing);
    expect(find.text('Added just now'), findsNothing);
    expect(
      find.textContaining('Lidarr knows of no albums by this artist yet.'),
      findsOneWidget,
    );

    final asked = reads.count;
    await _wait(tester, artistReadEvery * 5);
    expect(reads.count, asked);

    await harness.unmount(tester);
  });

  testWidgets('a page not opened by an add says it at once and never polls', (
    tester,
  ) async {
    final (:harness, :reads) = await _open(
      tester,
      albums: (_) => const [],
      justAdded: false,
    );

    expect(find.text(_reading), findsNothing);
    expect(find.text('Added just now'), findsNothing);
    expect(
      find.textContaining('Lidarr knows of no albums by this artist yet.'),
      findsOneWidget,
    );
    await _wait(tester, artistReadFor);
    expect(reads.count, 1);

    await harness.unmount(tester);
  });

  testWidgets('leaving the page stops the reads', (tester) async {
    final (:harness, :reads) = await _open(tester, albums: (_) => const []);

    await _wait(tester, artistReadEvery);
    expect(reads.count, 2);

    await harness.unmount(tester);
    await tester.pump(artistReadEvery * 5);

    expect(reads.count, 2);
  });
}
