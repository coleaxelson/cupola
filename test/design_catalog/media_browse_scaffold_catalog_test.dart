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
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
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

FutureProvider<List<_Film>?> _resultsFor(StateProvider<String> query) =>
    FutureProvider<List<_Film>?>((ref) async {
      final text = ref.watch(query).toLowerCase();
      if (text.isEmpty) return null;
      return [
        for (final film in _library)
          if (film.title.toLowerCase().contains(text)) film,
      ];
    });

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

final _results = [for (final query in _queries) _resultsFor(query)];

/// A search that never answers, to show the spinner it draws meanwhile.
final _pendingResults = FutureProvider<List<_Film>?>(
  (ref) => Completer<List<_Film>?>().future,
);

Widget _scaffold(
  int phone, {
  FutureProvider<List<_Film>>? library,
  bool peek = true,
  bool sorts = true,
  Set<int>? cutoff = const {5},
  MediaBrowseTileShape shape = MediaBrowseTileShape.poster,
  String title = 'Movies',
  FutureProvider<List<_Film>?>? results,
  ServiceKey? service,
  bool status = true,
  IconData emptyIcon = Icons.video_library_outlined,
  String? emptyMessage,
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
    searchHeroTagPrefix: 'movie_search',
    libraryProvider: library ?? _libraryProvider,
    searchQueryProvider: _queries[phone],
    searchResultsProvider: results ?? _results[phone],
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

/// Types [text] into the first text field below it once it has laid out, the
/// way a user would: the scaffold's field owns its own controller, so a
/// preset query would leave the field blank.
class _Typed extends StatefulWidget {
  const _Typed({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  State<_Typed> createState() => _TypedState();
}

class _TypedState extends State<_Typed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EditableTextState? field;
      void visit(Element element) {
        if (field != null) return;
        if (element is StatefulElement && element.state is EditableTextState) {
          field = element.state as EditableTextState;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      field?.userUpdateTextEditingValue(
        TextEditingValue(
          text: widget.text,
          selection: TextSelection.collapsed(offset: widget.text.length),
        ),
        SelectionChangedCause.keyboard,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
  searchHeroTagPrefix: 'artist_search',
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

void main() {
  catalogCard(
    'MediaBrowseScaffold',
    width: 1706,
    overrides: () async => [
      // A Radarr with an address, so the service-aware failure has a host to
      // name; nothing else on the sheet reads settings but the image auth.
      currentSettingsProvider.overrideWith(
        (ref) =>
            settingsWithServices(const [ServiceKey.radarr, ServiceKey.lidarr]),
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
        'MediaBrowseScaffold · searching "Nosferatu", a search with no '
        'match, an empty library · results are a MediaGrid with compact '
        'badges; back arrow exits search',
        (_) => _phones([
          _Typed(text: 'Nosferatu', child: _scaffold(4)),
          _Typed(text: 'Wisborg', child: _scaffold(5)),
          _scaffold(6, library: _emptyProvider),
        ]),
      ),
      CatalogScene(
        'MediaBrowseScaffold · searching, results pending · the spinner in '
        'the primary ink: the service accent is the lamp, and onTint resolves '
        'it to ink',
        (_) => _phones([
          _Typed(
            text: 'Nosferatu',
            child: _scaffold(11, results: _pendingResults),
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
      CatalogScene(
        'Text at 200% · the library wall, a failed load with service: and a '
        'search for Nosferatu: the header, the chips, the tile titles and the '
        'failure at twice the reading size',
        (_) => _phones([
          _scaffold(0, library: _shelfProvider),
          _scaffold(13, library: _failingProvider, service: ServiceKey.radarr),
          _Typed(text: 'Nosferatu', child: _scaffold(14)),
        ]),
        textScale: catalogTextScale,
      ),
    ],
  );
}
