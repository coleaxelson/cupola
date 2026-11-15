/// An artist's page by kind of album, and the finder of a track among them:
/// Jan Morgenstern's nine albums as the board draws them (three soundtracks,
/// four singles, an EP and an album), and the tracks Lidarr lists for them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/music/presentation/artist_type_pills.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(800, 3600);
const _nbsp = '\u00A0';

Map<String, Object?> _album(
  int id,
  String title, {
  String type = 'Album',
  List<String> secondary = const [],
  String year = '2010',
  int files = 1,
  int tracks = 1,
  bool monitored = true,
  String? date,
}) => {
  'id': id,
  'artistId': 1,
  'title': title,
  'albumType': type,
  'secondaryTypes': secondary,
  'monitored': monitored,
  'releaseDate': date ?? '$year-01-01T00:00:00Z',
  'images': const <Object?>[],
  'statistics': {'trackFileCount': files, 'totalTrackCount': tracks},
};

/// Three soundtracks (one left alone), four singles (two wanted, one on disk
/// and one left alone), an EP and an album announced.
List<Map<String, Object?>> _nine() => [
  _album(1, 'Elephants Dream OST', secondary: ['Soundtrack'], year: '2006'),
  _album(2, 'Big Buck Bunny OST', secondary: ['Soundtrack'], year: '2008'),
  _album(
    3,
    'Sintel OST',
    secondary: ['Soundtrack', 'Studio'],
    year: '2010',
    files: 0,
    monitored: false,
  ),
  _album(4, 'The Dragon', type: 'Single', files: 0),
  _album(5, 'Snow', type: 'Single', files: 0),
  _album(6, 'Finale', type: 'Single'),
  _album(7, 'Caminandes', type: 'Single', files: 0, monitored: false),
  _album(8, 'Spring', type: 'EP', year: '2019', files: 2, tracks: 2),
  _album(9, 'Next', date: '2999-01-01T00:00:00Z', files: 0, tracks: 5),
];

Map<String, Object?> _track(
  int id,
  int albumId,
  String title, {
  int number = 1,
  int duration = 0,
  bool hasFile = true,
}) => {
  'id': id,
  'albumId': albumId,
  'title': title,
  'trackNumber': '$number',
  'mediumNumber': 1,
  'duration': duration,
  'hasFile': hasFile,
};

/// Sintel's tracks on the soundtrack, and the single that shares one's name.
List<Map<String, Object?>> _tracksOfJan() => [
  _track(301, 3, 'Opening', number: 1, hasFile: false),
  _track(303, 3, 'The Dragon', number: 3, duration: 336000, hasFile: false),
  _track(401, 4, 'The Dragon', hasFile: false),
  _track(501, 5, 'Snow', hasFile: false),
  _track(601, 6, 'Finale', duration: 270000),
  _track(801, 8, 'Café Spring', number: 2, duration: 180000),
  _track(802, 8, 'Spring Snow', number: 1, duration: 200000),
];

class _Reads {
  var tracks = 0;
}

Future<({ProfileHarness harness, _Reads reads})> _open(
  WidgetTester tester, {
  List<Map<String, Object?>>? albums,
  List<Map<String, Object?>>? tracks,
  NetworkReply Function()? trackReply,
  ArtistPage page = const ArtistPage(artistId: 1),
  Size size = _tall,
}) async {
  final reads = _Reads();
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.followFakeTime(tester.binding);
  harness.network
    ..on(
      WorldIds.lidarr,
      'GET',
      '/api/v1/album',
      (r) => r.query['artistId'] == '1'
          ? NetworkReply.json(albums ?? _nine())
          : null,
    )
    ..on(WorldIds.lidarr, 'GET', '/api/v1/track', (r) {
      if (r.query['artistId'] == '1') {
        reads.tracks++;
        return trackReply?.call() ??
            NetworkReply.json(tracks ?? _tracksOfJan());
      }
      final album = int.tryParse(r.query['albumId'] ?? '');
      return NetworkReply.json([
        for (final track in tracks ?? _tracksOfJan())
          if (track['albumId'] == album) track,
      ]);
    });
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(home: page),
    ),
  );
  await harness.settle(tester);
  return (harness: harness, reads: reads);
}

Future<void> _openFinder(WidgetTester tester, ProfileHarness harness) async {
  // The lens beside the pills, or the button where there are no pills.
  final lens = find.byType(ArtistFindLens);
  await tester.tap(lens.evaluate().isEmpty ? find.text('Find a track') : lens);
  await harness.settle(tester);
}

Future<void> _type(
  WidgetTester tester,
  ProfileHarness harness,
  String text,
) async {
  await tester.enterText(find.byType(EditableText), text);
  await harness.settle(tester);
}

void main() {
  group('by kind', () {
    testWidgets('an artist with several kinds gets a pill each with its '
        'count, and the counts add up to All', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, reads: _) = await _open(tester);

      expect(find.text('All 9'), findsOneWidget);
      expect(find.text('EPs 1'), findsOneWidget);
      expect(find.text('Singles 4'), findsOneWidget);
      expect(find.text('Soundtracks 3'), findsOneWidget);
      // Albums: the one announced. In the order the pills read in.
      expect(find.text('Albums 1'), findsOneWidget);
      final lefts = [
        for (final label in [
          'All 9',
          'Albums 1',
          'EPs 1',
          'Singles 4',
          'Soundtracks 3',
        ])
          tester.getTopLeft(find.text(label)).dx,
      ];
      expect(lefts, [...lefts]..sort());
      // One sentence each, and `All` is the one chosen.
      expect(
        find.semantics.byLabel('All, 9'),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        find.semantics.byLabel('Singles, 4'),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('an artist with one kind has no pills, and a quiet Find a '
        'track in their place', (tester) async {
      final (:harness, reads: _) = await _open(
        tester,
        albums: [
          _album(1, 'Sintel'),
          _album(2, 'Spring', year: '2019'),
        ],
      );

      expect(find.byType(ArtistTypePills), findsNothing);
      expect(find.byType(SelectionPill), findsNothing);
      expect(find.byType(ArtistFindLens), findsNothing);
      expect(find.text('Find a track'), findsOneWidget);
      // The row does not say the kind: they are all one.
      expect(find.textContaining('Album'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('the rows say their kind when there are several', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);

      expect(
        find.text('2010$_nbsp· Single$_nbsp· 1${_nbsp}track'),
        findsWidgets,
      );

      await harness.unmount(tester);
    });

    testWidgets('a kind chosen filters the four places, which recount, and '
        'the ones left empty go; the summary stays the artist\'s whole', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);

      // All: one announced, two wanted, on disk (the finale, the OSTs, the
      // EP), and the two left alone behind their line.
      // `Wanted` is the heading and the word of the two rows under it.
      expect(find.text('Coming'), findsOneWidget);
      expect(find.text('Wanted'), findsNWidgets(3));
      expect(find.text('On disk'), findsOneWidget);
      expect(find.text('Unmonitored'), findsNothing);
      expect(find.text('2${_nbsp}unmonitored albums'), findsOneWidget);
      const whole =
          '4${_nbsp}albums on disk$_nbsp· 2${_nbsp}wanted$_nbsp· 1${_nbsp}announced';
      expect(find.text(whole), findsOneWidget);

      await tester.tap(find.text('Singles 4'));
      await harness.settle(tester);

      expect(find.text('Coming'), findsNothing);
      expect(find.text('Wanted'), findsNWidgets(3));
      expect(find.text('2${_nbsp}singles'), findsOneWidget);
      expect(find.text('On disk'), findsOneWidget);
      expect(find.text('1${_nbsp}single'), findsOneWidget);
      expect(find.text('1${_nbsp}unmonitored single'), findsOneWidget);
      expect(find.text('The Dragon'), findsOneWidget);
      expect(find.text('Snow'), findsOneWidget);
      expect(find.text('Finale'), findsOneWidget);
      expect(find.text('Spring'), findsNothing);
      expect(find.text('Sintel OST'), findsNothing);
      // The summary under the name is not the filter's.
      expect(find.text(whole), findsOneWidget);

      await tester.tap(find.text('Soundtracks 3'));
      await harness.settle(tester);

      expect(find.text('Wanted'), findsNothing);
      expect(find.text('On disk'), findsOneWidget);
      expect(find.text('2${_nbsp}soundtracks'), findsOneWidget);
      expect(find.text('1${_nbsp}unmonitored soundtrack'), findsOneWidget);
      expect(find.text('Elephants Dream OST'), findsOneWidget);

      await tester.tap(find.text('All 9'));
      await harness.settle(tester);

      expect(find.text('Coming'), findsOneWidget);
      expect(find.text('2${_nbsp}unmonitored albums'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('the unmonitored line opens them, under a heading that '
        'counts the kind', (tester) async {
      final (:harness, reads: _) = await _open(tester);

      await tester.tap(find.text('Singles 4'));
      await harness.settle(tester);
      await tester.tap(find.text('Show them'));
      await harness.settle(tester);

      // The heading, and the word of the one row under it.
      expect(find.text('Unmonitored'), findsNWidgets(2));
      expect(find.text('Caminandes'), findsOneWidget);
      expect(find.text('Show them'), findsNothing);
      expect(find.text('Sintel OST'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('the unmonitored line speaks one sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, reads: _) = await _open(tester);

      await tester.tap(find.text('Singles 4'));
      await harness.settle(tester);

      expect(
        find.bySemanticsLabel('1${_nbsp}unmonitored single, show them'),
        findsOneWidget,
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('the choice lives while the page does: a refresh keeps it', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);

      await tester.tap(find.text('EPs 1'));
      await harness.settle(tester);
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await harness.settle(tester);

      expect(find.text('Spring'), findsOneWidget);
      expect(find.text('Finale'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('finding a track', () {
    testWidgets('the lens opens a field named for the artist, with Done, and '
        'the albums give way to the results', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, :reads) = await _open(tester);

      expect(
        find.bySemanticsLabel('Find a track by Jan Morgenstern'),
        findsOneWidget,
      );
      expect(reads.tracks, 0, reason: 'nothing is read until it opens');

      await _openFinder(tester, harness);

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(ArtistTypePills), findsNothing);
      expect(find.text('Wanted'), findsNothing);
      expect(find.text('The Dragon'), findsNothing);
      expect(find.text('Search albums'), findsNothing);
      expect(reads.tracks, 1);
      expect(
        find.text(
          'Tracks of Jan Morgenstern’s albums that Lidarr knows. '
          'A tap opens the album on its tracks.',
        ),
        findsOneWidget,
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('one kind: the quiet button opens the same finder', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        albums: [
          _album(3, 'Sintel'),
          _album(8, 'Spring', year: '2019'),
        ],
      );

      await tester.tap(find.text('Find a track'));
      await harness.settle(tester);

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.text('Find a track'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('typing lists the tracks, marked, each with its album and '
        'where it stands, under a heading that counts them', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);

      await _type(tester, harness, 'the drag');

      expect(find.text('2${_nbsp}tracks'), findsOneWidget);
      expect(find.byType(SearchRow), findsNWidgets(2));
      // The soundtrack's track, with its number and length; the single's,
      // with no length known.
      expect(
        find.text('Sintel OST$_nbsp· track 3$_nbsp· 5:36'),
        findsOneWidget,
      );
      expect(find.text('The Dragon$_nbsp· track 1'), findsOneWidget);
      // The words typed are marked in the title: underlined.
      final marked = <String>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.decoration == TextDecoration.underline) {
            marked.add(span.text!);
          }
          return true;
        });
      }
      expect(marked, ['The Drag', 'The Drag']);
      // One sentence each.
      expect(
        find.bySemanticsLabel(
          'The Dragon, track 3 on Sintel OST, 5:36, unmonitored',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('The Dragon, track 1 on The Dragon, wanted'),
        findsOneWidget,
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a track with a file says On disk; one without says its '
        'album\'s own word, so a track never contradicts its album', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);

      await _type(tester, harness, 'finale');
      expect(find.text('On disk'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Finale, track 1 on Finale, 4:30, on disk'),
        findsOneWidget,
      );

      await _type(tester, harness, 'snow');
      // `Snow` the single is wanted; `Spring Snow` is on the EP, on disk.
      expect(find.text('Wanted'), findsOneWidget);
      expect(find.text('On disk'), findsOneWidget);

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('is blind to case and accents', (tester) async {
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);

      await _type(tester, harness, 'CAFE');

      expect(find.text('1${_nbsp}track'), findsOneWidget);
      expect(find.byType(SearchRow), findsOneWidget);
      expect(find.text('Spring$_nbsp· track 2$_nbsp· 3:00'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an album Lidarr has not released says so on its tracks', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        tracks: [_track(901, 9, 'Not Yet', hasFile: false)],
      );
      await _openFinder(tester, harness);

      await _type(tester, harness, 'not');

      expect(find.textContaining('not out yet'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('reads the tracks once: closing and opening again asks '
        'nothing more', (tester) async {
      final (:harness, :reads) = await _open(tester);

      await _openFinder(tester, harness);
      await tester.tap(find.text('Done'));
      await harness.settle(tester);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(ArtistTypePills), findsOneWidget);

      await _openFinder(tester, harness);
      await _type(tester, harness, 'snow');

      expect(reads.tracks, 1);
      expect(find.byType(SearchRow), findsNWidgets(2));

      await harness.unmount(tester);
    });

    testWidgets('Done puts the pills back and the albums with them', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);
      await _type(tester, harness, 'snow');

      await tester.tap(find.text('Done'));
      await harness.settle(tester);

      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Singles 4'), findsOneWidget);
      expect(find.text('Wanted'), findsNWidgets(3));
      expect(find.text('Search albums'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('nothing found says what was asked and what Lidarr knows', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);

      await _type(tester, harness, 'zebra');

      expect(find.text('No track called “zebra”'), findsOneWidget);
      expect(
        find.text(
          'Lidarr knows the tracks of the albums it lists for this artist.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SearchRow), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('while Lidarr is asked it says so over skeleton rows', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        trackReply: () => const NetworkReply.hang(),
      );

      await tester.tap(find.byType(ArtistFindLens));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Asking Lidarr'), findsOneWidget);
      expect(find.byType(SearchRowsPending), findsOneWidget);
      expect(find.byType(SearchRow), findsNothing);

      await tester.pump(const Duration(seconds: 20));
      await harness.unmount(tester);
    });

    testWidgets('a failure names Lidarr, and Retry reads again', (
      tester,
    ) async {
      var failing = true;
      final (:harness, :reads) = await _open(
        tester,
        trackReply: () => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : NetworkReply.json(_tracksOfJan()),
      );
      await _openFinder(tester, harness);

      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      expect(reads.tracks, 1);

      failing = false;
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);
      await _type(tester, harness, 'snow');

      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(reads.tracks, 2);
      expect(find.byType(SearchRow), findsNWidgets(2));

      await harness.unmount(tester);
    });

    testWidgets('a tap closes the finder and opens the album on its tracks', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);
      await _openFinder(tester, harness);
      await _type(tester, harness, 'spring snow');

      await tester.tap(find.byType(SearchRow));
      await harness.settle(tester);

      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(AlbumTracks), findsOneWidget);
      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Spring',
      );
      // Its tracks, read as an album's are.
      expect(find.text('Café Spring'), findsOneWidget);
      expect(find.text('2 of 2 tracks on disk'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a tap clears a kind that would hide the album', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (:harness, reads: _) = await _open(tester);
      await tester.tap(find.text('Soundtracks 3'));
      await harness.settle(tester);
      await _openFinder(tester, harness);
      await _type(tester, harness, 'finale');

      await tester.tap(find.byType(SearchRow));
      await harness.settle(tester);

      // `Finale` is a single: the filter that hid it is gone.
      expect(
        find.semantics.byLabel('All, 9'),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(find.text('Elephants Dream OST'), findsOneWidget);
      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Finale',
      );

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a tap keeps a kind that already shows the album', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(tester);
      await tester.tap(find.text('Singles 4'));
      await harness.settle(tester);
      await _openFinder(tester, harness);
      await _type(tester, harness, 'finale');

      await tester.tap(find.byType(SearchRow));
      await harness.settle(tester);

      expect(find.text('Elephants Dream OST'), findsNothing);
      expect(find.byType(AlbumTracks), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a tap unfolds the unmonitored albums when the album is one '
        'of them', (tester) async {
      final (:harness, reads: _) = await _open(
        tester,
        tracks: [_track(701, 7, 'Caminandes Llamigos', hasFile: false)],
      );
      await _openFinder(tester, harness);
      await _type(tester, harness, 'llamigos');

      await tester.tap(find.byType(SearchRow));
      await harness.settle(tester);

      // The heading and the words of the two albums left alone.
      expect(find.text('Unmonitored'), findsNWidgets(3));
      expect(find.byType(AlbumTracks), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a tap scrolls the page to an album far down the page', (
      tester,
    ) async {
      final albums = [
        for (var i = 1; i <= 40; i++)
          _album(i, 'Record $i', year: '${1980 + i}', files: 0),
      ];
      final (:harness, reads: _) = await _open(
        tester,
        albums: albums,
        tracks: [_track(1, 1, 'Opening Night', hasFile: false)],
        size: const Size(390, 700),
      );

      // `Record 1` is the oldest: last of forty, far below the screen.
      expect(find.text('Record 1'), findsNothing);
      await _openFinder(tester, harness);
      await _type(tester, harness, 'opening');
      await tester.tap(find.byType(SearchRow));
      await harness.settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);

      expect(find.byType(AlbumTracks), findsOneWidget);
      final top = tester.getTopLeft(find.byType(AlbumTracks)).dy;
      expect(top, inInclusiveRange(0, 700));

      await harness.unmount(tester);
    });

    testWidgets('a tap reaches an unmonitored album under a long On disk '
        'list, whose heading starts far outside what is built', (tester) async {
      final albums = [
        for (var i = 1; i <= 60; i++)
          _album(i, 'Record $i', year: '${1950 + i}', files: 1),
        _album(99, 'Hidden', year: '1940', files: 0, monitored: false),
      ];
      final (:harness, reads: _) = await _open(
        tester,
        albums: albums,
        tracks: [_track(990, 99, 'Buried Treasure', hasFile: false)],
        size: const Size(390, 700),
      );

      await _openFinder(tester, harness);
      await _type(tester, harness, 'buried');
      await tester.tap(find.byType(SearchRow));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await harness.settle(tester);

      expect(find.byType(AlbumTracks), findsOneWidget);
      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Hidden',
      );
      final top = tester.getTopLeft(find.byType(AlbumTracks)).dy;
      expect(top, inInclusiveRange(0, 700));

      await harness.unmount(tester);
    });

    testWidgets('a tap reaches the tail of a second long list, whose place '
        'starts far below another one', (tester) async {
      final albums = [
        for (var i = 1; i <= 50; i++)
          _album(i, 'Wanted $i', year: '${2000 + i % 20}', files: 0),
        for (var i = 51; i <= 110; i++)
          _album(i, 'Kept $i', year: '${1950 + i % 40}'),
      ];
      final (:harness, reads: _) = await _open(
        tester,
        albums: albums,
        tracks: [_track(1100, 110, 'Deep Cut', hasFile: true)],
        size: const Size(390, 700),
      );

      await _openFinder(tester, harness);
      await _type(tester, harness, 'deep');
      await tester.tap(find.byType(SearchRow));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await harness.settle(tester);

      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Kept 110',
      );
      final top = tester.getTopLeft(find.byType(AlbumTracks)).dy;
      expect(top, inInclusiveRange(0, 700));

      await harness.unmount(tester);
    });

    testWidgets('offers no lens while Lidarr is still reading the albums', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        albums: const [],
        page: const ArtistPage(artistId: 1, justAdded: true),
      );

      expect(find.byType(ArtistFindLens), findsNothing);
      expect(find.text('Find a track'), findsNothing);
      expect(find.byType(ArtistTypePills), findsNothing);

      await harness.unmount(tester);
    });
  });
  group('opened on an album (the link\u2019s ?album=)', () {
    testWidgets('the page opens on its tracks, as a found track does', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        page: const ArtistPage(artistId: 1, openAlbumId: 8),
      );

      expect(find.byType(AlbumTracks), findsOneWidget);
      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Spring',
      );
      expect(find.text('Café Spring'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an album left alone unfolds the albums left alone', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        tracks: [_track(701, 7, 'Caminandes Llamigos', hasFile: false)],
        page: const ArtistPage(artistId: 1, openAlbumId: 7),
      );

      // The heading and the words of the two albums left alone.
      expect(find.text('Unmonitored'), findsNWidgets(3));
      expect(
        tester.widget<AlbumTracks>(find.byType(AlbumTracks)).album.title,
        'Caminandes',
      );
      expect(find.text('Caminandes Llamigos'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('reaches an album far down the page', (tester) async {
      final albums = [
        for (var i = 1; i <= 40; i++)
          _album(i, 'Record $i', year: '${1980 + i}', files: 0),
      ];
      final (:harness, reads: _) = await _open(
        tester,
        albums: albums,
        tracks: [_track(1, 1, 'Opening Night', hasFile: false)],
        size: const Size(390, 700),
        page: const ArtistPage(artistId: 1, openAlbumId: 1),
      );
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);

      expect(find.byType(AlbumTracks), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(AlbumTracks)).dy,
        inInclusiveRange(0, 700),
      );

      await harness.unmount(tester);
    });

    testWidgets('an album the artist does not have opens nothing', (
      tester,
    ) async {
      final (:harness, reads: _) = await _open(
        tester,
        page: const ArtistPage(artistId: 1, openAlbumId: 404),
      );

      expect(find.byType(AlbumTracks), findsNothing);
      expect(find.text('Singles 4'), findsOneWidget);

      await harness.unmount(tester);
    });
  });
}
