/// The sheet that adds one album to Lidarr: its two shapes (an artist the
/// library lacks, an artist it holds), its states, and what it posts.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_album_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

const _lidarr = ServiceInstance(
  id: 'lidarr',
  service: ServiceKey.lidarr,
  url: 'https://lidarr.test',
  credential: 'key',
);

const _standard = LidarrMetadataProfile(
  id: 1,
  name: 'Standard',
  allowedPrimaryTypes: ['Album', 'EP'],
);

const _none = LidarrMetadataProfile(id: 7, name: 'None');

LidarrAddOptions _options({
  List<LidarrMetadataProfile> metadata = const [_standard, _none],
  List<LidarrRootFolder>? folders,
}) => LidarrAddOptions(
  folders:
      folders ??
      const [
        LidarrRootFolder(
          path: '/music',
          freeSpace: 2308974418944,
          defaultQualityProfileId: 2,
          defaultMetadataProfileId: 1,
          defaultNewItemMonitor: 'all',
        ),
      ],
  qualityProfiles: const [(id: 1, name: 'Lossless'), (id: 2, name: 'Any')],
  metadataProfiles: metadata,
);

LidarrAlbumHit _hit({String artistType = 'Group'}) {
  final raw = <String, dynamic>{
    'id': 0,
    'title': 'Elephant',
    'foreignAlbumId': 'mb-elephant',
    'albumType': 'Album',
    'releaseDate': '2003-04-14T00:00:00Z',
    'monitored': false,
    'images': const <Object?>[],
    'artist': {
      'id': 0,
      'artistName': 'The White Stripes',
      'foreignArtistId': 'mb-stripes',
      'artistType': artistType,
      'status': 'continuing',
      'monitored': false,
      'images': const <Object?>[],
    },
  };
  return LidarrAlbumHit(
    album: LidarrAlbum.fromJson(raw),
    artist: LidarrArtist.fromJson(
      (raw['artist'] as Map).cast<String, dynamic>(),
    ),
    raw: raw,
  );
}

LidarrArtist _held() => LidarrArtist.fromJson({
  'id': 7,
  'artistName': 'The White Stripes',
  'foreignArtistId': 'mb-stripes',
  'status': 'continuing',
  'monitored': true,
  'images': const <Object?>[],
});

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final client = FakeApiClient()
    ..postResponseData = {
      'id': 40,
      'artist': {
        'id': 12,
        'artistName': 'The White Stripes',
        'foreignArtistId': 'mb-stripes',
        'status': 'continuing',
        'monitored': true,
        'images': const <Object?>[],
      },
    };

  LidarrAddedAlbum? added;
  var closed = false;

  Future<void> open({
    LidarrAddOptions? options,
    LidarrArtist? libraryArtist,
    LidarrAlbumHit? hit,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings.copyWithInstance(_lidarr),
    );
    tester.view
      ..physicalSize = const Size(390, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          lidarrAddOptionsProvider.overrideWith(
            (ref, id) async => options ?? _options(),
          ),
          lidarrServiceForProvider.overrideWith(
            (ref, id) => LidarrService(client),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    added = await showLidarrAddAlbumSheet(
                      context,
                      hit: hit ?? _hit(),
                      connection: _lidarr,
                      connectionName: 'Lidarr',
                      libraryArtist: libraryArtist,
                    );
                    closed = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAdd() async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  Map<dynamic, dynamic> get posted => client.lastPostData as Map;
}

Switch _searchSwitch(WidgetTester tester) => tester.widget<Switch>(
  find.descendant(
    of: find
        .ancestor(
          of: find.text('Search when added'),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(Switch),
  ),
);

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('an artist the library lacks', () {
    testWidgets('the head names the album, who it is by, when and what '
        'kind', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      expect(find.text('Elephant'), findsOneWidget);
      expect(
        find.text('The White Stripes\u00A0· 2003\u00A0· Album'),
        findsOneWidget,
      );
    });

    testWidgets('says that the artist comes in too, and only this album '
        'is monitored', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      expect(
        find.textContaining('Your library doesn’t have The White Stripes yet.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Lidarr adds them too, and monitors only this'),
        findsOneWidget,
      );
    });

    testWidgets('asks for the folder, the profiles and the search, on the '
        'folder\'s defaults', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('/music'), findsOneWidget);
      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Metadata profile'), findsOneWidget);
      // The folder's default profile, not Lidarr's `None`: the rest of the
      // discography then arrives unmonitored.
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('None'), findsNothing);
      expect(find.text('Search when added'), findsOneWidget);
      expect(find.text('Lidarr looks for Elephant right away'), findsOneWidget);
      expect(find.text('Monitor'), findsNothing);
      expect(find.text('Monitor new albums'), findsNothing);
    });

    testWidgets('the button follows the search: Add and search, or Add to '
        'the connection', (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      expect(_buttonLabel(tester), 'Add and search');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(_searchSwitch(tester).value, isFalse);
      expect(_buttonLabel(tester), 'Add to Lidarr');
    });

    testWidgets('posts the album with its artist, monitoring that album and '
        'no other', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      await harness.tapAdd();

      expect(harness.client.lastPostPath, '/api/v1/album');
      expect(harness.posted['monitored'], isTrue);
      expect(harness.posted['addOptions'], {'searchForNewAlbum': true});
      final artist = harness.posted['artist'] as Map;
      expect(artist['rootFolderPath'], '/music');
      expect(artist['qualityProfileId'], 2);
      expect(artist['metadataProfileId'], 1);
      expect(artist['monitorNewItems'], 'none');
      expect(artist['addOptions'], {
        'monitor': 'none',
        'albumsToMonitor': ['mb-elephant'],
        'searchForMissingAlbums': false,
      });
      expect(harness.closed, isTrue);
      expect(harness.added!.artist!.id, 12);
      expect(harness.added!.connection.id, 'lidarr');
    });

    testWidgets('search off posts searchForNewAlbum false', (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await harness.tapAdd();

      expect(harness.posted['addOptions'], {'searchForNewAlbum': false});
    });

    testWidgets('another metadata profile is the person\'s choice, and the '
        'same album is the one monitored', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      await tester.tap(find.text('Metadata profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await harness.tapAdd();

      final artist = harness.posted['artist'] as Map;
      expect(artist['metadataProfileId'], 7);
      expect((artist['addOptions'] as Map)['monitor'], 'none');
      expect((artist['addOptions'] as Map)['albumsToMonitor'], ['mb-elephant']);
    });

    testWidgets('an album that was added closes the sheet, though the artist '
        'could not be read after', (tester) async {
      final harness = _Harness(tester);
      harness.client
        ..postResponseData = {'id': 40}
        ..getException = Exception('Lidarr went quiet');
      await harness.open();

      await harness.tapAdd();

      expect(harness.closed, isTrue);
      expect(harness.added!.artist, isNull);
      expect(find.textContaining('Could not add'), findsNothing);
    });

    testWidgets('a refusal stays in the sheet, in Lidarr\'s words', (
      tester,
    ) async {
      final harness = _Harness(tester);
      harness.client.postException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/album'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v1/album'),
          statusCode: 400,
          data: [
            {'errorMessage': 'This album has already been added'},
          ],
        ),
      );
      await harness.open();

      await harness.tapAdd();

      expect(find.text('Could not add Elephant to Lidarr.'), findsOneWidget);
      expect(find.text('This album has already been added'), findsOneWidget);
      expect(harness.closed, isFalse);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('a Lidarr with no root folder says so and offers no add', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open(options: _options(folders: const []));

      expect(find.text('Lidarr has no root folder yet.'), findsOneWidget);
      expect(find.text('Add one in Lidarr, then come back.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('text at 200% fits without overflow', (tester) async {
      final harness = _Harness(tester);
      await harness.open(textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('an artist the library holds', () {
    testWidgets('says they are in the library, and offers only the search', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open(libraryArtist: _held());

      expect(
        find.textContaining('Your library already has The White Stripes.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Lidarr adds this album and monitors it.'),
        findsOneWidget,
      );
      expect(find.text('Folder'), findsNothing);
      expect(find.text('Quality profile'), findsNothing);
      expect(find.text('Metadata profile'), findsNothing);
      expect(find.text('Search when added'), findsOneWidget);
      expect(_buttonLabel(tester), 'Add and search');
    });

    testWidgets('reads no options: nothing is chosen that Lidarr already '
        'knows', (tester) async {
      final harness = _Harness(tester);
      harness.client.getResponseData = {
        'id': 7,
        'artistName': 'The White Stripes',
        'path': '/music/The White Stripes',
        'status': 'continuing',
        'monitored': true,
        'images': const <Object?>[],
      };
      await harness.open(libraryArtist: _held());

      await harness.tapAdd();

      // The artist as the library holds them goes with the album.
      expect(harness.client.lastGetPath, '/api/v1/artist/7');
      expect(
        (harness.posted['artist'] as Map)['path'],
        '/music/The White Stripes',
      );
      expect(harness.posted['addOptions'], {'searchForNewAlbum': true});
      expect(harness.closed, isTrue);
    });
  });
}
