@Tags(['catalog'])
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/presentation/movies_find.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/domain/readarr_author_caption.dart';
import 'package:cupola/features/readarr/presentation/readarr_find.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_search_provider.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/series/presentation/series_find.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/media/presentation/arr_bulk.dart';
import 'package:cupola/features/movies/presentation/movies_bulk.dart';
import 'package:cupola/features/readarr/presentation/readarr_bulk.dart';
import 'package:cupola/features/series/presentation/series_bulk.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/core/widgets/library_selection.dart';
import 'package:cupola/core/widgets/media_browse_index.dart';
import 'package:cupola/core/widgets/media_bulk.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/lidarr_bulk.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/core/widgets/media_browse_wanted.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/lidarr_artist_caption.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/lidarr_wanted.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/music_find.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/services/presentation/services_queue_snapshots.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// On the catalog's pinned origin with no file behind it: the load fails.
const _missing = 'https://art.catalog/missing.jpg';

typedef _Film = ({
  int id,
  String title,
  String sortTitle,
  int year,
  String? poster,
  MediaStatusInfo status,
  String added,
});

/// Public-domain silents. One sample poster exists and it is Nosferatu's; the
/// rest show the no-URL and failed-load states rather than borrowing it.
const List<_Film> _library = [
  (
    id: 1,
    title: 'Nosferatu',
    sortTitle: 'nosferatu',
    year: 1922,
    poster: CatalogArt.poster,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-09-20T10:00:00Z',
  ),
  (
    id: 2,
    title: 'Metropolis',
    sortTitle: 'metropolis',
    year: 1927,
    poster: null,
    status: MediaStatusInfo(
      pipeline: MediaPipeline.downloading,
      progress: 0.42,
    ),
    added: '2026-09-26T10:00:00Z',
  ),
  (
    id: 3,
    title: 'The Cabinet of Dr. Caligari',
    sortTitle: 'cabinet of dr caligari',
    year: 1920,
    poster: _missing,
    status: MediaStatusInfo(availability: MediaAvailability.missing),
    added: '2026-09-12T10:00:00Z',
  ),
  (
    id: 4,
    title: 'Sherlock Jr.',
    sortTitle: 'sherlock jr',
    year: 1924,
    poster: null,
    status: MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.61),
    added: '2026-09-18T10:00:00Z',
  ),
  (
    id: 5,
    title: 'Nanook of the North',
    sortTitle: 'nanook of the north',
    year: 1922,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.upgradable),
    added: '2026-09-02T10:00:00Z',
  ),
  (
    id: 6,
    title: 'Safety Last!',
    sortTitle: 'safety last',
    year: 1923,
    poster: null,
    status: MediaStatusInfo(
      availability: MediaAvailability.missing,
      unmonitored: true,
    ),
    added: '2026-08-30T10:00:00Z',
  ),
  (
    id: 7,
    title: '20,000 Leagues Under the Sea',
    sortTitle: '20000 leagues under sea',
    year: 1916,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-12T10:00:00Z',
  ),
  (
    id: 8,
    title: 'The Mark of Zorro',
    sortTitle: 'mark of zorro',
    year: 1920,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-14T10:00:00Z',
  ),
  (
    id: 9,
    title: 'The Navigator',
    sortTitle: 'navigator',
    year: 1924,
    poster: null,
    status: MediaStatusInfo(pipeline: MediaPipeline.queued),
    added: '2026-09-27T10:00:00Z',
  ),
  (
    id: 10,
    title: 'The Sheik',
    sortTitle: 'sheik',
    year: 1921,
    poster: null,
    status: MediaStatusInfo(availability: MediaAvailability.available),
    added: '2026-08-20T10:00:00Z',
  ),
];

final _libraryProvider = FutureProvider<List<_Film>>((ref) async => _library);

/// The same library without its one-title sections, so a lettered wall shows
/// full rows: M, N and S only.
final _shelfProvider = FutureProvider<List<_Film>>(
  (ref) async => [
    for (final film in _library)
      if ('mns'.contains(film.sortTitle[0])) film,
  ],
);
final _emptyProvider = FutureProvider<List<_Film>>((ref) async => const []);
final _pendingProvider = FutureProvider<List<_Film>>(
  (ref) => Completer<List<_Film>>().future,
);
final _failingProvider = FutureProvider<List<_Film>>(
  (ref) async => throw DioException.connectionError(
    requestOptions: RequestOptions(path: '/api/v3/movie'),
    reason: 'Connection refused',
  ),
  retry: noProviderRetry,
);
final _unconfiguredProvider = FutureProvider<List<_Film>>(
  (ref) async => throw const ServiceNotConfigured(ServiceKey.radarr),
  retry: noProviderRetry,
);

/// Each phone gets its own query, so typing into one does not search another.
final _queries = [
  for (var i = 0; i < 16; i++) StateProvider<String>((ref) => ''),
];

const _kpis = AsyncValue<List<ServiceKpi>>.data([
  ServiceKpi(label: 'Movies', value: '1,284', icon: Icons.movie_rounded),
  ServiceKpi(
    label: 'Monitored',
    value: '1,190',
    icon: Icons.visibility_rounded,
  ),
  ServiceKpi(
    label: 'Missing',
    value: '37',
    icon: Icons.report_gmailerrorred_rounded,
    tone: StatusTone.neutral,
  ),
  ServiceKpi(label: 'Queue', value: '3', icon: Icons.download_rounded),
]);

Widget _scaffold(
  int phone, {
  FutureProvider<List<_Film>>? library,
  bool peek = true,
  bool sorts = true,
  Set<int>? cutoff = const {5},
  MediaBrowseTileShape shape = MediaBrowseTileShape.poster,
  String title = 'Movies',
  ServiceKey? service,
  bool status = true,
  IconData emptyIcon = Icons.video_library_outlined,
  String? emptyMessage,
  MediaBulk<_Film>? bulk,
  bool showAppBar = true,
  double topPadding = 0,
  IconData posterIcon = Icons.movie_outlined,
}) {
  return MediaBrowseScaffold<_Film>(
    title: title,
    searchHint: 'Search movies',
    activityRoute: '/activity',
    navigationSection: NavigationSection.stack,
    serviceName: 'Radarr',
    service: service,
    accentColor: ServiceKey.radarr.accent,
    heroTagPrefix: 'movie',
    libraryProvider: library ?? _libraryProvider,
    searchQueryProvider: _queries[phone],
    // What the field finds is the finds' own scenes; the wall's own are drawn
    // with the field empty.
    find: MediaFind.libraryOnly(
      libraryBody: (context, query) => Center(child: Text('Finding “$query”')),
    ),
    titleExtractor: (film) => film.title,
    subtitleExtractor: (film) => '${film.year}',
    sortTitleExtractor: (film) => film.sortTitle,
    imagesExtractor: (film) => film.poster == null
        ? const []
        : [
            {'coverType': 'poster', 'remoteUrl': film.poster},
          ],
    idExtractor: (film) => film.id,
    statusExtractor: status ? (movie) => movie.status : null,
    settingsSelector: (_) => ('', '', const NoAccess()),
    onItemTap: (_, _, _) {},
    emptyIcon: emptyIcon,
    emptyMessage: emptyMessage,
    tileShape: shape,
    cutoffUnmetIds: cutoff,
    bulk: bulk,
    posterFallbackIcon: posterIcon,
    showAppBar: showAppBar,
    topPadding: topPadding,
    sorts: sorts
        ? [
            MediaBrowseSort<_Film>.dateAdded((film) => film.added),
            MediaBrowseSort<_Film>.year((film) => film.year),
          ]
        : const [],
    kpiPeek: peek
        ? ServiceKpiPeek(kpis: _kpis, service: ServiceKey.radarr)
        : null,
  );
}

/// A phone-sized screen: its own box and its own `MediaQuery`, so three can
/// stand side by side in one scene.
Widget _phone(Widget child) => Builder(
  builder: (context) => SizedBox(
    width: 390,
    height: 844,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
      child: ClipRect(child: child),
    ),
  ),
);

Widget _phones(List<Widget> screens) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, screen) in screens.indexed) ...[
      if (index > 0) const SizedBox(width: 24),
      _phone(screen),
    ],
  ],
);

// === Music: the wall that finds in its library, then in Lidarr ============

LidarrArtist _artist(
  int id,
  String name, {
  String foreign = '',
  Map<String, dynamic>? statistics,
}) => LidarrArtist(
  id: id,
  artistName: name,
  foreignArtistId: foreign,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  statistics: statistics,
);

LidarrAlbum _album(
  int id,
  String title,
  int artistId,
  String year, {
  int files = 0,
  int tracks = 11,
  bool monitored = true,
  String foreign = '',
  String? art,
}) => LidarrAlbum(
  id: id,
  title: title,
  artistId: artistId,
  foreignAlbumId: foreign,
  releaseDate: '$year-01-01T00:00:00Z',
  monitored: monitored,
  images: [
    if (art != null) {'coverType': 'cover', 'remoteUrl': art},
  ],
  statistics: {'trackFileCount': files, 'totalTrackCount': tracks},
);

final _musicArtists = [
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
  _artist(1, 'Jan Morgenstern', foreign: 'mb-jan'),
  _artist(5, 'The Jimi Hendrix Experience', foreign: 'mb-jimi'),
];

final _musicAlbums = [
  _album(
    10,
    'Elephants Dream',
    1,
    '2006',
    files: 7,
    tracks: 7,
    foreign: 'mb-elephants',
    art: CatalogArt.poster,
  ),
  _album(11, 'Ella and Louis', 3, '1956', files: 9, foreign: 'mb-eal'),
  _album(12, 'Elegy for Strings', 2, '1909', tracks: 1, foreign: 'mb-elegy'),
  _album(
    13,
    'Electric Ladyland',
    5,
    '1968',
    monitored: false,
    foreign: 'mb-ladyland',
  ),
];

/// What Lidarr's catalog answers for `el`: Elbow (not held), Ella (held), an
/// album of Elbow's, one the library holds and left alone, and one by an
/// artist the library holds.
final _musicCatalog = <LidarrSearchHit>[
  for (final row in <Map<String, dynamic>>[
    {
      'artist': {
        'id': 0,
        'artistName': 'Elbow',
        'foreignArtistId': 'mb-elbow',
        'artistType': 'Group',
        'disambiguation': 'Bury, England',
        'status': 'continuing',
      },
    },
    {
      'artist': {
        'id': 3,
        'artistName': 'Ella Fitzgerald',
        'foreignArtistId': 'mb-ella',
        'artistType': 'Person',
        'status': 'continuing',
      },
    },
    for (final (title, foreign, artist, artistForeign, type) in const [
      ('Leaders of the Free World', 'mb-leaders', 'Elbow', 'mb-elbow', 'Album'),
      (
        'Electric Ladyland',
        'mb-ladyland',
        'The Jimi Hendrix Experience',
        'mb-jimi',
        'Album',
      ),
      ('Elegy for Brass', 'mb-brass', 'Edward Elgar', 'mb-elgar', 'Single'),
    ])
      {
        'album': {
          'id': 0,
          'title': title,
          'foreignAlbumId': foreign,
          'albumType': type,
          'releaseDate': '2005-03-07T00:00:00Z',
          'images': const <Object?>[],
          'artist': {
            'id': 0,
            'artistName': artist,
            'foreignArtistId': artistForeign,
            'status': 'continuing',
          },
        },
      },
  ])
    ?LidarrSearchHit.tryParse(row),
];

/// The Music wall as `MusicScreen` builds it: the real find bodies over a
/// scaffold with nothing else of the screen (no peek, no cutoff source).
Widget _music() => MediaBrowseScaffold<LidarrArtist>(
  title: 'Music',
  searchHint: 'Artists and albums',
  activityRoute: '/activity',
  navigationSection: NavigationSection.stack,
  serviceName: 'Lidarr',
  service: ServiceKey.lidarr,
  accentColor: ServiceKey.lidarr.accent,
  heroTagPrefix: 'artist',
  libraryProvider: musicProvider,
  searchQueryProvider: musicSearchQueryProvider,
  find: MediaFind(
    scopeProvider: musicFindScopeProvider,
    libraryBody: (context, query) =>
        MusicFindLibrary(query: query, onAskLidarr: () {}),
    serviceBody: (context, query) => MusicFindLidarr(query: query),
  ),
  titleExtractor: (artist) => artist.artistName,
  subtitleExtractor: (artist) => '',
  imagesExtractor: (artist) => artist.images,
  idExtractor: (artist) => artist.id,
  settingsSelector: (_) => ('', '', const NoAccess()),
  onItemTap: (_, _, _) {},
  tileShape: MediaBrowseTileShape.circle,
);

/// What the Music wall reads: a library to find in, an empty queue, and
/// Lidarr's answer to the search.
List<Override> _musicOverrides(
  String query,
  MediaFindScope scope,
  Future<List<LidarrSearchHit>?> Function()? search,
) => [
  musicProvider.overrideWith((ref) async => _musicArtists),
  musicAlbumsProvider.overrideWith((ref) async => _musicAlbums),
  lidarrQueueSnapshotsProvider.overrideWith(
    (ref) async => LidarrQueueSnapshots.empty,
  ),
  musicSearchQueryProvider.overrideWith((ref) => query),
  musicFindScopeProvider.overrideWith((ref) => scope),
  musicSearchResultsProvider.overrideWith(
    (ref) => (search ?? () async => const <LidarrSearchHit>[])(),
  ),
];

/// One phone of the Music wall, with the field holding [query] in [scope] and
/// Lidarr answering with [search].
CatalogScene _musicScene(
  String caption, {
  required String query,
  MediaFindScope scope = MediaFindScope.library,
  Future<List<LidarrSearchHit>?> Function()? search,
  double textScale = 1,
  String? id,
}) => CatalogScene(
  caption,
  (_) => _phone(_music()),
  id: id,
  textScale: textScale,
  overrides: _musicOverrides(query, scope, search),
);

// === Movies, Series and Authors: the wall that finds ======================

RadarrMovie _radarrMovie(
  int id,
  String title,
  int year,
  int runtime, {
  int tmdbId = 0,
  bool hasFile = false,
  String? art,
}) => RadarrMovie.fromJson({
  'id': id,
  'title': title,
  'sortTitle': title.toLowerCase(),
  'year': year,
  'runtime': runtime,
  'tmdbId': tmdbId,
  'hasFile': hasFile,
  'monitored': true,
  'isAvailable': true,
  'status': 'released',
  'images': [
    if (art != null) {'coverType': 'poster', 'remoteUrl': art},
  ],
});

SonarrSeries _sonarrSeries(
  int id,
  String title,
  int year,
  int seasons, {
  int tmdbId = 0,
  bool complete = false,
  String? art,
}) => SonarrSeries.fromJson({
  'id': id,
  'title': title,
  'sortTitle': title.toLowerCase(),
  'year': year,
  'tmdbId': tmdbId,
  'monitored': true,
  'status': 'ended',
  'seasons': [
    for (var n = 1; n <= seasons; n++) {'seasonNumber': n, 'monitored': true},
  ],
  'statistics': {'episodeFileCount': complete ? 8 : 0, 'episodeCount': 8},
  'images': [
    if (art != null) {'coverType': 'poster', 'remoteUrl': art},
  ],
});

ReadarrAuthor _author(int id, String name, int books, int onDisk) =>
    ReadarrAuthor(
      id: id,
      authorName: name,
      monitored: true,
      bookCount: books,
      bookFileCount: onDisk,
    );

final _finderMovies = [
  _radarrMovie(1, 'Sherlock Jr.', 1924, 45, tmdbId: 1, hasFile: true),
  _radarrMovie(2, 'The Sheik', 1921, 80, tmdbId: 2),
  _radarrMovie(3, 'Nosferatu', 1922, 94, tmdbId: 3, hasFile: true),
];

/// What Radarr's lookup answers for `sh`: the one the library holds, and two
/// it does not.
final _radarrLookup = [
  _radarrMovie(1, 'Sherlock Jr.', 1924, 45, tmdbId: 1, hasFile: true),
  _radarrMovie(0, 'Sherlock Holmes', 2009, 128, tmdbId: 77),
  _radarrMovie(0, 'Shane', 1953, 118, tmdbId: 78),
];

final _finderSeries = [
  _sonarrSeries(1, 'Cosmos Laundromat', 2015, 3, tmdbId: 1, complete: true),
  _sonarrSeries(2, 'Cowboy Bebop', 1998, 1, tmdbId: 2),
  _sonarrSeries(3, 'Hero', 2018, 2, tmdbId: 3, complete: true),
];

final _finderAuthors = [
  _author(1, 'Jules Verne', 7, 6),
  _author(2, 'Jules Renard', 12, 12),
  _author(3, 'Brandon Sanderson', 20, 15),
];

/// What the three walls read: a library to find in, an empty queue, the lookup
/// and the Seerr answers the title rows ask of it.
List<Override> _finderOverrides({
  String query = '',
  MediaFindScope scope = MediaFindScope.library,
  Future<List<RadarrMovie>?> Function()? movieLookup,
}) => [
  moviesProvider.overrideWith((ref) async => _finderMovies),
  radarrQueueSnapshotProvider.overrideWith(
    (ref) async => ArrQueueSnapshot.empty,
  ),
  moviesSearchQueryProvider.overrideWith((ref) => query),
  moviesFindScopeProvider.overrideWith((ref) => scope),
  moviesSearchResultsProvider.overrideWith(
    (ref) => (movieLookup ?? () async => const <RadarrMovie>[])(),
  ),
  seriesProvider.overrideWith((ref) async => _finderSeries),
  sonarrQueueSnapshotProvider.overrideWith(
    (ref) async => ArrQueueSnapshot.empty,
  ),
  seriesSearchQueryProvider.overrideWith((ref) => query),
  seriesFindScopeProvider.overrideWith((ref) => MediaFindScope.library),
  readarrAuthorsProvider.overrideWith((ref) async => _finderAuthors),
  readarrSearchQueryProvider.overrideWith((ref) => query),
  seerrNumberingProvider.overrideWith((ref) async => null),
  seerrSendsToProvider.overrideWith((ref, arr) async => false),
];

/// The Movies wall as `MoviesScreen` builds it, over the real find bodies.
Widget _moviesFinder() => Consumer(
  builder: (context, ref, _) {
    final queue = ref.watch(radarrQueueSnapshotProvider).value;
    MediaStatusInfo? status(RadarrMovie movie) => queue == null
        ? null
        : badgeOverQueue(
            radarrMovieStatus(
              movie,
              queueEntry: queue.entryFor(movie.id),
              queueUnknown: !queue.isWhole,
            ),
            queue,
          );
    return MediaBrowseScaffold<RadarrMovie>(
      title: 'Movies',
      searchHint: 'Movies',
      activityRoute: '/activity',
      navigationSection: NavigationSection.stack,
      serviceName: 'Radarr',
      service: ServiceKey.radarr,
      accentColor: ServiceKey.radarr.accent,
      heroTagPrefix: 'movie',
      libraryProvider: moviesProvider,
      searchQueryProvider: moviesSearchQueryProvider,
      find: MediaFind(
        scopeProvider: moviesFindScopeProvider,
        libraryBody: (context, query) => MoviesFindLibrary(
          query: query,
          statusOf: status,
          settingsSelector: (_) => ('', '', const NoAccess()),
          onOpen: (_, _, _) {},
          onAskRadarr: () => ref.read(moviesFindScopeProvider.notifier).state =
              MediaFindScope.service,
        ),
        serviceBody: (context, query) => MoviesFindRadarr(
          query: query,
          statusOf: status,
          onOpen: (_, _, _) {},
        ),
      ),
      titleExtractor: (movie) => movie.title,
      subtitleExtractor: (movie) => '${movie.year}',
      imagesExtractor: (movie) => movie.images,
      idExtractor: (movie) => movie.id,
      settingsSelector: (_) => ('', '', const NoAccess()),
      onItemTap: (_, _, _) {},
    );
  },
);

Widget _seriesFinder() => Consumer(
  builder: (context, ref, _) {
    final queue = ref.watch(sonarrQueueSnapshotProvider).value;
    MediaStatusInfo? status(SonarrSeries series) => queue == null
        ? null
        : badgeOverQueue(
            sonarrSeriesStatus(
              series,
              queueEntry: queue.entryFor(series.id),
              queueUnknown: !queue.isWhole,
            ),
            queue,
          );
    return MediaBrowseScaffold<SonarrSeries>(
      title: 'TV series',
      searchHint: 'Series',
      activityRoute: '/activity',
      navigationSection: NavigationSection.stack,
      serviceName: 'Sonarr',
      service: ServiceKey.sonarr,
      accentColor: ServiceKey.sonarr.accent,
      heroTagPrefix: 'series',
      libraryProvider: seriesProvider,
      searchQueryProvider: seriesSearchQueryProvider,
      find: MediaFind(
        scopeProvider: seriesFindScopeProvider,
        libraryBody: (context, query) => SeriesFindLibrary(
          query: query,
          statusOf: status,
          settingsSelector: (_) => ('', '', const NoAccess()),
          onOpen: (_, _, _) {},
          onAskSonarr: () => ref.read(seriesFindScopeProvider.notifier).state =
              MediaFindScope.service,
        ),
        serviceBody: (context, query) => SeriesFindSonarr(
          query: query,
          statusOf: status,
          onOpen: (_, _, _) {},
        ),
      ),
      titleExtractor: (series) => series.title,
      subtitleExtractor: (series) => '${series.year}',
      imagesExtractor: (series) => series.images,
      idExtractor: (series) => series.id,
      settingsSelector: (_) => ('', '', const NoAccess()),
      onItemTap: (_, _, _) {},
    );
  },
);

Widget _authorsFinder() => MediaBrowseScaffold<ReadarrAuthor>(
  title: 'Authors',
  searchHint: 'Authors',
  activityRoute: '/activity',
  navigationSection: NavigationSection.stack,
  serviceName: 'Readarr',
  service: ServiceKey.readarr,
  accentColor: ServiceKey.readarr.accent,
  heroTagPrefix: 'author',
  libraryProvider: readarrAuthorsProvider,
  searchQueryProvider: readarrSearchQueryProvider,
  find: MediaFind.libraryOnly(
    libraryBody: (context, query) => AuthorsFindLibrary(
      query: query,
      settingsSelector: (_) => ('', '', const NoAccess()),
      onOpen: (_, _, _) {},
    ),
  ),
  titleExtractor: (author) => author.authorName,
  subtitleExtractor: readarrAuthorCaption,
  imagesExtractor: (author) => author.images,
  idExtractor: (author) => author.id,
  settingsSelector: (_) => ('', '', const NoAccess()),
  onItemTap: (_, _, _) {},
  tileShape: MediaBrowseTileShape.circle,
);

/// One phone of a wall that finds, with the field holding [query].
CatalogScene _finderScene(
  String caption,
  Widget Function() wall, {
  required String query,
  MediaFindScope scope = MediaFindScope.library,
  Future<List<RadarrMovie>?> Function()? movieLookup,
  double textScale = 1,
  String? id,
}) => CatalogScene(
  caption,
  (_) => _phone(wall()),
  id: id,
  textScale: textScale,
  overrides: _finderOverrides(
    query: query,
    scope: scope,
    movieLookup: movieLookup,
  ),
);

// === A long wall: the A–Z strip, and Lidarr's Wanted chip =================

/// Fifty artists over every letter but Q, U, X and Z, and one under `#`.
final _longArtists = [
  for (final (index, name) in const [
    '1000 Paper Boats',
    'Alder Quartet',
    'Amber Static',
    'Aurelia Row',
    'Birch & Hollow',
    'Brass Lantern',
    'Blue Harbor Choir',
    'Cobalt Meadow',
    'Copper Tide',
    'Cedar Lines',
    'Dune Orchestra',
    'Dust Cathedral',
    'Echo Parade',
    'Élan Static',
    'Elm Street Brass',
    'Fable Hours',
    'Fern & Flint',
    'Garden Machine',
    'Glass Orchard',
    'Harbor Lights Trio',
    'Hollow Pines',
    'Indigo Ferry',
    'Jade Cassette',
    'Jan Morgenstern',
    'Juniper Wire',
    'Kestrel Union',
    'Lantern Society',
    'Low Tide Radio',
    'Lumen Choir',
    'Marble Valley',
    'Midnight Orchard',
    'Moss Telegraph',
    'Night Ferry',
    'North Pier',
    'Oak Frequency',
    'Opal Room',
    'Paper Cranes',
    'Pale Harbor',
    'Rivet Sky',
    'Rust Garden',
    'Salt Flats Ensemble',
    'Slate Meadow',
    'Soft Engines',
    'Tidal Archive',
    'Tin Orchard',
    'Tundra Mail',
    'Velvet Static',
    'Willow Machine',
    'Winter Dock',
    'Yarrow Lines',
    'Yellow Ledger',
  ].indexed)
    _artist(
      index + 1,
      name,
      statistics: {
        'albumCount': 3 + index % 8,
        'trackCount': (3 + index % 8) * 10,
        'trackFileCount': (3 + index % 8) * 10 - (index % 5 == 1 ? 10 : 0),
      },
    ),
];

/// Every fifth artist has an album Lidarr wants, one to three.
final _longWanted = MediaBrowseWantedSet(
  countById: {
    for (final artist in _longArtists)
      if (artist.id % 5 == 2) artist.id: 1 + artist.id % 3,
  },
);

/// Lidarr's wall as `MusicScreen` builds it, over [_longArtists]: the
/// circular tiles with their completeness, and Wanted where Missing would be.
Widget _lidarrWall() => MediaBrowseScaffold<LidarrArtist>(
  title: 'Music',
  searchHint: 'Artists and albums',
  activityRoute: '/activity',
  navigationSection: NavigationSection.stack,
  serviceName: 'Lidarr',
  service: ServiceKey.lidarr,
  accentColor: ServiceKey.lidarr.accent,
  heroTagPrefix: 'artist',
  libraryProvider: musicProvider,
  searchQueryProvider: musicSearchQueryProvider,
  find: MediaFind(
    scopeProvider: musicFindScopeProvider,
    libraryBody: (context, query) =>
        MusicFindLibrary(query: query, onAskLidarr: () {}),
    serviceBody: (context, query) => MusicFindLidarr(query: query),
  ),
  titleExtractor: (artist) => artist.artistName,
  subtitleExtractor: lidarrArtistCaption,
  imagesExtractor: (artist) => artist.images,
  idExtractor: (artist) => artist.id,
  statusExtractor: (artist) =>
      const MediaStatusInfo(availability: MediaAvailability.available),
  settingsSelector: (_) => ('', '', const NoAccess()),
  onItemTap: (_, _, _) {},
  tileShape: MediaBrowseTileShape.circle,
  cutoffUnmetIds: const {},
  wanted: MediaBrowseWanted(
    answer: AsyncData(_longWanted),
    service: ServiceKey.lidarr,
    instanceId: '',
    failureConsequence: 'the artists with a wanted album are not shown',
    onRetry: () {},
    captionOf: lidarrWantedCaption,
    summaryOf: lidarrWantedSummary,
  ),
  kpiPeek: ServiceKpiPeek(kpis: _kpis, service: ServiceKey.lidarr),
);

List<Override> _longOverrides() => [
  musicProvider.overrideWith((ref) async => _longArtists),
  lidarrQueueSnapshotsProvider.overrideWith(
    (ref) async => LidarrQueueSnapshots.empty,
  ),
  musicSearchQueryProvider.overrideWith((ref) => ''),
  musicFindScopeProvider.overrideWith((ref) => MediaFindScope.library),
];

/// Sixty movies from A to Z, for Movies' wall.
final _longFilms = <_Film>[
  for (var i = 0; i < 60; i++)
    (
      id: 100 + i,
      title:
          '${String.fromCharCode(65 + i % 26)}${'aeiou'[i % 5]}rora ${i ~/ 26 + 1}',
      sortTitle:
          '${String.fromCharCode(97 + i % 26)}${'aeiou'[i % 5]}rora ${i ~/ 26 + 1}',
      year: 1990 + i % 30,
      poster: null,
      status: const MediaStatusInfo(availability: MediaAvailability.available),
      added: '2026-09-${10 + i % 15}T10:00:00Z',
    ),
];
final _longFilmsProvider = FutureProvider<List<_Film>>(
  (ref) async => _longFilms,
);

/// Puts a finger on the strip, [fraction] of the way down it, and keeps it
/// there: the sheet is drawn with the finger down.
Future<void> _holdStrip(
  WidgetTester tester,
  Finder scene,
  double fraction,
) async {
  final rect = tester.getRect(
    find.descendant(of: scene, matching: find.byType(MediaBrowseIndex)),
  );
  final finger = await tester.startGesture(
    Offset(rect.center.dx, rect.top + rect.height * fraction),
  );
  await finger.moveBy(const Offset(0, 1));
  await tester.pump();
}

CatalogScene _lidarrWallScene(
  String caption, {
  double textScale = 1,
  String? id,
  Future<void> Function(WidgetTester, Finder)? act,
  double? width,
  double? height,
  CatalogPlatform platform = CatalogPlatform.phone,
}) => CatalogScene(
  caption,
  (_) => width == null ? _phone(_lidarrWall()) : _lidarrWall(),
  id: id,
  textScale: textScale,
  overrides: _longOverrides(),
  act: act,
  width: width,
  height: height,
  platform: platform,
);

// === Music: selecting several artists =====================================

/// What a selection of artists is read from: the board's nine, each with the
/// albums Lidarr wants of them, and sizes on disk that the three of the
/// selection add up to 61.4 GB.
final _selectArtists = [
  for (final (id, name, gigabytes, quality) in const [
    (1, 'Anton Bruckner', 14.2, 1),
    (2, 'Bill Evans', 20.1, 1),
    (3, 'Brian Eno', 18.3, 1),
    (4, 'Charles Mingus', 23.0, 2),
    (5, 'Jan Morgenstern', 0.9, 1),
    (6, 'Max Richter', 6.5, 1),
    (7, 'Miles Davis', 9.8, 2),
    (8, 'Mulatu Astatke', 3.4, 1),
    (9, 'Nina Simone', 11.7, 1),
  ])
    LidarrArtist(
      id: id,
      artistName: name,
      foreignArtistId: 'mb-select-$id',
      status: 'continuing',
      monitored: true,
      images: const [],
      genres: const [],
      monitorNewItems: 'all',
      qualityProfileId: quality,
      metadataProfileId: 1,
      statistics: {
        'albumCount': 12,
        'trackCount': 120,
        'trackFileCount': 120,
        'sizeOnDisk': (gigabytes * 1024 * 1024 * 1024).round(),
      },
    ),
];

/// The albums wanted of each artist of [_selectArtists].
final _selectWanted = MediaBrowseWantedSet(
  countById: const {1: 1, 2: 3, 3: 7, 4: 1, 5: 1, 6: 2, 7: 12, 8: 1, 9: 3},
);

/// Lidarr's wall as the router builds it in the service's Library tab, over
/// [_selectArtists]: under the band and the tab bar (`topPadding`), on the
/// Wanted chip, with [bulk] as the actions.
Widget _selectWall({MediaBulk<LidarrArtist>? bulk, bool chrome = true}) =>
    MediaBrowseScaffold<LidarrArtist>(
      title: 'Music',
      searchHint: 'Artists and albums',
      activityRoute: '/activity',
      navigationSection: NavigationSection.stack,
      serviceName: 'Lidarr',
      service: ServiceKey.lidarr,
      accentColor: ServiceKey.lidarr.accent,
      heroTagPrefix: 'artist',
      libraryProvider: musicProvider,
      searchQueryProvider: musicSearchQueryProvider,
      find: MediaFind(
        scopeProvider: musicFindScopeProvider,
        libraryBody: (context, query) =>
            MusicFindLibrary(query: query, onAskLidarr: () {}),
        serviceBody: (context, query) => MusicFindLidarr(query: query),
      ),
      titleExtractor: (artist) => artist.artistName,
      subtitleExtractor: lidarrArtistCaption,
      sortTitleExtractor: (artist) => artist.artistName,
      imagesExtractor: (artist) => artist.images,
      idExtractor: (artist) => artist.id,
      statusExtractor: (artist) => MediaStatusInfo(
        availability: artist.artistName == 'Charles Mingus'
            ? MediaAvailability.missing
            : MediaAvailability.available,
      ),
      settingsSelector: (_) => ('', '', const NoAccess()),
      onItemTap: (_, _, _) {},
      tileShape: MediaBrowseTileShape.circle,
      showAppBar: false,
      topPadding: chrome ? kToolbarHeight + ServiceTabBar.height : 0,
      cutoffUnmetIds: const {},
      wanted: MediaBrowseWanted(
        answer: AsyncData(_selectWanted),
        service: ServiceKey.lidarr,
        instanceId: '',
        failureConsequence: 'the artists with a wanted album are not shown',
        onRetry: () {},
        captionOf: lidarrWantedCaption,
        summaryOf: lidarrWantedSummary,
      ),
      bulk: bulk,
      kpiPeek: ServiceKpiPeek(kpis: _kpis, service: ServiceKey.lidarr),
    );

List<Override> _selectOverrides() => [
  musicProvider.overrideWith((ref) async => _selectArtists),
  lidarrQueueSnapshotsProvider.overrideWith(
    (ref) async => LidarrQueueSnapshots.empty,
  ),
  musicSearchQueryProvider.overrideWith((ref) => ''),
  musicFindScopeProvider.overrideWith((ref) => MediaFindScope.library),
  lidarrAddOptionsProvider.overrideWith(
    (ref, id) async => const LidarrAddOptions(
      folders: [LidarrRootFolder(path: '/mnt/tank/media/music')],
      qualityProfiles: [(id: 1, name: 'Lossless'), (id: 2, name: 'Any')],
      metadataProfiles: [
        LidarrMetadataProfile(
          id: 1,
          name: 'Standard',
          allowedPrimaryTypes: ['Album', 'EP'],
        ),
      ],
    ),
  ),
];

const _navDestinations = [
  FloatingNavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  FloatingNavDestination(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore_rounded,
    label: 'Discover',
  ),
  FloatingNavDestination(
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    label: 'Activity',
  ),
  FloatingNavDestination(
    icon: Icons.layers_outlined,
    selectedIcon: Icons.layers_rounded,
    label: 'Stack',
  ),
];

/// The phone's shell as the app builds it, as far as selection goes: the
/// floating navigation bar in the Scaffold's bottom slot, which steps down
/// while a library selects, and the service's band and tab bar over the wall,
/// which step aside.
class _CatalogShell extends StatefulWidget {
  const _CatalogShell({required this.wall, this.service = ServiceKey.lidarr});

  final Widget wall;

  /// Whose band and tab bar are over the wall.
  final ServiceKey service;

  @override
  State<_CatalogShell> createState() => _CatalogShellState();
}

class _CatalogShellState extends State<_CatalogShell> {
  final _selection = LibrarySelectionController();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LibrarySelectionScope(
    controller: _selection,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: ServiceHomeScreen(
        service: widget.service,
        child: ServiceTabScaffold(
          service: widget.service,
          tab: ServiceTab.library,
          child: widget.wall,
        ),
      ),
      bottomNavigationBar: LibrarySelectionNavSlot(
        child: FloatingBottomNavBar(
          selectedIndex: 3,
          onDestinationSelected: (_) {},
          destinations: _navDestinations,
        ),
      ),
    ),
  );
}

/// Lets the wall's motion land: the sheet is pumped in 400 ms steps.
Future<void> _land(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Enters selection by a long press on Bill Evans and taps Brian Eno and
/// Charles Mingus: three artists selected, on the Wanted chip.
Future<void> _selectThree(WidgetTester tester, Finder scene) => _selectNamed(
  tester,
  scene,
  const ['Bill Evans', 'Brian Eno', 'Charles Mingus'],
);

/// Enters selection by a long press on the first of [names] and taps the rest,
/// on the Wanted chip.
Future<void> _selectNamed(
  WidgetTester tester,
  Finder scene,
  List<String> names, {
  String? chip = 'Wanted',
}) async {
  Finder text(String value) =>
      find.descendant(of: scene, matching: find.text(value));
  // The chip: the service's tab bar has a Wanted of its own.
  if (chip != null) {
    await tester.tap(
      find.descendant(
        of: find.descendant(
          of: scene,
          matching: find.byType(MediaBrowseFilterChip),
        ),
        matching: find.text(chip),
      ),
    );
    await _land(tester);
  }
  await tester.longPress(text(names.first));
  await _land(tester);
  for (final name in names.skip(1)) {
    await tester.tap(text(name));
    await _land(tester);
  }
}

/// Lidarr's refusal of one artist's folder, as the editor sends it.
final _folderRefusal = DioException(
  requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
    statusCode: 400,
    data: [
      {
        'propertyName': 'RootFolderPath',
        'errorMessage': 'The folder /music/Charles Mingus is not reachable',
      },
    ],
  ),
  type: DioExceptionType.badResponse,
);

/// The four actions, each running at once, and each leaving Charles Mingus
/// refused and the other two taken.
MediaBulk<LidarrArtist> _partialBulk() => MediaBulk<LidarrArtist>(
  singular: 'artist',
  plural: 'artists',
  noneHint: 'Select an artist first',
  service: ServiceKey.lidarr,
  instanceId: '',
  actions: [
    for (final (label, icon) in const [
      ('Search', Icons.search_rounded),
      ('Monitor', Icons.visibility_rounded),
      ('Profile', Icons.tune_rounded),
      ('Remove', Icons.delete_outline_rounded),
    ])
      MediaBulkAction<LidarrArtist>(
        label: label,
        icon: icon,
        prepare: (context, artists) async => MediaBulkJob<LidarrArtist>(
          run: (items) async => MediaBulkOutcome(
            done: [
              for (final artist in items)
                if (artist.artistName != 'Charles Mingus') artist.id,
            ],
            failures: [
              MediaBulkFailure(
                id: 4,
                name: 'Charles Mingus',
                line: lidarrRefusalLine(
                  'Charles Mingus',
                  _folderRefusal,
                  'Lidarr',
                ),
                error: _folderRefusal,
              ),
            ],
          ),
          doneLine: (count) => 'Updated $count',
          partialLine: (done, total) => '$done of $total artists updated',
        ),
      ),
  ],
);

// === Movies, Series and Authors: selecting =================================

/// The wall of Movies as the router builds it in the service's Library tab,
/// over the films that start with M, N and S (so a section is a row or two),
/// with [bulk] as the actions.
Widget _filmWall({
  MediaBulk<_Film>? bulk,
  String title = 'Movies',
  FutureProvider<List<_Film>>? library,
  IconData posterIcon = Icons.movie_outlined,
}) => _scaffold(
  14,
  library: library ?? _shelfProvider,
  posterIcon: posterIcon,
  cutoff: null,
  sorts: false,
  peek: false,
  title: title,
  bulk: bulk,
  showAppBar: false,
  topPadding: kToolbarHeight + ServiceTabBar.height,
);

/// Series for Sonarr's wall: records of the same shape as the films, with
/// series' titles and no artwork.
final _showsProvider = FutureProvider<List<_Film>>(
  (ref) async => [
    for (final (id, title, year) in const [
      (1, 'Chernobyl', 2019),
      (2, 'Cosmos Laundromat', 2015),
      (3, 'Cowboy Bebop', 1998),
      (4, 'Firefly', 2002),
      (5, 'Fringe', 2008),
      (6, 'Hannibal', 2013),
      (7, 'Hero', 2018),
    ])
      (
        id: id,
        title: title,
        sortTitle: title.toLowerCase(),
        year: year,
        poster: null,
        status: const MediaStatusInfo(
          availability: MediaAvailability.available,
        ),
        added: '2026-09-1${id}T10:00:00Z',
      ),
  ],
);

/// Radarr's refusal of one movie's folder, as the editor sends it.
final _radarrRefusal = DioException(
  requestOptions: RequestOptions(path: '/api/v3/movie/editor'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/v3/movie/editor'),
    statusCode: 400,
    data: [
      {
        'propertyName': 'RootFolderPath',
        'errorMessage': 'The folder /movies/Metropolis is not reachable',
      },
    ],
  ),
  type: DioExceptionType.badResponse,
);

/// The four actions of Movies' wall, each running at once and each leaving
/// Metropolis refused and the others taken.
MediaBulk<_Film> _filmBulk({ArrBulkKind kind = radarrBulkKind}) =>
    MediaBulk<_Film>(
      singular: kind.singular,
      plural: kind.plural,
      noneHint: kind.noneHint,
      service: kind.service,
      instanceId: '',
      actions: [
        for (final (label, icon) in const [
          ('Search', Icons.search_rounded),
          ('Monitor', Icons.visibility_rounded),
          ('Profile', Icons.tune_rounded),
          ('Remove', Icons.delete_outline_rounded),
        ])
          MediaBulkAction<_Film>(
            label: label,
            icon: icon,
            prepare: (context, films) async => MediaBulkJob<_Film>(
              run: (items) async => MediaBulkOutcome(
                done: [
                  for (final film in items)
                    if (film.title != 'Metropolis') film.id,
                ],
                failures: [
                  MediaBulkFailure(
                    id: 2,
                    name: 'Metropolis',
                    line: arrRefusalLine(
                      'Metropolis',
                      _radarrRefusal,
                      ServiceKey.radarr,
                      'Radarr',
                    ),
                    error: _radarrRefusal,
                  ),
                ],
              ),
              doneLine: (count) => 'Updated $count',
              partialLine: (done, total) =>
                  '$done of $total ${kind.plural} updated',
            ),
          ),
      ],
    );

/// Three authors, with what their files take adding up to 61.4 GB.
final _selectAuthors = [
  for (final (id, name, gigabytes) in const [
    (1, 'Brandon Sanderson', 23.0),
    (2, 'Jules Renard', 18.3),
    (3, 'Jules Verne', 20.1),
  ])
    ReadarrAuthor(
      id: id,
      authorName: name,
      monitored: true,
      bookCount: 7,
      bookFileCount: 6,
      qualityProfileId: 1,
      metadataProfileId: 1,
      monitorNewItems: 'all',
      sizeOnDisk: (gigabytes * 1024 * 1024 * 1024).round(),
    ),
];

/// Readarr's wall as the router builds it in the service's Library tab, over
/// [_selectAuthors], with the real actions: the confirmation opens on the
/// scene's own navigator.
Widget _authorsWall() => Consumer(
  builder: (context, ref, _) => MediaBrowseScaffold<ReadarrAuthor>(
    title: 'Authors',
    searchHint: 'Authors',
    activityRoute: '/activity',
    navigationSection: NavigationSection.stack,
    serviceName: 'Readarr',
    service: ServiceKey.readarr,
    accentColor: ServiceKey.readarr.accent,
    heroTagPrefix: 'author',
    libraryProvider: readarrAuthorsProvider,
    searchQueryProvider: readarrSearchQueryProvider,
    find: MediaFind.libraryOnly(
      libraryBody: (context, query) => const SizedBox.shrink(),
    ),
    titleExtractor: (author) => author.authorName,
    subtitleExtractor: readarrAuthorCaption,
    sortTitleExtractor: (author) => author.authorName,
    imagesExtractor: (author) => author.images,
    idExtractor: (author) => author.id,
    settingsSelector: (_) => ('', '', const NoAccess()),
    onItemTap: (_, _, _) {},
    tileShape: MediaBrowseTileShape.circle,
    showAppBar: false,
    topPadding: kToolbarHeight + ServiceTabBar.height,
    bulk: readarrBulk(
      ref: ref,
      instanceId: '',
      name: 'Readarr',
      dialogsOnRoot: false,
    ),
  ),
);

/// The wall in the shell, the actions asking what they ask: the sheet and the
/// confirmation are the scene's own [Navigator]'s, so the sheet draws them.
Widget _shelled(Widget wall, {ServiceKey service = ServiceKey.lidarr}) =>
    ClipRect(
      child: Navigator(
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => _CatalogShell(wall: wall, service: service),
        ),
      ),
    );

/// A sheet drawn in place over the selecting wall, as the sheet's card draws
/// its panels: the panel is the real one, and the scrim stands for the route
/// a modal would be.
CatalogScene _sheetScene(
  String caption, {
  required String id,
  required Widget sheet,
}) => CatalogScene(
  caption,
  (_) => _phone(
    Stack(
      fit: StackFit.expand,
      children: [
        _CatalogShell(wall: _selectWall(bulk: _partialBulk())),
        // Takes no touch: the wall under it is selected before it is drawn.
        const IgnorePointer(child: ColoredBox(color: Colors.black54)),
        IgnorePointer(
          child: Align(alignment: Alignment.bottomCenter, child: sheet),
        ),
      ],
    ),
  ),
  id: id,
  overrides: _selectOverrides(),
  act: _selectThree,
);

CatalogScene _selectScene(
  String caption, {
  required String id,
  MediaBulk<LidarrArtist>? bulk,
  Future<void> Function(WidgetTester, Finder)? act,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => _phone(_CatalogShell(wall: _selectWall(bulk: bulk ?? _partialBulk()))),
  id: id,
  textScale: textScale,
  overrides: _selectOverrides(),
  act: act ?? _selectThree,
);

/// The tablet: the rail stays, the wall is the list column with its bar at the
/// foot, and the title the list opened is the pane beside it, as it was.
Widget _tablet(BuildContext context) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: FloatingNavRail.margin),
      child: Align(
        widthFactor: 1,
        child: FloatingNavRail(
          selectedIndex: 3,
          destinations: _navDestinations,
          onDestinationSelected: (_) {},
        ),
      ),
    ),
    SizedBox(
      width: 440,
      child: _selectWall(bulk: _partialBulk(), chrome: false),
    ),
    Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: CupolaRoom.of(context).hair)),
        ),
        child: Center(
          child: Text(
            'The pane, as it was',
            style: AppType.meta.copyWith(
              color: CupolaRoom.of(context).inkSecondary,
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  catalogCard(
    'MediaBrowseScaffold',
    width: 1706,
    overrides: () async => [
      // A Radarr with an address, so the service-aware failure has a host to
      // name; nothing else on the sheet reads settings but the image auth.
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices(const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.readarr,
          ServiceKey.lidarr,
        ]),
      ),
    ],
    scenes: [
      CatalogScene(
        'MediaBrowseScaffold · library under Title A–Z, Lidarr\'s circular '
        'wall, then no sort choices and no cutoff source · letter headings '
        '(# for a digit) only over the alphabetical order; the sort control '
        'only with two orders',
        (_) => _phones([
          _scaffold(1, library: _shelfProvider),
          _scaffold(
            2,
            library: _shelfProvider,
            title: 'Artists',
            shape: MediaBrowseTileShape.circle,
            peek: false,
          ),
          _scaffold(3, sorts: false, cutoff: null, peek: false),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · a wall with no status to resolve (Readarr\'s '
        'authors): circular, the sort control alone on the strip, no status '
        'chips, no peek · and with neither chips nor sort the strip is not '
        'drawn · an empty library with its own glyph and line',
        (_) => _phones([
          _scaffold(
            15,
            library: _shelfProvider,
            title: 'Authors',
            shape: MediaBrowseTileShape.circle,
            peek: false,
            status: false,
            cutoff: null,
          ),
          _scaffold(
            0,
            library: _shelfProvider,
            title: 'Authors',
            shape: MediaBrowseTileShape.circle,
            peek: false,
            status: false,
            sorts: false,
            cutoff: null,
          ),
          _scaffold(
            6,
            library: _emptyProvider,
            title: 'Authors',
            peek: false,
            status: false,
            sorts: false,
            cutoff: null,
            emptyIcon: Icons.menu_book_outlined,
            emptyMessage: 'Authors are added in the service itself.',
          ),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · loading, a failed load with no service, the '
        'same failure with service: (ServiceOfflineState.failure: cause, '
        'address, Settings), not configured · search and chips stay put',
        (_) => _phones([
          _scaffold(7, library: _pendingProvider),
          _scaffold(8, library: _failingProvider),
          _scaffold(12, library: _failingProvider, service: ServiceKey.radarr),
          _scaffold(9, library: _unconfiguredProvider),
        ]),
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, your library · the field holds '
        '"sh": the control under it, one section headed by its count and its '
        'noun, a poster with its year and runtime, and the word the wall '
        'says (Available, Missing)',
        _moviesFinder,
        query: 'sh',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Series, your library · the count '
        '(12 series, 1 series), the year and the seasons, the wall’s '
        'word',
        _seriesFinder,
        query: 'co',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, Radarr · the lookup as the '
        'rows Discover draws: held where it is, the plus for what is not',
        _moviesFinder,
        query: 'sh',
        scope: MediaFindScope.service,
        movieLookup: () async => _radarrLookup,
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Authors · a library only: no control, '
        'the disc and the caption the wall’s tile carries',
        _authorsFinder,
        query: 'jules',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Authors, nothing found · no button: '
        'there is nothing to ask',
        _authorsFinder,
        query: 'tolkien',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, nothing in the library · the '
        'line and the way to Radarr as an outlined button',
        _moviesFinder,
        query: 'zzz',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, Radarr, asked · the heading '
        'over four poster plates',
        _moviesFinder,
        query: 'sh',
        scope: MediaFindScope.service,
        movieLookup: () => Completer<List<RadarrMovie>?>().future,
        id: 'find-movies-asked',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, Radarr found nothing · the '
        'glyph and the line',
        _moviesFinder,
        query: 'zzz',
        scope: MediaFindScope.service,
        movieLookup: () async => const [],
        id: 'find-movies-nothing',
      ),
      _finderScene(
        'MediaBrowseScaffold · find on Movies, Radarr did not answer · the '
        'app’s own failure state',
        _moviesFinder,
        query: 'sh',
        scope: MediaFindScope.service,
        movieLookup: () => Future.error(
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v3/movie/lookup'),
            reason: 'Connection refused',
          ),
        ),
        id: 'find-movies-unreachable',
      ),
      _finderScene(
        'Text at 200% · find on Movies, your library: the heading, the rows '
        'and the meta at twice the reading size',
        _moviesFinder,
        query: 'sh',
        textScale: catalogTextScale,
        id: 'text-200-find-movies',
      ),
      _finderScene(
        'Text at 200% · find on Movies, Radarr: the held row and the plus',
        _moviesFinder,
        query: 'sh',
        scope: MediaFindScope.service,
        movieLookup: () async => _radarrLookup,
        textScale: catalogTextScale,
        id: 'text-200-find-radarr',
      ),
      CatalogScene(
        'MediaBrowseScaffold · 1280 desktop window · the wall sits in the '
        '1140 content well and adds columns at the 130 floor',
        (_) => _scaffold(10, library: _shelfProvider),
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
      ),
      _musicScene(
        'MediaBrowseScaffold · find, your library · the field holds "el": the '
        'segmented control under it, Artists and Albums each with its count, '
        'an album’s state in the one word the artist page uses, the '
        'caption that says what is searched',
        query: 'el',
      ),
      _musicScene(
        'MediaBrowseScaffold · find, your library, nothing found · the line, '
        'the way to Lidarr as an outlined button',
        query: 'elbo',
      ),
      _musicScene(
        'MediaBrowseScaffold · find, Lidarr · artists and albums the catalog '
        'found: held ones in their words, the rest with the add disc, an '
        'album left alone with the monitor disc',
        query: 'el',
        scope: MediaFindScope.service,
        search: () async => _musicCatalog,
      ),
      _musicScene(
        'MediaBrowseScaffold · find, Lidarr, asked · the heading over four '
        'skeleton rows',
        query: 'elbo',
        scope: MediaFindScope.service,
        search: () => Completer<List<LidarrSearchHit>?>().future,
      ),
      _musicScene(
        'MediaBrowseScaffold · find, Lidarr answered and its catalog did '
        'not · the amber card with Retry, the library still works',
        query: 'elbo',
        scope: MediaFindScope.service,
        search: () => Future.error(const LidarrCatalogUnavailable('down')),
      ),
      _musicScene(
        'MediaBrowseScaffold · find, Lidarr found nothing · what Lidarr '
        'finds, and not songs',
        query: 'smells like',
        scope: MediaFindScope.service,
        search: () async => const [],
      ),
      _musicScene(
        'MediaBrowseScaffold · find, Lidarr did not answer · the app’s '
        'own failure state, named for the service',
        query: 'elbo',
        scope: MediaFindScope.service,
        search: () => Future.error(
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/search'),
            reason: 'Connection refused',
          ),
        ),
      ),
      _musicScene(
        'Text at 200% · find, your library: the control, the headings and '
        'the rows at twice the reading size',
        query: 'el',
        textScale: catalogTextScale,
        id: 'text-200-find-library',
      ),
      _musicScene(
        'Text at 200% · find, Lidarr: the rows and their discs at twice the '
        'reading size',
        query: 'el',
        scope: MediaFindScope.service,
        search: () async => _musicCatalog,
        textScale: catalogTextScale,
        id: 'text-200-find-lidarr',
      ),
      CatalogScene(
        'MediaBrowseScaffold · find on a 1280 desktop window · the results sit '
        'in the 1140 well',
        (_) => _music(),
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
        overrides: _musicOverrides('el', MediaFindScope.library, null),
      ),
      _lidarrWallScene(
        'MediaBrowseScaffold · Lidarr, Title A–Z, long wall · the A–Z strip '
        'on the right edge, 28 wide, the wall giving it 28 of margin; letters '
        'with no artist (Q, U, X, Z) dimmed',
        id: 'index-lidarr',
      ),
      _lidarrWallScene(
        'MediaBrowseScaffold · the strip under a finger · the letter large in '
        'a 72 bubble left of the strip, centred on it, while the finger is '
        'down; the wall is already at that letter',
        id: 'index-dragging',
        act: (tester, scene) => _holdStrip(tester, scene, 0.46),
      ),
      _lidarrWallScene(
        'MediaBrowseScaffold · Lidarr, Wanted chip · it stands where Missing '
        'does on the other walls; each tile says how many albums are wanted, '
        'and a line under the chips says what wanted means',
        id: 'wanted-lidarr',
        act: (tester, scene) async {
          final chip = find.descendant(
            of: scene,
            matching: find.text('Wanted'),
          );
          await tester.tap(chip);
          await tester.pump(const Duration(milliseconds: 400));
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · Movies, Title A–Z, long wall · the same strip '
        'over posters',
        (_) => _phone(_scaffold(11, library: _longFilmsProvider, cutoff: null)),
        id: 'index-movies',
      ),
      _lidarrWallScene(
        'Text at 200% · the strip: letters take their larger line height, and '
        'what no longer fits is a dot for the letters left out',
        textScale: catalogTextScale,
        id: 'text-200-index',
      ),
      _lidarrWallScene(
        'MediaBrowseScaffold · 1280 desktop window · the strip at the edge of '
        'the 1140 well, which the wall gives 28 of margin',
        id: 'index-desktop',
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
      ),
      _selectScene(
        'MediaBrowseScaffold · selecting, Lidarr · Cancel, the count and '
        'Select all 34 in place of the band and the field; a check disc on '
        'each tile, the unselected dimmed; the selection bar where the '
        'navigation bar was, the navigation bar gone',
        id: 'select-lidarr',
      ),
      _selectScene(
        'MediaBrowseScaffold · selecting with nothing selected · the four '
        'actions dimmed and still tappable, carrying why as their hint',
        id: 'select-none',
        act: (tester, scene) async {
          // The toast a tap on an action answers with is the scaffold
          // messenger's, shared by every scene of the sheet and gone before
          // the sheet is drawn: `media_browse_scaffold_selection_test.dart`
          // holds it.
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select')),
          );
          await _land(tester);
        },
      ),
      _selectScene(
        'MediaBrowseScaffold · selecting, a title the chip hides · it stays '
        'selected and counted, and the header says how many the chip hides',
        id: 'select-hidden',
        act: (tester, scene) async {
          await _selectThree(tester, scene);
          // Charles Mingus is the one artist the library reads as missing
          // (`_selectWall`), so the chip for what is available hides him.
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Available')),
          );
          await _land(tester);
        },
      ),
      _sheetScene(
        'MediaBrowseScaffold · Monitor, over the selection · the artists '
        'named under the title, Monitor and Leave as is as they start',
        id: 'select-monitor',
        sheet: AppBottomSheet(
          title: 'Monitor 3 artists',
          subtitle: 'Bill Evans, Brian Eno and Charles Mingus',
          child: LidarrBulkMonitorSheet(
            artists: [
              for (final index in const [1, 2, 3]) _selectArtists[index],
            ],
          ),
        ),
      ),
      _sheetScene(
        'MediaBrowseScaffold · Profile, over the selection · the artists '
        'differ in quality, so Leave as is; they share a metadata profile; '
        'Apply is not live until something changes',
        id: 'select-profile',
        sheet: AppBottomSheet(
          title: 'Profiles for 3 artists',
          subtitle: 'Bill Evans, Brian Eno and Charles Mingus',
          child: LidarrBulkProfileSheet(
            artists: [
              for (final index in const [1, 2, 3]) _selectArtists[index],
            ],
            instanceId: 'catalog',
          ),
        ),
      ),
      CatalogScene(
        'MediaBrowseScaffold · Remove, over the selection · the app’s own '
        'confirmation: what Lidarr stops, the size the files take, the '
        'exclusion, and the confirm naming what it does',
        (_) => _phone(
          Consumer(
            builder: (context, ref, _) => _shelled(
              _selectWall(
                bulk: lidarrBulk(
                  ref: ref,
                  instanceId: '',
                  name: 'Lidarr',
                  dialogsOnRoot: false,
                ),
              ),
            ),
          ),
        ),
        id: 'select-remove',
        overrides: _selectOverrides(),
        act: (tester, scene) async {
          await _selectThree(tester, scene);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-remove')),
            ),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · Remove, a title the chip hides · the three are '
        'selected and the chip hides one: the confirmation counts and sizes '
        'only the two the wall shows',
        (_) => _phone(
          Consumer(
            builder: (context, ref, _) => _shelled(
              _selectWall(
                bulk: lidarrBulk(
                  ref: ref,
                  instanceId: '',
                  name: 'Lidarr',
                  dialogsOnRoot: false,
                ),
              ),
            ),
          ),
        ),
        id: 'select-remove-hidden',
        overrides: _selectOverrides(),
        act: (tester, scene) async {
          await _selectThree(tester, scene);
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Available')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-remove')),
            ),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · Search over fifty-one artists · above fifty the '
        'wall asks first: how many, that Lidarr goes one by one, and that '
        'the searches cannot be stopped from here',
        (_) => _phone(
          Consumer(
            builder: (context, ref, _) => _shelled(
              _selectWall(
                bulk: lidarrBulk(
                  ref: ref,
                  instanceId: '',
                  name: 'Lidarr',
                  dialogsOnRoot: false,
                ),
              ),
            ),
          ),
        ),
        id: 'select-search-many',
        overrides: [
          // The board's nine and forty-two more: the wall reads these.
          ..._selectOverrides().skip(1),
          musicProvider.overrideWith(
            (ref) async => [
              ..._selectArtists,
              for (var id = 10; id < 52; id++)
                LidarrArtist(
                  id: id,
                  artistName: 'Artist $id',
                  foreignArtistId: 'mb-select-$id',
                  status: 'continuing',
                  monitored: true,
                  images: const [],
                  genres: const [],
                  monitorNewItems: 'all',
                  qualityProfileId: 1,
                  metadataProfileId: 1,
                  statistics: const {'albumCount': 1, 'sizeOnDisk': 1 << 30},
                ),
            ],
          ),
        ],
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.textContaining('Select all'),
            ),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-search')),
            ),
          );
          await _land(tester);
        },
      ),
      _selectScene(
        'MediaBrowseScaffold · after an action Lidarr refused for one artist '
        '· the amber notice over the wall: how many were updated, the refusal '
        'in Lidarr’s words naming the artist, and Try Charles Mingus again; the '
        'selection has ended and the navigation bar is back',
        id: 'select-partial',
        act: (tester, scene) async {
          await _selectThree(tester, scene);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-monitor')),
            ),
          );
          await _land(tester);
        },
      ),
      _selectScene(
        'Text at 200% · selecting: the header stacks its count under Cancel '
        'and Select all, the bar’s names stay in their columns',
        id: 'text-200-select',
        textScale: catalogTextScale,
        // At twice the size the first rows fill the screen, so all nine are
        // selected from the header rather than reached one by one.
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select all 9')),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · selecting on a tablet · the rail stays, the '
        'bar floats at the foot of the list column, the pane is as it was',
        _tablet,
        id: 'select-tablet',
        width: 1024,
        height: 760,
        overrides: _selectOverrides(),
        // The bar floats over the foot of the list, so the three are the
        // first that are clear of it.
        act: (tester, scene) => _selectNamed(tester, scene, const [
          'Anton Bruckner',
          'Bill Evans',
          'Brian Eno',
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · selecting on a 1280 desktop window · the bar '
        'at the foot of the 1140 well',
        (_) => _selectWall(bulk: _partialBulk(), chrome: false),
        id: 'select-desktop',
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
        overrides: _selectOverrides(),
        act: _selectThree,
      ),
      CatalogScene(
        'MediaBrowseScaffold · selecting, Movies · the same bar on a poster '
        'wall: the check disc on the poster’s corner, unselected posters '
        'dimmed, the bar where the navigation bar was',
        (_) => _phone(
          _CatalogShell(
            service: ServiceKey.radarr,
            wall: _filmWall(bulk: _filmBulk()),
          ),
        ),
        id: 'select-movies',
        act: (tester, scene) => _selectNamed(tester, scene, const [
          'Nanook of the North',
          'The Navigator',
          'Nosferatu',
        ], chip: null),
      ),
      CatalogScene(
        'MediaBrowseScaffold · Series, Monitor, over the selection · '
        '`Monitor new seasons` is Sonarr’s own second control, started on '
        'what the series share',
        (_) => _phone(
          Stack(
            fit: StackFit.expand,
            children: [
              _CatalogShell(
                service: ServiceKey.sonarr,
                wall: _filmWall(
                  title: 'TV series',
                  library: _showsProvider,
                  posterIcon: Icons.tv_outlined,
                  bulk: _filmBulk(kind: sonarrBulkKind),
                ),
              ),
              const IgnorePointer(child: ColoredBox(color: Colors.black54)),
              IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AppBottomSheet(
                    title: 'Monitor 3 series',
                    subtitle: 'Chernobyl, Cosmos Laundromat and Cowboy Bebop',
                    child: const ArrBulkMonitorSheet(
                      kind: sonarrBulkKind,
                      count: 3,
                      startMonitored: true,
                      startNewItems: 'all',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        id: 'select-series-monitor',
        act: (tester, scene) => _selectNamed(tester, scene, const [
          'Chernobyl',
          'Cosmos Laundromat',
          'Cowboy Bebop',
        ], chip: null),
      ),
      CatalogScene(
        'MediaBrowseScaffold · Authors, Remove, over the selection · the '
        'confirmation in Readarr’s words: what it stops, the size the files '
        'take, the exclusion',
        (_) => _phone(_shelled(_authorsWall(), service: ServiceKey.readarr)),
        id: 'select-authors-remove',
        overrides: [
          readarrAuthorsProvider.overrideWith((ref) async => _selectAuthors),
          readarrSearchQueryProvider.overrideWith((ref) => ''),
        ],
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select all 3')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-remove')),
            ),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · after an action Radarr refused for one movie '
        '· the amber notice in the movies’ words, `Try Metropolis again`',
        (_) => _phone(
          _CatalogShell(
            service: ServiceKey.radarr,
            wall: _filmWall(bulk: _filmBulk()),
          ),
        ),
        id: 'select-movies-partial',
        act: (tester, scene) async {
          await _selectNamed(tester, scene, const [
            'Metropolis',
            'Nanook of the North',
            'The Navigator',
          ], chip: null);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byKey(const ValueKey('library-selection-monitor')),
            ),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'Text at 200% · selecting on Movies: the header stacks, the poster '
        'discs and the bar hold',
        (_) => _phone(
          _CatalogShell(
            service: ServiceKey.radarr,
            wall: _filmWall(bulk: _filmBulk()),
          ),
        ),
        id: 'text-200-select-movies',
        textScale: catalogTextScale,
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Select')),
          );
          await _land(tester);
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.textContaining('Select all'),
            ),
          );
          await _land(tester);
        },
      ),
      CatalogScene(
        'MediaBrowseScaffold · selecting Movies on a 1280 desktop window · '
        'the bar at the foot of the 1140 well',
        (_) => _filmWall(bulk: _filmBulk()),
        id: 'select-movies-desktop',
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
        act: (tester, scene) => _selectNamed(tester, scene, const [
          'Nanook of the North',
          'The Navigator',
          'Nosferatu',
        ], chip: null),
      ),
      CatalogScene(
        'Text at 200% · the library wall and a failed load with service: the '
        'header, the chips, the tile titles and the failure at twice the '
        'reading size',
        (_) => _phones([
          _scaffold(0, library: _shelfProvider),
          _scaffold(13, library: _failingProvider, service: ServiceKey.radarr),
        ]),
        textScale: catalogTextScale,
      ),
    ],
  );
}
