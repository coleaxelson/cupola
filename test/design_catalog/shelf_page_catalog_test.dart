@Tags(['catalog'])
library;

import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/music/presentation/artist_type_pills.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_album_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/artist_page_providers.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/author_page.dart';
import 'package:cupola/features/readarr/presentation/author_page_providers.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Each catalog picture's light, as the app reads it.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.poster, 'poster'),
    (CatalogArt.backdrop, 'backdrop'),
  ]) {
    final bytes = io.File(
      'design/system/assets/Imagery/$file.jpg',
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: titleLightDecodeSize,
      targetHeight: titleLightDecodeSize,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData())!;
    _lights[url] = await titleLightFromPixels([
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        0xFF000000 |
            rgba.getUint8(i) << 16 |
            rgba.getUint8(i + 1) << 8 |
            rgba.getUint8(i + 2),
    ]);
  }
}

ServiceInstance _connection(ServiceKey service) => ServiceInstance(
  id: service.name,
  service: service,
  label: '',
  url: 'http://nas.home.arpa',
  credential: 'catalog',
);

/// The profiles' Lidarr and Readarr answer their quality profiles; nothing
/// else is asked of them here.
class _Lidarr extends LidarrService {
  _Lidarr() : super(FakeApiClient());

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': 1, 'name': 'Lossless'},
    {'id': 2, 'name': 'Standard'},
  ];
}

class _Readarr extends ReadarrService {
  _Readarr() : super(FakeApiClient());

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': 1, 'name': 'eBook'},
    {'id': 2, 'name': 'Spoken'},
  ];
}

List<Object?> _cover(String url) => [
  {'coverType': 'cover', 'remoteUrl': url},
];

LidarrArtist _artist() => LidarrArtist.fromJson({
  'id': 1,
  'artistName': 'Jan Morgenstern',
  'foreignArtistId': 'jm',
  'status': 'continuing',
  'monitored': true,
  'monitorNewItems': 'all',
  'path': '/mnt/tank/media/music/Jan Morgenstern',
  'qualityProfileId': 1,
  'images': const <Object?>[],
  'statistics': {'albumCount': 4, 'trackFileCount': 18, 'trackCount': 23},
});

List<LidarrAlbum> _albums({bool art = true, bool wanted = false}) => [
  for (final (id, title, year, files, total, url) in [
    (3, 'Sintel', 2010, 5, 5, CatalogArt.poster),
    (2, 'Big Buck Bunny', 2008, 6, 6, CatalogArt.backdrop),
    (1, 'Elephants Dream', 2006, wanted ? 0 : 7, 7, CatalogArt.poster),
  ])
    LidarrAlbum.fromJson({
      'id': id,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'duration': id == 3 ? 1260000 : 0,
      'images': art ? _cover(url) : const <Object?>[],
      'statistics': {'trackFileCount': files, 'totalTrackCount': total},
    }),
  LidarrAlbum.fromJson({
    'id': 4,
    'title': 'Sintel (Anniversary Edition)',
    'monitored': true,
    'releaseDate': catalogNow
        .add(const Duration(days: 3))
        .toUtc()
        .toIso8601String(),
    'images': art ? _cover(CatalogArt.backdrop) : const <Object?>[],
    'statistics': {'trackFileCount': 0, 'totalTrackCount': 5},
  }),
];

final _tracks = [
  for (final (number, title, ms) in [
    (1, 'Opening', 168000),
    (2, 'Scales', 252000),
    (3, 'The Dragon', 336000),
    (4, 'Snow', 234000),
    (5, 'Finale', 270000),
  ])
    LidarrTrack.fromJson({
      'id': number,
      'trackNumber': '$number',
      'title': title,
      'duration': ms,
      'hasFile': true,
    }),
];

/// Jan Morgenstern's nine albums by kind, as the board draws them: three
/// soundtracks, four singles (two wanted, one on disk, one left alone), an EP
/// and an album announced.
List<LidarrAlbum> _kindAlbums() => [
  for (final (id, title, type, secondary, year, files, total, url, monitored)
      in [
        (
          11,
          'Elephants Dream',
          'Album',
          ['Soundtrack'],
          2006,
          7,
          7,
          CatalogArt.poster,
          true,
        ),
        (
          12,
          'Big Buck Bunny',
          'Album',
          ['Soundtrack'],
          2008,
          6,
          6,
          CatalogArt.backdrop,
          true,
        ),
        (
          13,
          'Sintel',
          'Album',
          ['Soundtrack', 'Studio'],
          2010,
          5,
          5,
          CatalogArt.poster,
          true,
        ),
        (
          14,
          'The Dragon',
          'Single',
          <String>[],
          2010,
          0,
          1,
          CatalogArt.poster,
          true,
        ),
        (
          15,
          'Snow',
          'Single',
          <String>[],
          2010,
          0,
          1,
          CatalogArt.backdrop,
          true,
        ),
        (
          16,
          'Finale',
          'Single',
          <String>[],
          2010,
          1,
          1,
          CatalogArt.poster,
          true,
        ),
        (
          17,
          'Caminandes',
          'Single',
          <String>[],
          2013,
          0,
          1,
          CatalogArt.backdrop,
          false,
        ),
        (18, 'Spring', 'EP', <String>[], 2019, 3, 3, CatalogArt.poster, true),
        (
          19,
          'Tears of Steel',
          'Album',
          <String>[],
          2012,
          9,
          9,
          CatalogArt.backdrop,
          true,
        ),
      ])
    LidarrAlbum.fromJson({
      'id': id,
      'title': title,
      'albumType': type,
      'secondaryTypes': secondary,
      'monitored': monitored,
      'releaseDate': '$year-01-01T00:00:00Z',
      'duration': id == 16 ? 270000 : 0,
      'images': _cover(url),
      'statistics': {'trackFileCount': files, 'totalTrackCount': total},
    }),
];

/// The tracks Lidarr lists for those albums: the soundtrack's Dragon, and the
/// single that shares its name.
final _kindTracks = [
  LidarrTrack.fromJson({
    'id': 1301,
    'albumId': 13,
    'trackNumber': '3',
    'title': 'The Dragon',
    'duration': 336000,
    'hasFile': true,
  }),
  LidarrTrack.fromJson({
    'id': 1401,
    'albumId': 14,
    'trackNumber': '1',
    'title': 'The Dragon',
    'duration': 0,
    'hasFile': false,
  }),
  LidarrTrack.fromJson({
    'id': 1501,
    'albumId': 15,
    'trackNumber': '1',
    'title': 'Snow',
    'duration': 234000,
    'hasFile': false,
  }),
  LidarrTrack.fromJson({
    'id': 1601,
    'albumId': 16,
    'trackNumber': '1',
    'title': 'Finale',
    'duration': 270000,
    'hasFile': true,
  }),
];

/// Taps `Find a track` or the lens in [scene], and types [query] into the
/// field it opens.
Future<void> _findTrack(WidgetTester tester, Finder scene, String query) async {
  final lens = find.descendant(
    of: scene,
    matching: find.byType(ArtistFindLens),
  );
  await tester.tap(
    lens.evaluate().isEmpty
        ? find.descendant(of: scene, matching: find.text('Find a track'))
        : lens,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.enterText(
    find.descendant(of: scene, matching: find.byType(EditableText)),
    query,
  );
}

CatalogScene _artistScene(
  String caption, {
  List<LidarrAlbum>? albums,
  CatalogPlatform platform = CatalogPlatform.phone,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
  double width = 390,
  double height = 1700,
  double textScale = 1,
  bool art = true,
  bool wanted = false,
  bool justAdded = false,
  Future<LidarrArtist>? artist,
}) => CatalogScene(
  caption,
  (_) => ArtistPage(artistId: 1, justAdded: justAdded),
  width: width,
  height: height,
  platform: platform,
  textScale: textScale,
  act: act,
  overrides: [
    lidarrArtistTracksProvider.overrideWith(
      (ref, item) async => albums == null ? const [] : _kindTracks,
    ),
    lidarrServiceProvider.overrideWithValue(_Lidarr()),
    lidarrArtistProvider.overrideWith((ref, item) => artist ?? _artist()),
    lidarrArtistAlbumsProvider.overrideWith(
      // Lidarr has taken the artist and not read its albums yet.
      (ref, item) async => justAdded
          ? const <LidarrAlbum>[]
          : albums ?? _albums(art: art, wanted: wanted),
    ),
    lidarrAlbumTracksProvider.overrideWith((ref, album) async => _tracks),
    lidarrQueueSnapshotsForProvider.overrideWith(
      (ref, id) async => LidarrQueueSnapshots.empty,
    ),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
  ],
);

/// An artist the lookup found and no Lidarr holds: no id, no artwork.
LidarrArtist _lookupElbow() => LidarrArtist.fromJson({
  'artistName': 'Elbow',
  'foreignArtistId': 'mbid-elbow',
  'status': 'continuing',
  'artistType': 'Group',
  'disambiguation': 'Bury, England',
  'overview':
      'English rock band formed in Bury in 1997, led by Guy Garvey. Their '
      'albums have been shortlisted for the Mercury Prize five times.',
  'images': const <Object?>[],
});

const _addOptions = LidarrAddOptions(
  folders: [
    LidarrRootFolder(
      path: '/music',
      freeSpace: 2308974418944,
      defaultQualityProfileId: 1,
      defaultMetadataProfileId: 1,
      defaultMonitor: null,
      defaultNewItemMonitor: 'all',
    ),
  ],
  qualityProfiles: [(id: 1, name: 'Lossless'), (id: 2, name: 'Standard')],
  metadataProfiles: [
    LidarrMetadataProfile(
      id: 1,
      name: 'Standard',
      allowedPrimaryTypes: ['Album', 'EP'],
    ),
  ],
);

/// A Lidarr that refuses the add, as it refuses an artist it already holds.
class _RefusingLidarr extends LidarrService {
  _RefusingLidarr([String message = 'This artist has already been added'])
    : super(FakeApiClient()) {
    (client as FakeApiClient).postException = DioException.badResponse(
      statusCode: 400,
      requestOptions: RequestOptions(path: '/api/v1/artist'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/artist'),
        statusCode: 400,
        data: [
          {'errorMessage': message},
        ],
      ),
    );
  }
}

/// The sheet as it stands open: the room under the modal barrier, and the
/// panel risen from the bottom edge.
Widget _sheetOpen(Widget body) => Builder(
  builder: (context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Theme.of(context).colorScheme.surface),
      ColoredBox(color: CupolaRoom.of(context).scrim),
      Align(
        alignment: Alignment.bottomCenter,
        child: AppBottomSheet(child: body),
      ),
    ],
  ),
);

String _lidarrName(ServiceInstance connection) =>
    connection.label.isEmpty ? 'Lidarr' : 'Lidarr \u00B7 ${connection.label}';

CatalogScene _addArtistScene(
  String caption, {
  List<ServiceInstance>? connections,
  Future<LidarrAddOptions> Function()? options,
  bool refused = false,
  double height = 844,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => _sheetOpen(
    LidarrAddArtistSheet(
      artist: _lookupElbow(),
      connections: connections ?? [_connection(ServiceKey.lidarr)],
      name: _lidarrName,
    ),
  ),
  width: 390,
  height: height,
  textScale: textScale,
  overrides: [
    lidarrAddOptionsProvider.overrideWith(
      (ref, id) => (options ?? () async => _addOptions)(),
    ),
    if (refused)
      lidarrServiceForProvider.overrideWith((ref, id) => _RefusingLidarr()),
  ],
  act: refused
      ? (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.byType(FilledButton)),
          );
        }
      : null,
);

/// An album the catalog found by a band the library has not got.
LidarrAlbumHit _elephantHit() {
  final raw = <String, dynamic>{
    'id': 0,
    'title': 'Elephant',
    'foreignAlbumId': 'mbid-elephant',
    'albumType': 'Album',
    'releaseDate': '2003-04-14T00:00:00Z',
    'monitored': false,
    'images': const <Object?>[],
    'artist': {
      'id': 0,
      'artistName': 'The White Stripes',
      'foreignArtistId': 'mbid-stripes',
      'artistType': 'Group',
      'status': 'continuing',
      'monitored': false,
      'images': const <Object?>[],
      'genres': const <Object?>[],
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

/// The options a Lidarr that kept its own `None` profile offers.
const _albumOptions = LidarrAddOptions(
  folders: [
    LidarrRootFolder(
      path: '/music',
      freeSpace: 2308974418944,
      defaultQualityProfileId: 1,
      defaultMetadataProfileId: 1,
      defaultNewItemMonitor: 'all',
    ),
  ],
  qualityProfiles: [(id: 1, name: 'Lossless'), (id: 2, name: 'Standard')],
  metadataProfiles: [
    LidarrMetadataProfile(
      id: 1,
      name: 'Standard',
      allowedPrimaryTypes: ['Album', 'EP'],
    ),
    LidarrMetadataProfile(id: 2, name: 'None'),
  ],
);

CatalogScene _addAlbumScene(
  String caption, {
  bool held = false,
  bool refused = false,
  double height = 760,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => _sheetOpen(
    LidarrAddAlbumSheet(
      hit: _elephantHit(),
      connection: _connection(ServiceKey.lidarr),
      connectionName: 'Lidarr',
      libraryArtist: held ? _artist() : null,
    ),
  ),
  width: 390,
  height: height,
  textScale: textScale,
  overrides: [
    lidarrAddOptionsProvider.overrideWith((ref, id) async => _albumOptions),
    if (refused)
      lidarrServiceForProvider.overrideWith(
        (ref, id) => _RefusingLidarr('This album has already been added'),
      ),
  ],
  act: refused
      ? (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.byType(FilledButton)),
          );
        }
      : null,
);

ReadarrAuthor _author() => ReadarrAuthor.fromJson({
  'id': 1,
  'authorName': 'Jules Verne',
  'titleSlug': 'jules-verne',
  'monitored': true,
  'path': '/mnt/user/media/books/Jules Verne',
  'qualityProfileId': 1,
  'images': const <Object?>[],
  'statistics': {'bookCount': 7, 'bookFileCount': 6},
});

final _books = [
  for (final (id, title, year, onDisk) in const [
    (1, 'Five Weeks in a Balloon', 1863, false),
    (2, 'Journey to the Centre of the Earth', 1864, true),
    (3, 'From the Earth to the Moon', 1865, true),
    (4, 'Twenty Thousand Leagues Under the Seas', 1870, true),
    (5, 'Around the World in Eighty Days', 1872, true),
    (6, 'The Mysterious Island', 1875, true),
    (7, 'Michael Strogoff', 1876, true),
  ])
    ReadarrBook.fromJson({
      'id': id,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'statistics': {'bookFileCount': onDisk ? 1 : 0},
    }),
];

CatalogScene _authorScene(
  String caption, {
  double height = 1500,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => const AuthorPage(authorId: 1),
  width: 390,
  height: height,
  textScale: textScale,
  overrides: [
    readarrServiceProvider.overrideWithValue(_Readarr()),
    readarrAuthorProvider.overrideWith((ref, item) async => _author()),
    readarrAuthorBooksProvider.overrideWith((ref, item) async => _books),
    readarrQueueSnapshotForProvider.overrideWith(
      (ref, id) async => ArrQueueSnapshot.empty,
    ),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
  ],
);

/// The catalog's TMDB pictures, lit as the app lights them.
Future<TitleLight?> _tmdbLight(String url) async =>
    _lights[url.contains(CatalogArt.tmdbBackdrop)
        ? CatalogArt.backdrop
        : url.contains(CatalogArt.tmdbPoster)
        ? CatalogArt.poster
        : url];

Map<String, Object?> _directed(
  int id,
  String title,
  String date, {
  String type = 'movie',
  int? status,
  bool art = false,
}) => {
  'id': id,
  'mediaType': type,
  if (type == 'tv') 'name': title else 'title': title,
  type == 'tv' ? 'firstAirDate' : 'releaseDate': date,
  'voteAverage': type == 'tv' ? null : 6.6,
  'posterPath': art ? CatalogArt.tmdbPoster : null,
  'job': 'Director',
  'department': 'Directing',
  if (status != null) 'mediaInfo': {'status': status, 'status4k': 5},
};

CatalogScene _personScene(
  String caption, {
  double width = 390,
  double height = 1100,
  double textScale = 1,
  bool seerrSends = true,
  bool paned = false,
}) => CatalogScene(
  caption,
  (_) => paned
      ? MediaPane(
          canGoBack: false,
          onBack: () {},
          child: const PersonPage(personId: 1),
        )
      : const PersonPage(personId: 1),
  width: width,
  height: height,
  textScale: textScale,
  overrides: [
    personDetailProvider.overrideWith(
      (ref, id) async => const PersonDetail(
        id: 1,
        name: 'Ian Hubert',
        knownForDepartment: 'Directing',
        biography:
            'Filmmaker and visual effects artist, known for short films made '
            'with free software and for the lazy tutorials.',
        placeOfBirth: 'Seattle, Washington, USA',
      ),
    ),
    personCreditsProvider.overrideWith(
      (ref, id) async => PersonCombinedCredits.fromJson({
        'crew': [
          _directed(1, 'Dynamo Dream', '2019-02-01', type: 'tv'),
          _directed(2, 'Tears of Steel', '2012-09-26', status: 5, art: true),
          _directed(3, 'Project London', '2011-06-01'),
        ],
      }),
    ),
    seerrNumberingProvider.overrideWith((ref) async => null),
    seerrSendsToProvider.overrideWith((ref, arr) async => seerrSends),
    seriesForProvider.overrideWith((ref, id) async => const []),
    titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
  ],
);

CatalogScene _collectionScene(String caption, {double height = 1700}) =>
    CatalogScene(
      caption,
      (_) => const CollectionPage(collectionId: 1),
      width: 390,
      height: height,
      overrides: [
        collectionDetailProvider.overrideWith(
          (ref, id) async => CollectionDetail(
            id: 1,
            name: 'Blender Open Movies',
            backdropPath: CatalogArt.tmdbBackdrop,
            parts: [
              for (final (id, title, year, status) in const [
                (1, 'Elephants Dream', 2006, 5),
                (2, 'Big Buck Bunny', 2008, 3),
                (3, 'Sintel', 2010, 5),
                (4, 'Tears of Steel', 2012, 5),
                (5, 'Spring', 2019, 5),
                (6, 'Coffee Run', 2020, 5),
                (7, 'Sprite Fright', 2021, 3),
                (8, 'Charge', 2022, 2),
              ])
                MediaPreview(
                  id: id,
                  title: title,
                  mediaType: 'movie',
                  releaseDate: '$year-04-10',
                  voteAverage: 7.4,
                  posterPath: CatalogArt.tmdbPoster,
                  mediaInfo: {'status': status},
                ),
            ],
          ),
        ),
        seerrNumberingProvider.overrideWith((ref) async => null),
        activeRequestsForProvider.overrideWith((ref, id) async => const []),
        titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLights);
  catalogCard(
    'ShelfPage',
    width: 1240,
    overrides: () => settingsScopeOverrides(
      // Seerr and Sonarr for the person and the collection, Radarr not.
      customize: (settings) => [
        _connection(ServiceKey.lidarr),
        _connection(ServiceKey.readarr),
        _connection(ServiceKey.seerr),
        _connection(ServiceKey.sonarr),
      ].fold(settings, (s, c) => s.copyWithInstance(c)),
    ),
    scenes: [
      _artistScene(
        'ArtistPage · lit by the first cover; announced, on disk, the '
        'settings and the way to Lidarr',
      ),
      _artistScene(
        'ArtistPage · no artwork: the initials, the plates, the lamp; one '
        'album wanted',
        art: false,
        wanted: true,
      ),
      _artistScene(
        'ArtistPage · albums by kind, Singles chosen: the pills with their '
        'counts, Wanted and On disk recounted, the unmonitored line in the '
        'kind\u2019s words, the summary still the artist\u2019s whole',
        albums: _kindAlbums(),
        height: 1500,
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Singles 4')),
          );
        },
      ),
      _artistScene(
        'ArtistPage · find a track: the field with Done, the tracks the words '
        'typed open, the prefix marked, each with its album and where it '
        'stands; a track never contradicts its album',
        albums: _kindAlbums(),
        height: 760,
        act: (tester, scene) => _findTrack(tester, scene, 'the drag'),
      ),
      _artistScene(
        'ArtistPage · find a track, nothing found: what was asked and what '
        'Lidarr knows',
        albums: _kindAlbums(),
        height: 620,
        act: (tester, scene) => _findTrack(tester, scene, 'zebra'),
      ),
      _artistScene(
        'ArtistPage · one kind of album: no pills, and a quiet Find a track '
        'in their place',
        height: 1000,
      ),
      CatalogScene(
        'ShelfWorkRow · open on its tracks (AlbumTracks): a complete album '
        'asks for no search',
        (_) => MediaGroup(
          children: [
            ShelfWorkRow(
              initiallyOpen: true,
              cover: const ShelfCover(
                art: (url: CatalogArt.poster, headers: null),
                size: Size.square(64),
                fallback: SizedBox.shrink(),
              ),
              title: 'Sintel',
              facts: '2010 · 5 tracks · 21\u00A0min',
              state: (
                word: 'Complete',
                tone: StatusTone.success,
                hollow: false,
              ),
              spoken: 'Sintel',
              body: (context) => AlbumTracks(
                album: _albums().first,
                record: (instanceId: 'lidarr', id: 3),
                searching: false,
                onSearch: null,
                onSearchReleases: () {},
              ),
            ),
          ],
        ),
        width: 390,
        height: 470,
        overrides: [
          lidarrAlbumTracksProvider.overrideWith((ref, album) async => _tracks),
        ],
      ),
      _authorScene(
        'AuthorPage · Readarr retired, said once; the books by year, the '
        'wanted one dashed and searched for from its card',
      ),
      _personScene(
        'PersonPage · a director by Seerr\'s credits: the role, one dot per '
        'title, the plus to Sonarr, Request where Seerr sends a movie to its '
        'Radarr, then who they are and where the credits come from',
      ),
      _personScene(
        'PersonPage where nothing set up can add a movie · the plus stays, '
        'dimmed',
        height: 760,
        seerrSends: false,
      ),
      _collectionScene(
        'CollectionPage (ShelfPage.banner) · the still lights the room; how '
        'much is on the server, the strip, the movies in release order',
      ),
      _personScene(
        'PersonPage in a tablet\'s pane, opened from a list · Close, and the '
        'light coming up from the list\'s side',
        width: 660,
        height: 820,
        paned: true,
      ),
      _personScene(
        'PersonPage at twice the reading size',
        height: 2000,
        textScale: catalogTextScale,
      ),
      _artistScene(
        'ArtistPage at twice the reading size · the name under the disc, the '
        'value under its label',
        height: 2600,
        textScale: catalogTextScale,
      ),
      _artistScene(
        'ArtistPage at twice the reading size, with the pills: the rail '
        'scrolls and fades at its end, the lens stays at the row\u2019s end',
        albums: _kindAlbums(),
        height: 3200,
        textScale: catalogTextScale,
      ),
      _authorScene(
        'AuthorPage at twice the reading size · two books to a row',
        height: 3000,
        textScale: catalogTextScale,
      ),
      _addArtistScene(
        'LidarrAddArtistSheet · the folder\u2019s defaults loaded: the folder '
        'with its room, the profiles, Monitor and its meaning, the two '
        'switches, the button that says it searches',
      ),
      _addArtistScene(
        'LidarrAddArtistSheet · two connections: the pills over the rows',
        connections: [
          _connection(ServiceKey.lidarr),
          const ServiceInstance(
            id: 'lidarr-away',
            service: ServiceKey.lidarr,
            label: 'Away',
            url: 'https://lidarr.example.net',
            credential: 'catalog',
          ),
        ],
        height: 900,
      ),
      _addArtistScene(
        'LidarrAddArtistSheet · the options could not be read: who did not '
        'answer, Retry, and nothing to add yet',
        options: () => Future<LidarrAddOptions>.error(
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/rootfolder'),
            reason: 'down',
          ),
        ),
        height: 520,
      ),
      _addArtistScene(
        'LidarrAddArtistSheet · a Lidarr with no root folder: what is true, '
        'what to do, the way to Lidarr, and no button',
        options: () async => const LidarrAddOptions(
          folders: [],
          qualityProfiles: [(id: 1, name: 'Lossless')],
          metadataProfiles: [],
        ),
        height: 520,
      ),
      _addArtistScene(
        'LidarrAddArtistSheet · Lidarr refused the add: it stays, in '
        'Lidarr\u2019s own words, over the button',
        refused: true,
      ),
      _addArtistScene(
        'LidarrAddArtistSheet at twice the reading size',
        height: 1900,
        textScale: catalogTextScale,
      ),
      _addAlbumScene(
        'LidarrAddAlbumSheet · an artist the library has not got: the album '
        'with its cover, the blue line that says the library does not have '
        'them, that they come in too and that only this album is monitored, '
        'the folder and the profiles for them (the folder\u2019s defaults), '
        'the search',
      ),
      _addAlbumScene(
        'LidarrAddAlbumSheet · an artist the library holds: the line says '
        'so, and the search is all there is to choose',
        held: true,
        height: 460,
      ),
      _addAlbumScene(
        'LidarrAddAlbumSheet · Lidarr refused the add: it stays, in '
        'Lidarr\u2019s own words, over the button',
        refused: true,
        height: 860,
      ),
      _addAlbumScene(
        'LidarrAddAlbumSheet at twice the reading size',
        height: 2000,
        textScale: catalogTextScale,
      ),
      _artistScene(
        'ArtistPage right after the add · Added just now, Lidarr reading '
        'the albums over three rows that are not there yet',
        height: 760,
        justAdded: true,
        artist: Future.value(
          LidarrArtist.fromJson({
            'id': 12,
            'artistName': 'Elbow',
            'foreignArtistId': 'mbid-elbow',
            'status': 'continuing',
            'monitored': true,
            'monitorNewItems': 'all',
            'path': '/music/Elbow',
            'qualityProfileId': 1,
            'images': const <Object?>[],
          }),
        ),
      ),
      _artistScene(
        'Reading the artist · nothing to show yet',
        height: 700,
        artist: Completer<LidarrArtist>().future,
      ),
      _artistScene(
        'A wide window · the phone\'s column, centred',
        width: 1240,
        height: 1700,
      ),
      _artistScene(
        'ArtistPage on the desktop shell · the pills with the lens at the '
        'row\u2019s end, Singles chosen',
        albums: _kindAlbums(),
        platform: CatalogPlatform.desktop,
        width: 1240,
        height: 1500,
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Singles 4')),
          );
        },
      ),
      _artistScene(
        'ArtistPage on the desktop shell · find a track',
        albums: _kindAlbums(),
        platform: CatalogPlatform.desktop,
        width: 1240,
        height: 900,
        act: (tester, scene) => _findTrack(tester, scene, 'the drag'),
      ),
    ],
  );
}
