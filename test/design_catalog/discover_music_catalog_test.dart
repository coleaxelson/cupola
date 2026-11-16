@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/more_from_your_artists_page.dart';
import 'package:cupola/features/discover/presentation/widgets/more_from_your_artists_shelf.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/domain/more_from_your_artists.dart';
import 'package:cupola/features/music/domain/music_held.dart';
import 'package:cupola/features/music/presentation/more_from_your_artists_provider.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/discover_music_provider.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'calendar_world.dart';
import 'catalog.dart';

/// The light of the catalog's poster, as the app reads it, for the lit covers.
TitleLight? _light;

Future<void> _readLight() async {
  final bytes = io.File(
    'design/system/assets/Imagery/poster.jpg',
  ).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: titleLightDecodeSize,
    targetHeight: titleLightDecodeSize,
  );
  final frame = await codec.getNextFrame();
  final rgba = (await frame.image.toByteData())!;
  _light = await titleLightFromPixels([
    for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
      0xFF000000 |
          rgba.getUint8(i) << 16 |
          rgba.getUint8(i + 1) << 8 |
          rgba.getUint8(i + 2),
  ]);
}

List<Object?> _cover(String url) => [
  {'coverType': 'cover', 'remoteUrl': url},
];

LidarrArtist _artist(
  int id,
  String name, {
  String foreign = '',
  String? type,
  String? disambiguation,
}) => LidarrArtist(
  id: id,
  artistName: name,
  foreignArtistId: foreign.isEmpty ? 'mb-$id' : foreign,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  artistType: type,
  disambiguation: disambiguation,
);

LidarrAlbum _album(
  int id,
  String title,
  int artistId, {
  required String year,
  String type = 'Album',
  int files = 0,
  bool monitored = false,
  bool art = true,
  String? foreign,
}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  foreignAlbumId: foreign ?? 'mb-album-$id',
  albumType: type,
  releaseDate: '$year-06-01T00:00:00Z',
  monitored: monitored,
  images: art ? _cover(CatalogArt.poster) : const [],
  statistics: {'trackFileCount': files, 'totalTrackCount': 5},
);

final _jan = _artist(1, 'Jan Morgenstern', foreign: 'mb-jan');
final _birch = _artist(2, 'Birch & Hollow');
final _cedar = _artist(3, 'Cedar Lines');

/// What the shelf holds: the board's three, the newest first.
MoreFromYourArtists _threeTiles() => MoreFromYourArtists.of(
  albums: [
    _album(11, 'Big Buck Bunny Suite', 1, year: '2008', type: 'EP'),
    _album(12, 'The Dragon', 1, year: '2010', type: 'Single'),
    _album(13, 'Snow', 1, year: '2010', type: 'Single'),
  ],
  artists: [_jan],
  now: DateTime(2026, 11, 15),
);

/// The whole of it, for See all: three artists, one with an album with no
/// artwork and a title that runs past its tile.
MoreFromYourArtists _whole() => MoreFromYourArtists.of(
  albums: [
    ..._threeTiles().albums.map((entry) => entry.album),
    _album(21, 'Winter Tapes', 2, year: '2019', type: 'Album'),
    _album(22, 'Radio Sessions', 2, year: '2014', type: 'EP', art: false),
    _album(
      31,
      'The Complete Unreleased Studio Recordings and Other Rarities',
      3,
      year: '2003',
      art: false,
    ),
  ],
  artists: [_jan, _birch, _cedar],
  now: DateTime(2026, 11, 15),
);

ServiceInstance _lidarrConnection() => ServiceInstance(
  id: 'lidarr',
  service: ServiceKey.lidarr,
  label: '',
  url: 'http://nas.home.arpa:8686',
  credential: 'catalog',
);

const _trending = [
  MediaPreview(
    id: 20,
    title: 'Sintel',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
  ),
  MediaPreview(
    id: 21,
    title: 'Cosmos Laundromat',
    mediaType: 'tv',
    posterPath: CatalogArt.tmdbPoster,
  ),
  MediaPreview(
    id: 22,
    title: 'Tears of Steel',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
  ),
];

/// What every scene reads: the shelf, Lidarr's queue empty, the calendar of the
/// boards' household, and the pictures lit.
List<Override> _world({
  required List<ServiceKey> services,
  MoreFromYourArtists? shelf,
}) => [
  currentSettingsProvider.overrideWith((ref) => settingsWithServices(services)),
  moreFromYourArtistsProvider.overrideWith(
    (ref) async => shelf ?? _threeTiles(),
  ),
  lidarrQueueSnapshotsProvider.overrideWith(
    (ref) async => LidarrQueueSnapshots.empty,
  ),
  titleLightProvider.overrideWith((ref, url) async => _light),
  hasCalendarProvider.overrideWithValue(true),
  calendarClockProvider.overrideWithValue(() => CalendarWorld.now),
  calendarProvider.overrideWith(
    (ref) async => LibraryCalendar(
      window: CalendarWorld.window,
      events: [CalendarWorld.spriteFright(), CalendarWorld.album],
      answered: const ['Radarr', 'Lidarr'],
      silent: const [],
      kinds: const {},
      readAt: CalendarWorld.now,
    ),
  ),
  seerrNumberingProvider.overrideWith((ref) async => null),
];

/// The atrium of a household with Seerr: its doors, the shelves Seerr reads,
/// and Lidarr's between them.
Widget _atrium() => const Scaffold(body: DiscoverAtrium());

List<Override> _atriumReads() => [
  atriumTrendingProvider.overrideWith((ref) async => _trending),
  bestMissingProvider.overrideWith((ref) async => [_trending[1]]),
  comingSoonProvider.overrideWith((ref) async => [_trending[2]]),
  catalogGenresProvider.overrideWith((ref, kind) async => const []),
  trendingPeopleProvider.overrideWith((ref) async => const []),
  atriumFacesProvider.overrideWith((ref) async => const []),
];

// === The search ============================================================

GlobalSearchResult _movie(String title, int id, int year) => GlobalSearchResult(
  service: ServiceKey.seerr,
  id: id,
  title: title,
  subtitle: 'Movie',
  imageUrl: 'https://image.tmdb.org/t/p/w154${CatalogArt.tmdbPoster}',
  imageHeaders: null,
  tags: const ['Movie'],
  route: '/discover/media/movie/$id',
  heroTag: 'catalog_$id',
  kind: SearchHitKind.movie,
  key: MediaKey.movie(id),
  year: year,
  seerrInfo: const {'status': 5},
);

GlobalSearchServiceResults _seerrLane(List<GlobalSearchResult> results) =>
    GlobalSearchServiceResults(
      leg: (
        instance: ServiceInstance(
          id: 'seerr',
          service: ServiceKey.seerr,
          label: '',
          url: 'http://nas.home.arpa:5055',
          credential: 'catalog',
        ),
        name: '',
      ),
      results: results,
    );

LidarrAlbumHit _albumHit(
  String title,
  String foreign,
  LidarrArtist artist, {
  String year = '2010',
  String type = 'Album',
  String? date,
}) {
  final raw = {
    'id': 0,
    'title': title,
    'foreignAlbumId': foreign,
    'albumType': type,
    'releaseDate': date ?? '$year-04-14T00:00:00Z',
    'monitored': false,
    'images': _cover(CatalogArt.poster),
    'artist': {
      'id': artist.id,
      'artistName': artist.artistName,
      'foreignArtistId': artist.foreignArtistId,
      'status': 'continuing',
      'monitored': false,
      'images': const <Object?>[],
      'genres': const <Object?>[],
    },
  };
  return LidarrAlbumHit(
    album: LidarrAlbum.fromJson(raw),
    artist: artist,
    raw: raw,
  );
}

/// A few days after the catalog's clock: the anniversary edition is not out
/// yet, and the app words that against the same clock (`catalogNow`).
final _soon = DateTime(
  catalogNow.year,
  catalogNow.month,
  catalogNow.day + 3,
).toUtc().toIso8601String();

/// What the library holds, for a row to be told held from not: Jan Morgenstern
/// and Sintel on disk, and the anniversary edition not out yet.
MusicHeld _held() => MusicHeld(
  artists: [_jan],
  albums: [
    _album(3, 'Sintel', 1, year: '2010', files: 5, foreign: 'mb-sintel'),
    LidarrAlbum(
      id: 4,
      title: 'Sintel (Anniversary Edition)',
      artistId: 1,
      foreignAlbumId: 'mb-anniversary',
      albumType: 'Album',
      releaseDate: _soon,
      monitored: true,
      images: _cover(CatalogArt.poster),
      statistics: const {'trackFileCount': 0, 'totalTrackCount': 5},
    ),
  ],
);

DiscoverMusicFound _sintelMusic() => DiscoverMusicFound(
  hits: [
    _albumHit('Sintel', 'mb-sintel', _jan),
    _albumHit(
      'Sintel (Anniversary Edition)',
      'mb-anniversary',
      _jan,
      date: _soon,
    ),
    _albumHit('Sintel Reprise', 'mb-reprise', _jan, year: '2012', type: 'EP'),
  ],
  held: _held(),
);

DiscoverMusicFound _elbowMusic() {
  final elbow = _artist(
    0,
    'Elbow',
    foreign: 'mb-elbow',
    type: 'Group',
    disambiguation: 'Bury, England',
  );
  return DiscoverMusicFound(
    hits: [
      LidarrArtistHit(elbow),
      _albumHit('The Seldom Seen Kid', 'mb-kid', elbow, year: '2008'),
      _albumHit('Build a Rocket Boys!', 'mb-rocket', elbow, year: '2011'),
    ],
    held: _held(),
  );
}

CatalogScene _search(
  String caption, {
  required String query,
  required DiscoverMusic music,
  List<GlobalSearchResult> titles = const [],
  List<ServiceKey> services = const [ServiceKey.seerr, ServiceKey.lidarr],
  bool requester = false,
  double width = 390,
  double height = 900,
  double textScale = 1,
  CatalogPlatform platform = CatalogPlatform.phone,
  String? id,
}) => CatalogScene(
  caption,
  (_) => const DiscoverPage(),
  width: width,
  height: height,
  textScale: textScale,
  platform: platform,
  id: id,
  overrides: [
    ..._world(services: services),
    ..._atriumReads(),
    globalSearchQueryProvider.overrideWith((ref) => query),
    globalSearchLanesProvider.overrideWith((ref) => [_seerrLane(titles)]),
    discoverMusicProvider.overrideWithValue(music),
    if (requester) audienceProvider.overrideWithValue(Audience.requester),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLight);
  catalogCard(
    'DiscoverMusic',
    scenes: [
      CatalogScene(
        'The shelf with Seerr · after what Seerr says is missing from the '
        'library, before what is trending: the board’s three albums, '
        'newest first, each the cover with its own light, the title, and who '
        'made it, what it is and when; no plus',
        (_) => _atrium(),
        width: 390,
        height: 1500,
        overrides: [
          ..._world(services: const [ServiceKey.seerr, ServiceKey.lidarr]),
          ..._atriumReads(),
        ],
      ),
      CatalogScene(
        'The shelf without Seerr · under the calendar, over the note about '
        'where the catalog comes from',
        (_) => const DiscoverPage(),
        width: 390,
        height: 1000,
        overrides: [
          ..._world(services: const [ServiceKey.radarr, ServiceKey.lidarr]),
          ..._atriumReads(),
        ],
      ),
      CatalogScene(
        'The shelf on a desktop window · the rail runs past its edge, the '
        'heading carries the arrows a mouse needs',
        (_) => ListView(children: const [MoreFromYourArtistsShelf()]),
        width: 760,
        height: 360,
        platform: CatalogPlatform.desktop,
        overrides: _world(
          services: const [ServiceKey.seerr, ServiceKey.lidarr],
          shelf: MoreFromYourArtists.of(
            albums: [
              for (var i = 0; i < 8; i++)
                _album(
                  100 + i,
                  const [
                    'Big Buck Bunny Suite',
                    'The Dragon',
                    'Snow',
                    'Winter Tapes',
                    'Radio Sessions',
                    'Sketches',
                    'B-Sides',
                    'Remixes',
                  ][i],
                  1,
                  year: '${2010 - i}',
                  type: const ['EP', 'Single', 'Album'][i % 3],
                ),
            ],
            artists: [_jan],
            now: DateTime(2026, 11, 15),
          ),
        ),
      ),
      CatalogScene(
        'The shelf at 200% · the title and the line under it take two lines '
        'each, the rail grows to hold them and nothing is cut',
        (_) => ListView(children: const [MoreFromYourArtistsShelf()]),
        width: 390,
        height: 420,
        textScale: catalogTextScale,
        overrides: _world(
          services: const [ServiceKey.seerr, ServiceKey.lidarr],
        ),
      ),
      CatalogScene(
        'See all · the albums under their artists, the artists A to Z, each '
        'artist’s newest first: a square cover with the kind and the '
        'year, the word the library keeps for an album left alone; one with '
        'no artwork wears its initials, a long title takes two lines',
        (_) => const MoreFromYourArtistsPage(),
        width: 390,
        height: 1000,
        overrides: _world(
          services: const [ServiceKey.seerr, ServiceKey.lidarr],
          shelf: _whole(),
        ),
      ),
      CatalogScene(
        'See all on a desktop window · the rows keep a page of one '
        'column’s measure',
        (_) => const MoreFromYourArtistsPage(),
        width: 1000,
        height: 800,
        platform: CatalogPlatform.desktop,
        overrides: _world(
          services: const [ServiceKey.seerr, ServiceKey.lidarr],
          shelf: _whole(),
        ),
      ),
      CatalogScene(
        'See all at 200% · the heading’s count and the rows’ words '
        'wrap, never clip',
        (_) => const MoreFromYourArtistsPage(),
        width: 390,
        height: 1000,
        textScale: catalogTextScale,
        id: 'see-all-200',
        overrides: _world(
          services: const [ServiceKey.seerr, ServiceKey.lidarr],
          shelf: _whole(),
        ),
      ),
      _search(
        'Search · Sintel: the movie on the server and music together; Music '
        'after it, three rows (an album the library holds and has complete, '
        'one not out yet, one it has not got with the plus), and the way to '
        'all of them',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: _sintelMusic(),
        height: 1100,
      ),
      _search(
        'Search · Elbow: music alone, an artist and two albums the library '
        'has not got, each with the plus; the people say no one',
        query: 'elbow',
        music: _elbowMusic(),
        height: 800,
      ),
      _search(
        'Search · Lidarr answers after the others: Music with Asking Lidarr '
        'over two square plates, and what came already there',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: const DiscoverMusicAsking(),
        height: 800,
      ),
      _search(
        'Search · its catalog does not answer: no Music, and a line at the '
        'head says so, with Retry',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: DiscoverMusicFault(
          lane: GlobalSearchServiceResults(
            leg: (instance: _lidarrConnection(), name: ''),
            state: SearchLaneState.failed,
            reason: ServiceFailureReason.serverError,
          ),
          sentence:
              'Lidarr answered, but its music catalog did not, so music is '
              'missing.',
        ),
        height: 800,
      ),
      _search(
        'Search · the requester: Sintel in movies and series and people, '
        'no Music and no Lidarr, and the field says what it always said',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: const DiscoverMusicOff(),
        services: const [ServiceKey.seerr],
        requester: true,
        height: 800,
      ),
      _search(
        'Search on a desktop window · Sintel, the rows in a column of one '
        'page’s measure',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: _sintelMusic(),
        width: 1000,
        height: 900,
        platform: CatalogPlatform.desktop,
        id: 'search-desktop',
      ),
      _search(
        'Search at 200% · Sintel: the rows take two lines, the way to the '
        'wall wraps',
        query: 'sintel',
        titles: [_movie('Sintel', 20, 2010)],
        music: _sintelMusic(),
        height: 1700,
        textScale: catalogTextScale,
        id: 'search-200',
      ),
    ],
  );
}
