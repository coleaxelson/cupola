import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_artist_caption.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_find.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

export 'package:cupola/features/music/domain/lidarr_artist_caption.dart';

/// The artist ids Lidarr reports under `wanted/cutoff`.
///
/// Lidarr answers that route with *albums*, so the fold is over `artistId`: an
/// artist with four albums below cutoff is one id, which is the grain this
/// library browses at.
///
/// `getAllCutoff()` answers `[]` on its own failures rather than throwing, so
/// an empty set is "Lidarr had nothing to say" as much as "nothing is below
/// cutoff". A Lidarr that is not answering at all never gets here: the library
/// provider fails first and the wall goes under a fault band.
///
/// Only the ids are read, so the walk does not ask Lidarr to embed the artist
/// in every album.
final lidarrCutoffUnmetArtistIdsProvider = FutureProvider.autoDispose<Set<int>>(
  (ref) async {
    final records = await ref
        .watch(lidarrServiceProvider)
        .getAllCutoff(queryParameters: const {'includeArtist': false});
    return {
      for (final record in records.whereType<Map>())
        if (record['artistId'] case final int id) id,
    };
  },
);

class MusicScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MusicScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers: see `movies_screen.dart`.
    final queue = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsProvider),
    ).byArtist;
    final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
    // Which of its addresses the lens's connection is reached at: the
    // posters go where the library is read from.
    final route = ref.watch(connectionRouteProvider(lens));

    return MediaBrowseScaffold<LidarrArtist>(
      title: 'Music',
      searchHint: 'Artists and albums',
      activityRoute: '${ServiceRoutes.lidarr}/queue',
      navigationSection: NavigationSection.stack,
      serviceName: 'Lidarr',
      service: ServiceKey.lidarr,
      accentColor: ServiceKey.lidarr.accent,
      heroTagPrefix: 'artist',
      libraryProvider: musicProvider,
      searchQueryProvider: musicSearchQueryProvider,
      find: MediaFind(
        scopeProvider: musicFindScopeProvider,
        serviceLabel: ref.watch(
          currentSettingsProvider.select(
            (s) => s.connectionTitle(lens, ServiceKey.lidarr),
          ),
        ),
        libraryBody: (context, query) => MusicFindLibrary(
          query: query,
          onAskLidarr: () => ref.read(musicFindScopeProvider.notifier).state =
              MediaFindScope.service,
        ),
        serviceBody: (context, query) => MusicFindLidarr(query: query),
      ),
      titleExtractor: (artist) => artist.artistName,
      subtitleExtractor: lidarrArtistCaption,
      sortTitleExtractor: (artist) => artist.artistName,
      imagesExtractor: (artist) => artist.images,
      idExtractor: (artist) => artist.id,
      statusExtractor: (artist) => badgeOverQueue(
        lidarrArtistStatus(
          artist,
          queueEntry: queue.entryFor(artist.id),
          queueUnknown: !queue.isWhole,
        ),
        queue,
      ),
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper alone: that
        // one only resolves the lens and re-watches its family member, which
        // keeps the answer it already had.
        ref.invalidate(lidarrQueueSnapshotsForProvider);
        // The rail's own non-swallowing read. See `movies_screen.dart`.
        ref.invalidate(lidarrKpiLibraryProvider);
      },
      // The lens's connection, never the first one's: see `movies_screen.dart`.
      settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
      onItemTap: (context, artist, heroTag) {
        context.push(
          ServiceRoutes.lidarrArtist(artist.id, heroTag: heroTag),
          extra: artist,
        );
      },
      coverTypes: const ['poster', 'fanart', 'banner'],
      // An artist is not a poster. `LidarrArtists` draws a circular portrait
      // because a 2:3 crop of a band photograph invents artwork that does not
      // exist and cuts a face in half to do it.
      tileShape: MediaBrowseTileShape.circle,
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<LidarrArtist>.dateAdded((artist) => artist.added),
        MediaBrowseSort<LidarrArtist>.size(
          (artist) => switch (artist.statistics?['sizeOnDisk']) {
            final int bytes => bytes,
            final num bytes => bytes.toInt(),
            _ => 0,
          },
        ),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(lidarrCutoffUnmetArtistIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.lidarr)),
        service: ServiceKey.lidarr,
      ),
    );
  }
}
