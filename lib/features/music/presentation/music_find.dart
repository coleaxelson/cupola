import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/lidarr_artist_caption.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/domain/music_find_index.dart';
import 'package:cupola/features/music/presentation/music_add_flow.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _artistTypes = ['poster', 'fanart', 'banner'];

typedef _Reach = ({String baseUrl, String apiKey});

/// Where the wall's artwork is read from and with what key: the lens's
/// connection at the address it is reached at now.
_Reach _watchReach(WidgetRef ref) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
  final route = ref.watch(connectionRouteProvider(lens));
  final (baseUrl, apiKey, _) = ref.watch(
    currentSettingsProvider.select((s) => s.artworkKeyOf(lens, route)),
  );
  return (baseUrl: baseUrl, apiKey: apiKey);
}

ImageSource _artOf(List<dynamic> images, List<String> types, _Reach reach) =>
    ImageUtils.extractPosterUrl(
      images,
      baseUrl: reach.baseUrl,
      apiKey: reach.apiKey,
      coverTypes: types,
    );

/// The padding under a list of results: the room the floating nav bar takes.
EdgeInsets _listPadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.lg,
  AppSpacing.sm,
  AppSpacing.lg,
  AppSpacing.lg + FloatingNavBarMetrics.getScrollViewBottomPadding(context),
);

/// What the Music wall's name for the connection reads inside a sentence.
String _watchName(WidgetRef ref) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr));
  final settings = ref.watch(currentSettingsProvider);
  return settings.connectionTitle(
    lens?.id ?? '',
    ServiceKey.lidarr,
    joiner: ' ',
  );
}

/// The state of a row, in the words the rows share.
({String label, StatusTone tone}) _status(AlbumState state) =>
    (label: state.word, tone: state.tone);

/// A section's heading over rows that are lazily built, with its count.
class _Section {
  const _Section(this.title, this.count, this.top);

  final String title;
  final int count;
  final double top;
}

/// The Music wall's search of its own library: artists by name and albums by
/// title, a word typed being the start of a word in either, answered as it is
/// typed from what the wall already read.
///
/// Two sections, `Artists` and `Albums`, each with how many it found. The rows
/// are built as they scroll in: a library of thousands matches `the` in
/// thousands of albums. An album opens its artist's page (Lidarr has no page
/// of an album). Nothing found is said once, with the way to ask Lidarr.
class MusicFindLibrary extends ConsumerStatefulWidget {
  const MusicFindLibrary({
    super.key,
    required this.query,
    required this.onAskLidarr,
  });

  final String query;

  /// Moves the search to Lidarr, with the same words.
  final VoidCallback onAskLidarr;

  @override
  ConsumerState<MusicFindLibrary> createState() => _MusicFindLibraryState();
}

class _MusicFindLibraryState extends ConsumerState<MusicFindLibrary> {
  /// The index of the lists it was built from: a keystroke searches it, and
  /// only a new library builds another.
  MusicFindIndex? _index;
  List<LidarrArtist>? _indexedArtists;
  List<LidarrAlbum>? _indexedAlbums;
  Map<int, LidarrArtist> _artistsById = const {};

  MusicFindIndex _indexFor(
    List<LidarrArtist> artists,
    List<LidarrAlbum> albums,
  ) {
    if (_index == null ||
        !identical(artists, _indexedArtists) ||
        !identical(albums, _indexedAlbums)) {
      _indexedArtists = artists;
      _indexedAlbums = albums;
      _artistsById = {for (final artist in artists) artist.id: artist};
      _index = MusicFindIndex(artists: artists, albums: albums);
    }
    return _index!;
  }

  void _openArtist(LidarrArtist artist) {
    context.push(ServiceRoutes.lidarrArtist(artist.id), extra: artist);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.lidarr),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.lidarr);
    }
    final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id;
    final name = _watchName(ref);
    final reach = _watchReach(ref);
    final artistsAsync = ref.watch(musicProvider);
    final albumsAsync = ref.watch(musicAlbumsProvider);
    final queue = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsProvider),
    ).byAlbum;

    if (!artistsAsync.hasValue) {
      if (artistsAsync.hasError) {
        return AppErrorState(
          error: artistsAsync.error!,
          service: ServiceKey.lidarr,
          instanceId: lens,
          onRetry: () => ref.invalidate(musicProvider),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final albums = albumsAsync.value ?? const <LidarrAlbum>[];
    final index = _indexFor(artistsAsync.requireValue, albums);
    final found = index.find(widget.query);
    final albumsPending = albumsAsync.isLoading && !albumsAsync.hasValue;
    final albumsFailed = albumsAsync.hasError && !albumsAsync.hasValue;
    final nothing = found.artists.isEmpty && found.albums.isEmpty;

    // Nothing is said of a library the search could not read in full.
    if (nothing && albumsPending) {
      return const _PendingAlbums();
    }
    if (nothing && !albumsFailed) {
      final asked = widget.query.trim();
      return ListView(
        padding: _listPadding(context),
        children: [
          SearchNothing(
            title: 'Nothing in your library called “$asked”',
            message: 'Lidarr can look further.',
            action: OutlinedButton.icon(
              onPressed: widget.onAskLidarr,
              icon: const Icon(Icons.search_rounded),
              label: Text('Search $name for “$asked”'),
            ),
          ),
        ],
      );
    }

    // A flat list of what is drawn, so that only what is on screen is built:
    // headings, the matches themselves (an artist or an album), and what
    // follows them.
    final entries = <Object>[
      if (found.artists.isNotEmpty) ...[
        _Section('Artists', found.artists.length, AppSpacing.lg),
        ...found.artists,
      ],
      if (found.albums.isNotEmpty) ...[
        _Section(
          'Albums',
          found.albums.length,
          found.artists.isEmpty ? AppSpacing.lg : AppSpacing.xl,
        ),
        ...found.albums,
      ],
      if (albumsPending) const _PendingAlbums(),
      if (albumsFailed)
        InlineErrorRetry.flush(
          message: 'Your albums did not load, so only artists are listed.',
          error: albumsAsync.error,
          service: ServiceKey.lidarr,
          instanceId: lens,
          onRetry: () => ref.invalidate(musicAlbumsProvider),
        ),
      if (!nothing) const _Footer(),
    ];
    final now = DateTime.now();
    return ListView.builder(
      padding: _listPadding(context),
      itemCount: entries.length,
      itemBuilder: (context, index) => switch (entries[index]) {
        _Section(:final title, :final count, :final top) => SearchHeading(
          title,
          count: count,
          top: top,
        ),
        LidarrArtist artist => _artistRow(artist, reach),
        LidarrAlbum album => _albumRow(album, reach, queue, now),
        final Widget widget => widget,
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _artistRow(LidarrArtist artist, _Reach reach) {
    final art = _artOf(artist.images, _artistTypes, reach);
    return SearchRow.disc(
      key: ValueKey(('artist', artist.id)),
      name: artist.artistName,
      line: lidarrArtistCaption(artist),
      photo: art.url,
      photoHeaders: art.headers,
      onTap: () => _openArtist(artist),
    );
  }

  Widget _albumRow(
    LidarrAlbum album,
    _Reach reach,
    ArrQueueSnapshot queue,
    DateTime now,
  ) {
    final artist = _artistsById[album.artistId];
    final state = albumState(album, queue: queue, now: now);
    final art = _artOf(album.images, const ['cover'], reach);
    return SearchRow.album(
      key: ValueKey(('album', album.id)),
      title: album.title,
      meta: joinDisplayParts([
        artist?.artistName,
        album.year,
        albumTrackCount(album),
      ]),
      status: state == null ? null : _status(state),
      statusHollow: state?.hollow ?? false,
      cover: art.url,
      coverHeaders: art.headers,
      hint: artist == null ? null : 'Opens ${artist.artistName}',
      onTap: artist == null ? () {} : () => _openArtist(artist),
    );
  }
}

/// The albums, still being read: the heading over two rows of plates.
class _PendingAlbums extends StatelessWidget {
  const _PendingAlbums();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ExcludeSemantics(
        child: SearchHeading('Albums', top: AppSpacing.lg),
      ),
      const SearchRowsPending(
        label: 'Reading your albums',
        rows: 2,
        shape: SearchRowsShape.square,
      ),
    ],
  );
}

/// What the list names, under it.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Text(
      'Names of artists and albums. Lidarr keeps albums, so a song is found by '
      'its album.',
      style: AppType.caption.copyWith(
        color: CupolaRoom.of(context).inkTertiary,
      ),
    ),
  );
}

/// The Music wall's search of Lidarr: its catalog's artists and albums for the
/// words typed ([query], once typing has paused), each with where it stands in
/// the library and what to do about it.
///
/// Held by the library, a row says so (`In your library`, or the album's own
/// state word: one album, one word, in both scopes) and opens the artist's
/// page. Not held, it carries a disc that adds it, with the sheet lot 1 built
/// for artists and the album's own; an album the library holds and left alone
/// carries one that monitors it and searches. Held is decided by MusicBrainz
/// id against the library, the way Lidarr's own search does.
class MusicFindLidarr extends ConsumerStatefulWidget {
  const MusicFindLidarr({super.key, required this.query});

  /// What Lidarr is asked, as the field holds it once typing has paused.
  final String query;

  @override
  ConsumerState<MusicFindLidarr> createState() => _MusicFindLidarrState();
}

class _MusicFindLidarrState extends ConsumerState<MusicFindLidarr> {
  /// The albums being monitored: their discs are busy, and inert.
  final _monitoring = <int>{};

  /// What the library holds, by MusicBrainz id, built once per library.
  List<LidarrArtist>? _heldFrom;
  List<LidarrAlbum>? _heldAlbumsFrom;
  Map<String, LidarrArtist> _artists = const {};
  Map<int, LidarrArtist> _artistsById = const {};
  Map<String, LidarrAlbum> _albums = const {};

  void _hold(List<LidarrArtist> artists, List<LidarrAlbum> albums) {
    if (identical(artists, _heldFrom) && identical(albums, _heldAlbumsFrom)) {
      return;
    }
    _heldFrom = artists;
    _heldAlbumsFrom = albums;
    _artists = {
      for (final artist in artists)
        if (artist.foreignArtistId.isNotEmpty) artist.foreignArtistId: artist,
    };
    _artistsById = {for (final artist in artists) artist.id: artist};
    _albums = {
      for (final album in albums)
        if (album.foreignAlbumId.isNotEmpty) album.foreignAlbumId: album,
    };
  }

  void _openArtist(LidarrArtist artist) {
    context.push(ServiceRoutes.lidarrArtist(artist.id), extra: artist);
  }

  Future<void> _monitor(LidarrAlbum album, String name) async {
    setState(() => _monitoring.add(album.id));
    try {
      await ref.read(lidarrServiceProvider).monitorAndSearchAlbum(album.id);
      if (!mounted) return;
      SnackBarHelper.success(context, '$name is looking for ${album.title}');
      ref.invalidate(musicAlbumsProvider);
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not monitor ${album.title} in $name.',
        detail: error,
      );
    } finally {
      if (mounted) setState(() => _monitoring.remove(album.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.lidarr),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.lidarr);
    }
    final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id;
    final name = _watchName(ref);
    final results = ref.watch(musicSearchResultsProvider);
    final artistsAsync = ref.watch(musicProvider);
    final albumsAsync = ref.watch(musicAlbumsProvider);

    void readAgain() {
      ref
        ..invalidate(musicSearchResultsProvider)
        ..invalidate(musicProvider)
        ..invalidate(musicAlbumsProvider);
    }

    // The search is asked, and so are the library reads that say which of
    // what it finds is already held.
    if (results.isLoading ||
        (!artistsAsync.hasValue && artistsAsync.isLoading) ||
        (!albumsAsync.hasValue && albumsAsync.isLoading)) {
      return ListView(
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SearchHeading('Asking $name', top: AppSpacing.lg),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SearchRowsPending(
              label: 'Asking $name',
              rows: 4,
              shape: SearchRowsShape.circle,
            ),
          ),
        ],
      );
    }
    if (results.hasError) {
      final error = results.error!;
      if (error is LidarrCatalogUnavailable) {
        // Lidarr answered: this is a fault, not silence, and the library
        // still works.
        return ListView(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          children: [
            InlineErrorRetry(
              message:
                  '$name answered, but its music catalog on the internet '
                  'did not. Your library still works.',
              error: const ClassifiedFailure(ServiceFailureReason.serverError),
              service: ServiceKey.lidarr,
              instanceId: lens,
              onRetry: () => ref.invalidate(musicSearchResultsProvider),
            ),
          ],
        );
      }
      return AppErrorState(
        error: error,
        service: ServiceKey.lidarr,
        instanceId: lens,
        serviceName: name,
        onRetry: () => ref.invalidate(musicSearchResultsProvider),
      );
    }
    // What says which results are held could not be read: a row cannot be
    // told from one that is not.
    if (!artistsAsync.hasValue || !albumsAsync.hasValue) {
      return AppErrorState(
        error: (artistsAsync.error ?? albumsAsync.error)!,
        service: ServiceKey.lidarr,
        instanceId: lens,
        serviceName: name,
        onRetry: readAgain,
      );
    }

    final hits = results.value ?? const <LidarrSearchHit>[];
    final artistHits = hits.whereType<LidarrArtistHit>().toList();
    final albumHits = hits.whereType<LidarrAlbumHit>().toList();
    if (artistHits.isEmpty && albumHits.isEmpty) {
      return ListView(
        children: [
          SearchNothing(
            icon: Icons.search_rounded,
            title: '$name found nothing called “${widget.query.trim()}”',
            message:
                'Lidarr finds artists and albums, not songs. Try the album '
                'the song is on, or the artist.',
          ),
        ],
      );
    }

    _hold(artistsAsync.requireValue, albumsAsync.requireValue);
    final reach = _watchReach(ref);
    final queue = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsProvider),
    ).byAlbum;
    final now = DateTime.now();
    return ListView(
      padding: _listPadding(context),
      children: [
        if (artistHits.isNotEmpty) ...[
          const SearchHeading('Artists', top: AppSpacing.lg),
          for (final hit in artistHits) _artistRow(hit, name, reach),
        ],
        if (albumHits.isNotEmpty) ...[
          SearchHeading(
            'Albums',
            top: artistHits.isEmpty ? AppSpacing.lg : AppSpacing.xl,
          ),
          for (final hit in albumHits) _albumRow(hit, name, reach, queue, now),
        ],
      ],
    );
  }

  Widget _artistRow(LidarrArtistHit hit, String name, _Reach reach) {
    final artist = hit.artist;
    final held = _artists[artist.foreignArtistId];
    final art = _artOf((held ?? artist).images, _artistTypes, reach);
    final add = held == null
        ? () => addLidarrArtist(context, ref, artist)
        : null;
    return SearchRow.disc(
      key: ValueKey((
        'found-artist',
        artist.foreignArtistId,
        artist.artistName,
      )),
      name: artist.artistName,
      line: joinDisplayParts([artist.artistType, artist.disambiguation]),
      status: held == null ? null : _inLibrary,
      photo: art.url,
      photoHeaders: art.headers,
      hint: held == null
          ? 'Not in your library. Adds it to $name'
          : 'Opens their page',
      onTap: held == null ? add! : () => _openArtist(held),
      action: held == null
          ? SearchRowAdd(
              label: 'Add ${artist.artistName} to $name',
              onTap: add!,
            )
          : null,
    );
  }

  Widget _albumRow(
    LidarrAlbumHit hit,
    String name,
    _Reach reach,
    ArrQueueSnapshot queue,
    DateTime now,
  ) {
    final album = hit.album;
    final heldAlbum = _albums[album.foreignAlbumId];
    final heldArtist = _artists[hit.artist.foreignArtistId];
    // A held album opens the artist the library keeps it under.
    final albumsArtist = heldAlbum == null
        ? null
        : _artistsById[heldAlbum.artistId];
    final state = heldAlbum == null
        ? null
        : albumState(heldAlbum, queue: queue, now: now);
    final leftAlone = state?.word == albumUnmonitoredWord;
    final art = _artOf((heldAlbum ?? album).images, const ['cover'], reach);
    void add() => addLidarrAlbum(context, ref, hit, libraryArtist: heldArtist);
    final busy = heldAlbum != null && _monitoring.contains(heldAlbum.id);
    final SearchRowAction? action = heldAlbum == null
        ? SearchRowAdd(
            label: 'Add ${album.title} by ${hit.artist.artistName} to $name',
            onTap: add,
          )
        : leftAlone
        ? SearchRowAdd(
            label: 'Monitor ${album.title} and search for it',
            busy: busy,
            onTap: () => _monitor(heldAlbum, name),
          )
        : null;
    return SearchRow.album(
      key: ValueKey(('found-album', album.foreignAlbumId)),
      title: album.title,
      meta: joinDisplayParts([
        hit.artist.artistName,
        album.year,
        album.albumType,
      ]),
      status: state == null ? null : _status(state),
      statusHollow: state?.hollow ?? false,
      cover: art.url,
      coverHeaders: art.headers,
      hint: heldAlbum == null
          ? 'Not in your library. Adds it to $name'
          : albumsArtist == null
          ? null
          : 'Opens ${albumsArtist.artistName}',
      onTap: heldAlbum != null
          ? (albumsArtist == null ? () {} : () => _openArtist(albumsArtist))
          : add,
      action: action,
    );
  }

  static final ({String label, StatusTone tone}) _inLibrary = (
    label: StateWord.inYourLibrary.label,
    tone: StateWord.inYourLibrary.tone!,
  );
}
