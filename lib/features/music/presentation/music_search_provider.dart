import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/search_results_loader.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';

/// Provider for the current search query in Music section.
final musicSearchQueryProvider = StateProvider<String>((ref) => '');

/// Where the Music wall's search looks: its library, or Lidarr. Back to the
/// library when the field is emptied; set to [MediaFindScope.service] by a
/// link that means Lidarr's own search.
final musicFindScopeProvider = StateProvider<MediaFindScope>(
  (ref) => MediaFindScope.library,
);

/// What Lidarr's search finds for the query, artists and albums together.
///
/// Null when the query is empty, otherwise Lidarr's answer, and a failure
/// when there was none: never an empty list for a Lidarr that did not
/// answer. A catalog Lidarr could not reach is [LidarrCatalogUnavailable]
/// (see `LidarrService.search`).
///
/// The request carries a [CancelToken] cancelled on dispose. See
/// `moviesSearchResultsProvider` for why the superseded round has to stop.
final musicSearchResultsProvider = FutureProvider<List<LidarrSearchHit>?>((
  ref,
) async {
  final query = ref.watch(musicSearchQueryProvider);
  // `watch`, not `read`. See `moviesSearchResultsProvider`.
  final service = ref.watch(lidarrServiceProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    lookup: (term) => service.search(term, cancelToken: cancelToken),
  );
}, retry: noProviderRetry);
