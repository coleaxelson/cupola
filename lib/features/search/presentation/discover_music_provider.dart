import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/domain/music_held.dart';
import 'package:cupola/features/music/presentation/more_from_your_artists_provider.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What the music source finds for the words Discover's field holds: its
/// answer as it came, never a list for a source that did not answer.
///
/// Asked only with a music source ([hasMusicSourceProvider]) and a word typed.
/// The source is the lens's Lidarr (`/api/v1/search`, artists and albums
/// together, [LidarrService.search]); a catalog Lidarr could not reach is
/// [LidarrCatalogUnavailable]. The request carries a [CancelToken] cancelled on
/// dispose, so the round a keystroke supersedes stops (see
/// `musicSearchResultsProvider`, the Music wall's own ask). Not retried on its
/// own: Retry asks again.
final discoverMusicHitsProvider =
    FutureProvider.autoDispose<List<LidarrSearchHit>>((ref) async {
      final query = ref.watch(globalSearchQueryProvider).trim();
      if (query.isEmpty || !ref.watch(hasMusicSourceProvider)) {
        return const [];
      }
      final service = ref.watch(lidarrServiceProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return service.search(query, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// How many of the music source's hits the search shows; the Music wall,
/// one tap away, holds the rest.
const discoverMusicRows = 3;

/// Where the music source stands for the field's words: what Discover's
/// results draw for it.
sealed class DiscoverMusic {
  const DiscoverMusic();
}

/// Nothing is asked: no music source (the requester's Discover among them), or
/// nothing typed.
final class DiscoverMusicOff extends DiscoverMusic {
  const DiscoverMusicOff();
}

/// The source is still answering, after the others: or the library reads that
/// say which of its rows are held.
final class DiscoverMusicAsking extends DiscoverMusic {
  const DiscoverMusicAsking();
}

/// The source answered with something: [hits], its first [discoverMusicRows],
/// and what the library [held].
final class DiscoverMusicFound extends DiscoverMusic {
  const DiscoverMusicFound({required this.hits, required this.held});

  final List<LidarrSearchHit> hits;
  final MusicHeld held;
}

/// The source answered, and found nothing by that name.
final class DiscoverMusicNothing extends DiscoverMusic {
  const DiscoverMusicNothing();
}

/// The source stopped short of an answer, or an answer that cannot be told
/// held from not: a quiet line at the head of the results, as every source of
/// the search says it, in the [lane]'s words.
final class DiscoverMusicFault extends DiscoverMusic {
  const DiscoverMusicFault({
    required this.lane,
    this.sentence,
    this.readsLibrary = false,
  });

  /// The source as a lane of the search, which the page draws as it draws
  /// every other: its tone, its glyph, its Retry.
  final GlobalSearchServiceResults lane;

  /// What the line says in place of the lane's own, where the lane's cause
  /// is not the whole story: a catalog the source could not reach.
  final String? sentence;

  /// The failure is the library's read rather than the search's: Retry
  /// reads the library again.
  final bool readsLibrary;
}

/// What Discover's search draws for music, folded from the three reads it
/// takes: the search itself, and the library's artists and albums, which say
/// which of the rows are already held.
///
/// The library is read only once the source has something to show, so a word
/// it finds nothing for downloads no album list. A failed library read is its
/// own fault, since a row cannot be told from one that is not held: it is
/// never guessed.
final discoverMusicProvider = Provider.autoDispose<DiscoverMusic>((ref) {
  if (!ref.watch(hasMusicSourceProvider)) return const DiscoverMusicOff();
  if (ref.watch(globalSearchQueryProvider).trim().isEmpty) {
    return const DiscoverMusicOff();
  }
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr));
  if (lens == null) return const DiscoverMusicOff();
  final leg = (
    instance: lens,
    name: ref.watch(
      currentSettingsProvider.select((s) => s.connectionName(lens.id) ?? ''),
    ),
  );

  // Asked before the value: a round asked again carries the last answer
  // across, and reading it first would draw what the person just left.
  final hits = ref.watch(discoverMusicHitsProvider);
  if (hits.isLoading) return const DiscoverMusicAsking();
  if (hits.hasError) {
    final error = hits.error!;
    if (error is LidarrCatalogUnavailable) {
      // Lidarr answered: its own fault, with the library still working.
      final lane = GlobalSearchServiceResults(
        leg: leg,
        state: SearchLaneState.failed,
        reason: ServiceFailureReason.serverError,
      );
      return DiscoverMusicFault(
        lane: lane,
        sentence:
            '${lane.laneTitle} answered, but its music catalog did not, so '
            'music is missing.',
      );
    }
    return DiscoverMusicFault(
      lane: GlobalSearchServiceResults.fault(leg, error),
    );
  }
  final found = hits.value ?? const <LidarrSearchHit>[];
  if (found.isEmpty) return const DiscoverMusicNothing();

  final artists = ref.watch(musicProvider);
  final albums = ref.watch(musicAlbumsProvider);
  final readError = artists.error ?? albums.error;
  if (!(artists.hasValue && albums.hasValue)) {
    if (readError != null) {
      return DiscoverMusicFault(
        lane: GlobalSearchServiceResults.fault(leg, readError),
        readsLibrary: true,
      );
    }
    return const DiscoverMusicAsking();
  }
  return DiscoverMusicFound(
    hits: found.take(discoverMusicRows).toList(growable: false),
    held: MusicHeld(artists: artists.requireValue, albums: albums.requireValue),
  );
});

/// Asks the music source again, as the line that says it did not answer
/// offers: the search, or the library read that failed.
void retryDiscoverMusic(WidgetRef ref, {bool readsLibrary = false}) {
  if (readsLibrary) {
    ref
      ..invalidate(musicProvider)
      ..invalidate(musicAlbumsProvider);
  } else {
    ref.invalidate(discoverMusicHitsProvider);
  }
}
