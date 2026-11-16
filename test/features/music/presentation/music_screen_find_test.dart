/// The Music wall's search: the library first, Lidarr on request, and what a
/// row says and does in each.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_album_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/music_find.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/profiles/profiles.dart';

LidarrArtist _artist(
  int id,
  String name, {
  String foreign = '',
  Map<String, dynamic>? statistics,
  String? type,
}) => LidarrArtist(
  id: id,
  artistName: name,
  foreignArtistId: foreign,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  artistType: type,
  statistics: statistics,
);

LidarrAlbum _album(
  int id,
  String title,
  int artistId, {
  required String year,
  int files = 0,
  int tracks = 11,
  bool monitored = true,
  String foreign = '',
  String? type,
}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  foreignAlbumId: foreign,
  albumType: type,
  releaseDate: '$year-01-01T00:00:00Z',
  monitored: monitored,
  images: const [],
  statistics: {'trackFileCount': files, 'totalTrackCount': tracks},
);

/// A Lidarr with a library to find in and a script for its search.
class _Lidarr extends FakeLidarrService {
  _Lidarr({
    this.searchAnswer,
    this.searchError,
    this.gate,
    this.extraAlbums = const [],
  });

  /// Albums beside the library's own few, for a library of thousands.
  final List<LidarrAlbum> extraAlbums;

  final List<LidarrSearchHit>? searchAnswer;
  Object? searchError;
  final Completer<void>? gate;
  final searched = <String>[];
  final monitored = <int>[];
  Object? monitorError;

  /// The search failed after the monitor was written.
  Object? searchStartError;

  /// How many times the library's albums were read, and a read held open.
  var albumReads = 0;
  Completer<void>? albumsGate;

  static final artists = [
    _artist(
      2,
      'Edward Elgar',
      foreign: 'mb-elgar',
      statistics: {'albumCount': 9, 'trackCount': 40, 'trackFileCount': 40},
    ),
    _artist(
      3,
      'Ella Fitzgerald',
      foreign: 'mb-ella',
      statistics: {'albumCount': 31, 'trackCount': 400, 'trackFileCount': 336},
    ),
    _artist(4, 'Björk', foreign: 'mb-bjork'),
    _artist(1, 'Jan Morgenstern', foreign: 'mb-jan'),
    _artist(5, 'The Jimi Hendrix Experience', foreign: 'mb-jimi'),
  ];

  static final albums = [
    _album(
      10,
      'Elephants Dream',
      1,
      year: '2006',
      files: 7,
      tracks: 7,
      foreign: 'mb-elephants',
    ),
    _album(11, 'Ella and Louis', 3, year: '1956', files: 9, foreign: 'mb-eal'),
    _album(
      12,
      'Elegy for Strings',
      2,
      year: '1909',
      tracks: 1,
      foreign: 'mb-elegy',
    ),
    _album(
      13,
      'Electric Ladyland',
      5,
      year: '1968',
      monitored: false,
      foreign: 'mb-ladyland',
    ),
  ];

  @override
  Future<List<LidarrArtist>> getArtists() async => artists;

  @override
  Future<List<LidarrAlbum>> getAllAlbumsOrThrow() async {
    albumReads++;
    await albumsGate?.future;
    return [...albums, ...extraAlbums];
  }

  @override
  Future<List<LidarrSearchHit>> search(
    String term, {
    CancelToken? cancelToken,
  }) async {
    searched.add(term);
    await gate?.future;
    if (searchError != null) throw searchError!;
    return searchAnswer ?? const [];
  }

  @override
  Future<void> monitorAndSearchAlbum(int albumId) async {
    if (monitorError != null) throw monitorError!;
    monitored.add(albumId);
    if (searchStartError != null) {
      throw LidarrSearchNotStarted(searchStartError!);
    }
  }
}

/// What Lidarr's catalog answers: Elbow (not held), Ella (held), an album of
/// Elbow's (neither), one the library holds and left alone, and one by an
/// artist the library holds that it does not.
List<LidarrSearchHit> _catalog() {
  LidarrAlbumHit album(
    String title,
    String foreign,
    LidarrArtist artist, {
    String type = 'Album',
  }) {
    final raw = {
      'id': 0,
      'title': title,
      'foreignAlbumId': foreign,
      'albumType': type,
      'releaseDate': '2003-04-14T00:00:00Z',
      'monitored': false,
      'images': const [],
      'artist': {
        'id': artist.id,
        'artistName': artist.artistName,
        'foreignArtistId': artist.foreignArtistId,
        'artistType': artist.artistType,
        'status': 'continuing',
        'monitored': false,
        'images': const [],
        'genres': const [],
      },
    };
    return LidarrAlbumHit(
      album: LidarrAlbum.fromJson(raw),
      artist: artist,
      raw: raw,
    );
  }

  final elbow = _artist(0, 'Elbow', foreign: 'mb-elbow', type: 'Group');
  return [
    LidarrArtistHit(elbow),
    LidarrArtistHit(
      _artist(0, 'Ella Fitzgerald', foreign: 'mb-ella', type: 'Person'),
    ),
    album('Leaders of the Free World', 'mb-leaders', elbow),
    album(
      'Electric Ladyland',
      'mb-ladyland',
      _artist(0, 'The Jimi Hendrix Experience', foreign: 'mb-jimi'),
    ),
    album(
      'Elegy for Brass',
      'mb-brass',
      _artist(0, 'Edward Elgar', foreign: 'mb-elgar'),
      type: 'Single',
    ),
  ];
}

/// The wall on the profiles' network, with [lidarr] standing in for the lens's
/// Lidarr, and the artist's page as a line saying which artist was opened.
Future<({ProfileHarness harness, GoRouter router, _Lidarr lidarr})> _open(
  WidgetTester tester, {
  _Lidarr? lidarr,
  double textScale = 1,
  ThemeData? theme,
  Size size = const Size(390, 1400),
  List<Override> overrides = const [],
}) async {
  final fake = lidarr ?? _Lidarr(searchAnswer: _catalog());
  final harness = await ProfileHarness.start(
    Profiles.p1,
    overrides: [lidarrServiceProvider.overrideWithValue(fake), ...overrides],
  );
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = size
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
        theme: theme ?? AppTheme.darkTheme(),
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
  await harness.settle(tester);
  return (harness: harness, router: router, lidarr: fake);
}

Future<void> _type(
  WidgetTester tester,
  ProfileHarness harness,
  String text,
) async {
  await tester.enterText(find.byType(TextField), text);
  await harness.settle(tester);
}

/// Asks Lidarr for what is in the field: the second segment.
Future<void> _askLidarr(WidgetTester tester, ProfileHarness harness) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MediaFindScopeControl),
      matching: find.text('Lidarr'),
    ),
  );
  await harness.settle(tester);
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SearchRow));

/// The disc at the end of the row named [title].
Finder _disc(String title) =>
    find.descendant(of: _row(title), matching: find.byIcon(Icons.add_rounded));

/// The semantics node the row named [title] speaks with.
SemanticsNode _node(WidgetTester tester, String title) => tester.getSemantics(
  find
      .descendant(
        of: _row(title),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == title,
        ),
      )
      .first,
);

/// What a screen reader says of the row named [title]: its name, then the
/// rest, with the no-break spaces the eye never sees.
String _said(WidgetTester tester, String title) {
  final node = _node(tester, title);
  return '${node.label}, ${node.value}'.replaceAll('\u00A0', ' ');
}

void main() {
  group('your library', () {
    testWidgets('finds artists and albums by the start of a word, with how '
        'many of each', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'el');

      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      // `Ella Fitzgerald` opens with `el`, `Edward Elgar` meets it later.
      expect(
        tester.getTopLeft(find.text('Ella Fitzgerald')).dy,
        lessThan(tester.getTopLeft(find.text('Edward Elgar')).dy),
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Björk'), findsNothing);
      expect(lidarr.searched, isEmpty, reason: 'no network for the library');

      await harness.unmount(tester);
    });

    testWidgets('is blind to case and accents', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'BJO');

      expect(find.text('Björk'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an artist row says its albums and what is missing', (
      tester,
    ) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'el');

      expect(find.text('9\u00A0albums\u00A0· complete'), findsOneWidget);
      expect(
        find.text('31\u00A0albums\u00A0· 64\u00A0tracks missing'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('an album row says who, when and how long, and where it '
        'stands in the one word the artist page uses', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'el');

      final dream = _row('Elephants Dream');
      expect(
        find.descendant(
          of: dream,
          matching: find.text(
            'Jan Morgenstern\u00A0· 2006\u00A0· 7\u00A0tracks',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dream, matching: find.text('Complete')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Ella and Louis'),
          matching: find.text('9 of 11\u00A0tracks'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Elegy for Strings'),
          matching: find.text('Wanted'),
        ),
        findsOneWidget,
      );

      await _type(tester, harness, 'electric');
      expect(
        find.descendant(
          of: _row('Electric Ladyland'),
          matching: find.text('Unmonitored'),
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('each row is one spoken sentence', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      final handle = tester.ensureSemantics();

      expect(
        _said(tester, 'Ella Fitzgerald'),
        'Ella Fitzgerald, 31 albums, 64 tracks missing',
      );
      expect(
        _said(tester, 'Elephants Dream'),
        'Elephants Dream, Jan Morgenstern, 2006, 7 tracks, Complete',
      );

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a few thousand albums build only what is on screen, with '
        'the count in the heading', (tester) async {
      final lidarr = _Lidarr(
        extraAlbums: [
          for (var i = 0; i < 4000; i++)
            _album(1000 + i, 'The Album $i', 1, year: '2001'),
        ],
      );
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );

      await _type(tester, harness, 'the');

      expect(find.text('4000'), findsOneWidget);
      expect(find.byType(SearchRow).evaluate().length, lessThan(30));
      // The far end is there when scrolled to.
      await tester.drag(find.byType(ListView).last, const Offset(0, -400000));
      await tester.pump();
      expect(find.byType(SearchRow).evaluate().length, lessThan(30));

      await harness.unmount(tester);
    });

    testWidgets('closes with what the list names', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'el');

      expect(
        find.text(
          'Names of artists and albums. Lidarr keeps albums, so a song is '
          'found by its album.',
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('an artist opens its page', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'ella fitz');

      await tester.tap(find.text('Ella Fitzgerald'));
      await harness.settle(tester);

      expect(find.text('artist page 3 added=null'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an album opens its artist, which is the page Lidarr has for '
        'it', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'elegy');

      await tester.tap(find.text('Elegy for Strings'));
      await harness.settle(tester);

      expect(find.text('artist page 2 added=null'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('nothing found says so once, and offers Lidarr', (
      tester,
    ) async {
      final (:harness, :router, :lidarr) = await _open(tester);

      await _type(tester, harness, 'elbo');

      expect(
        find.text('Nothing in your library called “elbo”'),
        findsOneWidget,
      );
      expect(find.text('Lidarr can look further.'), findsOneWidget);
      expect(find.text('Search Lidarr for “elbo”'), findsOneWidget);
      expect(find.text('Artists'), findsNothing);

      await tester.tap(find.text('Search Lidarr for “elbo”'));
      await harness.settle(tester);

      expect(lidarr.searched, ['elbo']);
      expect(find.text('Elbow'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('Lidarr', () {
    testWidgets('finds artists and albums, and says which the library holds', (
      tester,
    ) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      expect(lidarr.searched, ['el']);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      // What the catalog says of an artist is what it says: no country made
      // up.
      expect(
        find.descendant(of: _row('Elbow'), matching: find.text('Group')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Ella Fitzgerald'),
          matching: find.text('In your library'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Elbow'),
          matching: find.text('In your library'),
        ),
        findsNothing,
      );
      // An album the library holds reads in the library's word for it.
      expect(
        find.descendant(
          of: _row('Electric Ladyland'),
          matching: find.text('Unmonitored'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Leaders of the Free World'),
          matching: find.text('Elbow\u00A0· 2003\u00A0· Album'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Elegy for Brass'),
          matching: find.text('Edward Elgar\u00A0· 2003\u00A0· Single'),
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a disc is its own button with a name and a 44pt target, and '
        'the row beside it speaks one sentence', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsLabel('Add Elbow to Lidarr'), findsOneWidget);
      expect(_said(tester, 'Elbow'), 'Elbow, Group');
      expect(
        _node(tester, 'Elbow').hint,
        'Not in your library. Adds it to Lidarr',
      );
      expect(
        _said(tester, 'Ella Fitzgerald'),
        'Ella Fitzgerald, Person, In your library',
      );
      final disc = tester.getSize(
        find
            .ancestor(of: _disc('Elbow'), matching: find.byType(Container))
            .first,
      );
      expect(disc.width, greaterThanOrEqualTo(44));
      expect(disc.height, greaterThanOrEqualTo(44));

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('an artist the library holds opens its page; one it does '
        'not is added from its disc', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      await tester.tap(find.text('Ella Fitzgerald'));
      await harness.settle(tester);
      expect(find.text('artist page 3 added=null'), findsOneWidget);
      router.pop();
      await harness.settle(tester);

      await tester.tap(_disc('Elbow'));
      await harness.settle(tester);

      expect(find.byType(LidarrAddArtistSheet), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an album the library holds and left alone is monitored and '
        'searched from its disc, and says so', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      await tester.tap(_disc('Electric Ladyland'));
      await harness.settle(tester);

      expect(lidarr.monitored, [13]);
      expect(find.text('Lidarr is looking for Electric Ladyland'), findsOne);

      await harness.unmount(tester);
    });

    testWidgets('a monitor that went through and a search that did not '
        'says the album is monitored, and the albums are read again', (
      tester,
    ) async {
      final lidarr = _Lidarr(searchAnswer: _catalog())
        ..searchStartError = DioException.receiveTimeout(
          timeout: const Duration(seconds: 30),
          requestOptions: RequestOptions(path: '/api/v1/command'),
        );
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);
      final reads = lidarr.albumReads;

      await tester.tap(_disc('Electric Ladyland'));
      await harness.settle(tester);

      expect(lidarr.monitored, [13]);
      expect(
        find.textContaining(
          'Electric Ladyland is monitored, but Lidarr did not start looking '
          'for it.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Could not monitor'), findsNothing);
      expect(lidarr.albumReads, greaterThan(reads));

      await harness.unmount(tester);
    });

    testWidgets('the control stays busy until the albums are read again, '
        'and a second tap in that stretch asks for nothing', (tester) async {
      final lidarr = _Lidarr(searchAnswer: _catalog());
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);
      final reads = lidarr.albumReads;
      lidarr.albumsGate = Completer<void>();

      final disc = _disc('Electric Ladyland');
      expect(disc, findsOneWidget);
      await tester.tap(disc);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // The write is done and the read is out: the plus is still busy, so
      // there is nothing to tap for a second search.
      expect(lidarr.monitored, [13]);
      expect(lidarr.albumReads, greaterThan(reads));
      expect(disc, findsNothing);

      lidarr.albumsGate!.complete();
      await harness.settle(tester);
      expect(disc, findsOneWidget);
      expect(lidarr.monitored, [13]);

      await harness.unmount(tester);
    });

    testWidgets('a monitor that failed says so, with why', (tester) async {
      final lidarr = _Lidarr(searchAnswer: _catalog())
        ..monitorError = DioException(
          requestOptions: RequestOptions(path: '/api/v1/album/monitor'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/album/monitor'),
            statusCode: 400,
            data: {'message': 'Album not found'},
          ),
        );
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      await tester.tap(_disc('Electric Ladyland'));
      await harness.settle(tester);

      expect(
        find.textContaining('Could not monitor Electric Ladyland in Lidarr.'),
        findsOneWidget,
      );
      expect(find.textContaining('Album not found'), findsOneWidget);
      expect(lidarr.monitored, isEmpty);
      expect(
        find.text('Lidarr is looking for Electric Ladyland'),
        findsNothing,
      );

      await harness.unmount(tester);
    });

    testWidgets('an album by an artist the library lacks is added from its '
        'disc, with the artist', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      await tester.tap(_disc('Leaders of the Free World'));
      await harness.settle(tester);

      expect(find.byType(LidarrAddAlbumSheet), findsOneWidget);
      expect(
        find.textContaining('Your library doesn’t have Elbow yet.'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('an album that was added says so and opens nothing when '
        'the artist cannot be read after', (tester) async {
      final client = FakeApiClient()
        ..postResponseData = {'id': 40}
        ..getException = Exception('Lidarr went quiet');
      final (:harness, :router, :lidarr) = await _open(
        tester,
        overrides: [
          lidarrServiceForProvider.overrideWith(
            (ref, id) => LidarrService(client),
          ),
          lidarrAddOptionsProvider.overrideWith(
            (ref, id) async => const LidarrAddOptions(
              folders: [LidarrRootFolder(path: '/music')],
              qualityProfiles: [(id: 1, name: 'Lossless')],
              metadataProfiles: [
                LidarrMetadataProfile(id: 1, name: 'Standard'),
              ],
            ),
          ),
        ],
      );
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);
      await tester.tap(_disc('Leaders of the Free World'));
      await harness.settle(tester);

      await tester.tap(find.text('Add and search'));
      await harness.settle(tester);

      expect(client.postCallCount, 1);
      expect(find.byType(LidarrAddAlbumSheet), findsNothing);
      expect(
        find.text('Leaders of the Free World added to Lidarr'),
        findsOneWidget,
      );
      expect(find.textContaining('artist page'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/');

      await harness.unmount(tester);
    });

    testWidgets('an album by an artist the library holds opens the sheet '
        'with only the search to choose', (tester) async {
      final (:harness, :router, :lidarr) = await _open(tester);
      await _type(tester, harness, 'el');
      await _askLidarr(tester, harness);

      await tester.tap(find.text('Elegy for Brass'));
      await harness.settle(tester);

      expect(find.byType(LidarrAddAlbumSheet), findsOneWidget);
      expect(
        find.textContaining('Your library already has Edward Elgar.'),
        findsOneWidget,
      );
      expect(find.text('Folder'), findsNothing);
      expect(find.text('Search when added'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('while Lidarr is asked, a heading over four skeleton rows', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final lidarr = _Lidarr(searchAnswer: _catalog(), gate: gate);
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'elbo');
      await tester.tap(find.text('Lidarr'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Asking Lidarr'), findsOneWidget);
      expect(find.byType(ShimmerPlaceholder), findsNWidgets(12));

      gate.complete();
      await harness.settle(tester);
      expect(find.text('Asking Lidarr'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a catalog that did not answer is amber, keeps the library '
        'working and retries', (tester) async {
      final lidarr = _Lidarr(
        searchError: const LidarrCatalogUnavailable('LidarrAPI is down'),
      );
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'elbo');
      await _askLidarr(tester, harness);

      expect(
        find.textContaining(
          'Lidarr answered, but its music catalog on the internet did not. '
          'Your library still works.',
        ),
        findsOneWidget,
      );
      expect(lidarr.searched, ['elbo']);

      lidarr.searchError = null;
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);

      expect(lidarr.searched, ['elbo', 'elbo']);
      expect(
        find.textContaining('Lidarr answered, but its music catalog'),
        findsNothing,
      );

      await harness.unmount(tester);
    });

    testWidgets('nothing found says what Lidarr finds, and not songs', (
      tester,
    ) async {
      final (:harness, :router, :lidarr) = await _open(
        tester,
        lidarr: _Lidarr(searchAnswer: const []),
      );
      await _type(tester, harness, 'smells like');
      await _askLidarr(tester, harness);

      expect(
        find.text('Lidarr found nothing called “smells like”'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Lidarr finds artists and albums, not songs. Try the album the '
          'song is on, or the artist.',
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a Lidarr that did not answer is the app\'s own failure '
        'state, with Retry', (tester) async {
      final lidarr = _Lidarr(
        searchError: DioException(
          requestOptions: RequestOptions(path: '/api/v1/search'),
          type: DioExceptionType.connectionError,
        ),
      );
      final (:harness, :router, lidarr: _) = await _open(
        tester,
        lidarr: lidarr,
      );
      await _type(tester, harness, 'elbo');
      await _askLidarr(tester, harness);

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Lidarr did not answer'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  testWidgets('a link that means Lidarr\'s own search lands on it', (
    tester,
  ) async {
    final (:harness, :router, :lidarr) = await _open(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MusicScreen)),
    );

    container.read(musicFindScopeProvider.notifier).state =
        MediaFindScope.service;
    container.read(musicSearchQueryProvider.notifier).state = 'elbow';
    await harness.settle(tester);

    expect(lidarr.searched, ['elbow']);
    expect(find.text('Elbow'), findsOneWidget);
    expect(find.byType(MusicFindLidarr), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('text at 200% fits without overflow in both scopes', (
    tester,
  ) async {
    final (:harness, :router, :lidarr) = await _open(tester, textScale: 2);

    await _type(tester, harness, 'el');
    expect(tester.takeException(), isNull);
    await _askLidarr(tester, harness);
    expect(tester.takeException(), isNull);

    await harness.unmount(tester);
  });
}
