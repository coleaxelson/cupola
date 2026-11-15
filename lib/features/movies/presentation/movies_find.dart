import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_find_bodies.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What the wall does with a movie it is told of: the same tap on the wall's
/// own tile, in the library's find and in Radarr's.
typedef MovieOpen =
    void Function(BuildContext context, RadarrMovie movie, String heroTag);

/// `1924 · 45 min`: the year, and the runtime when Radarr knows it.
String movieFindMeta(RadarrMovie movie) => joinDisplayParts([
  if (movie.year > 0) '${movie.year}',
  if (movie.runtime > 0) formatTimeSpan(Duration(minutes: movie.runtime)),
]);

/// The Movies wall's search of its own library: movies by the start of a word
/// of their title (or its sort title), answered as it is typed from the
/// library the wall already read. One section, `2 movies`, of rows that say
/// where each stands in the word the wall's own badge says it in.
///
/// A tap opens the movie as the wall's tile does ([onOpen]).
class MoviesFindLibrary extends ConsumerWidget {
  const MoviesFindLibrary({
    super.key,
    required this.query,
    required this.statusOf,
    required this.settingsSelector,
    required this.onOpen,
    required this.onAskRadarr,
  });

  final String query;

  /// The wall's status for a movie, with the queue it waits on.
  final MediaStatusInfo? Function(RadarrMovie movie) statusOf;

  /// What the wall reads its artwork with (see `MediaBrowseScaffold`).
  final SettingsSelector settingsSelector;

  final MovieOpen onOpen;
  final VoidCallback onAskRadarr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (baseUrl, apiKey, _) = ref.watch(
      currentSettingsProvider.select(settingsSelector),
    );
    return MediaFindLibraryBody<RadarrMovie>(
      query: query,
      library: moviesProvider,
      service: ServiceKey.radarr,
      namesOf: (movie) => [
        movie.title,
        if (movie.sortTitle.isNotEmpty) movie.sortTitle,
      ],
      heading: (count) => findCount(count, one: 'movie', many: 'movies'),
      onAskService: onAskRadarr,
      rowOf: (context, movie) {
        final art = ImageUtils.extractPosterUrl(
          movie.images,
          baseUrl: baseUrl,
          apiKey: apiKey,
          coverTypes: const ['poster', 'cover'],
        );
        final state = mediaFindState(statusOf(movie));
        final tag = 'movie_${movie.id}_find';
        return SearchRow.title(
          key: ValueKey(('movie', movie.id)),
          title: movie.title,
          meta: movieFindMeta(movie),
          status: state.status,
          statusHollow: state.hollow,
          poster: art.url,
          posterHeaders: art.headers,
          heroTag: tag,
          selected:
              movie.tmdbId > 0 &&
              context.paneShows(MediaKey.movie(movie.tmdbId)),
          onTap: () => onOpen(context, movie, tag),
        );
      },
    );
  }
}

/// The Movies wall's search of Radarr: its lookup, as the rows Discover's
/// search draws for a title (`CatalogTitleRow`): where the title stands (in
/// Radarr, or Seerr's word), and the plus that adds it or asks for it as far
/// as this account may. A tap opens the title as the wall's tile does.
class MoviesFindRadarr extends ConsumerWidget {
  const MoviesFindRadarr({
    super.key,
    required this.query,
    required this.statusOf,
    required this.onOpen,
  });

  final String query;

  /// The wall's status for a movie, with the queue it waits on: what a row
  /// the library holds says, as the wall and its library find say it.
  final MediaStatusInfo? Function(RadarrMovie movie) statusOf;

  final MovieOpen onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The library's copy of a lookup row it holds: Radarr's lookup carries
    // the library id for what it holds, and the TMDB id says it otherwise (a
    // title added a moment ago, before the lookup was asked again).
    final library = ref.watch(moviesProvider).value ?? const <RadarrMovie>[];
    final byId = {for (final movie in library) movie.id: movie};
    final byTmdb = {
      for (final movie in library)
        if (movie.tmdbId > 0) movie.tmdbId: movie,
    };
    void changed() {
      // An add or a request: the wall reads its library again (and the rail
      // its own copy), and Radarr is asked again, so the row turns held in
      // place and the title is on the wall when the field is cleared.
      ref
        ..invalidate(moviesProvider)
        ..invalidate(radarrKpiLibraryProvider)
        ..invalidate(moviesSearchResultsProvider);
    }

    return MediaFindLookupBody<RadarrMovie>(
      query: query,
      results: moviesSearchResultsProvider,
      service: ServiceKey.radarr,
      heading: (count) => findCount(count, one: 'movie', many: 'movies'),
      rowOf: (context, movie) {
        final tag = 'movie_${movie.tmdbId}_${movie.id}_lookup';
        final poster = remotePosterOf(movie.images) ?? '';
        final held = movie.id > 0 ? byId[movie.id] : byTmdb[movie.tmdbId];
        // A row with no TMDB id has no title to add or ask for: it opens what
        // Radarr holds of it, when it holds it, and nothing else.
        if (movie.tmdbId <= 0 && held == null) {
          return SearchRow.title(
            key: ValueKey(('lookup', movie.id, movie.title)),
            title: movie.title,
            meta: movieFindMeta(movie),
            poster: poster,
            onTap: movie.id > 0 ? () => onOpen(context, movie, tag) : null,
          );
        }
        return CatalogTitleRow(
          key: ValueKey(('lookup', movie.tmdbId)),
          media: MediaPreview(
            id: movie.tmdbId,
            title: movie.title,
            overview: movie.overview,
            releaseDate: movie.year > 0 ? '${movie.year}' : null,
            mediaType: 'movie',
          ),
          meta: movieFindMeta(movie),
          heroTag: tag,
          posterUrl: poster,
          onChanged: changed,
          onOpen: () => onOpen(context, held ?? movie, tag),
          heldAs: held == null ? null : mediaFindState(statusOf(held)),
        );
      },
    );
  }
}
