import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_find_bodies.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What the wall does with a series it is told of: the same tap on the wall's
/// own tile, in the library's find and in Sonarr's.
typedef SeriesOpen =
    void Function(BuildContext context, SonarrSeries series, String heroTag);

/// `2015 · 3 seasons`: the year, and the seasons when Sonarr lists them
/// (specials are not a season).
String seriesFindMeta(SonarrSeries series) {
  final seasons = series.seasonList.where((s) => s.seasonNumber > 0).length;
  return joinDisplayParts([
    if (series.year > 0) '${series.year}',
    if (seasons > 0) findCount(seasons, one: 'season', many: 'seasons'),
  ]);
}

/// The Series wall's search of its own library: series by the start of a word
/// of their title (or its sort title), answered as it is typed from the
/// library the wall already read. One section, `12 series`, of rows that say
/// where each stands in the word the wall's own badge says it in.
///
/// A tap opens the series as the wall's tile does ([onOpen]).
class SeriesFindLibrary extends ConsumerWidget {
  const SeriesFindLibrary({
    super.key,
    required this.query,
    required this.statusOf,
    required this.settingsSelector,
    required this.onOpen,
    required this.onAskSonarr,
  });

  final String query;

  /// The wall's status for a series, with the queue it waits on.
  final MediaStatusInfo? Function(SonarrSeries series) statusOf;

  /// What the wall reads its artwork with (see `MediaBrowseScaffold`).
  final SettingsSelector settingsSelector;

  final SeriesOpen onOpen;
  final VoidCallback onAskSonarr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (baseUrl, apiKey, _) = ref.watch(
      currentSettingsProvider.select(settingsSelector),
    );
    return MediaFindLibraryBody<SonarrSeries>(
      query: query,
      library: seriesProvider,
      service: ServiceKey.sonarr,
      namesOf: (series) => [
        series.title,
        if (series.sortTitle.isNotEmpty) series.sortTitle,
      ],
      heading: (count) => findCount(count, one: 'series', many: 'series'),
      onAskService: onAskSonarr,
      rowOf: (context, series) {
        final art = ImageUtils.extractPosterUrl(
          series.images,
          baseUrl: baseUrl,
          apiKey: apiKey,
          coverTypes: const ['poster', 'cover'],
        );
        final state = mediaFindState(statusOf(series));
        final tag = 'series_${series.id}_find';
        return SearchRow.title(
          key: ValueKey(('series', series.id)),
          title: series.title,
          meta: seriesFindMeta(series),
          status: state.status,
          statusHollow: state.hollow,
          poster: art.url,
          posterHeaders: art.headers,
          heroTag: tag,
          selected:
              series.tmdbId > 0 &&
              context.paneShows(MediaKey.tv(series.tmdbId)),
          onTap: () => onOpen(context, series, tag),
        );
      },
    );
  }
}

/// The Series wall's search of Sonarr: its lookup, as the rows Discover's
/// search draws for a title (`CatalogTitleRow`): where the title stands (in
/// Sonarr, or Seerr's word), and the plus that adds it or asks for it as far
/// as this account may. A tap opens the title as the wall's tile does.
class SeriesFindSonarr extends ConsumerWidget {
  const SeriesFindSonarr({
    super.key,
    required this.query,
    required this.statusOf,
    required this.onOpen,
  });

  final String query;

  /// The wall's status for a series, with the queue it waits on: what a row
  /// the library holds says, as the wall and its library find say it.
  final MediaStatusInfo? Function(SonarrSeries series) statusOf;

  final SeriesOpen onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The library's copy of a lookup row it holds: Sonarr's lookup carries
    // the library id for what it holds, and the TMDB or TVDB id says it
    // otherwise (a title added a moment ago, before the lookup was asked
    // again).
    final library = ref.watch(seriesProvider).value ?? const <SonarrSeries>[];
    final byId = {for (final series in library) series.id: series};
    final byTmdb = {
      for (final series in library)
        if (series.tmdbId > 0) series.tmdbId: series,
    };
    final byTvdb = {
      for (final series in library)
        if (series.tvdbId > 0) series.tvdbId: series,
    };
    void changed() {
      // An add or a request: the wall reads its library again (and the rail
      // its own copy), and Sonarr is asked again, so the row turns held in
      // place and the title is on the wall when the field is cleared.
      ref
        ..invalidate(seriesProvider)
        ..invalidate(sonarrKpiLibraryProvider)
        ..invalidate(seriesSearchResultsProvider);
    }

    return MediaFindLookupBody<SonarrSeries>(
      query: query,
      results: seriesSearchResultsProvider,
      service: ServiceKey.sonarr,
      heading: (count) => findCount(count, one: 'series', many: 'series'),
      rowOf: (context, series) {
        final tag = 'series_${series.tmdbId}_${series.id}_lookup';
        final poster = remotePosterOf(series.images) ?? '';
        final held = series.id > 0
            ? byId[series.id]
            : (byTmdb[series.tmdbId] ?? byTvdb[series.tvdbId]);
        // A row with no TMDB id has no title to add or ask for: it opens what
        // Sonarr holds of it, when it holds it, and nothing else.
        if (series.tmdbId <= 0 && held == null) {
          return SearchRow.title(
            key: ValueKey(('lookup', series.id, series.title)),
            title: series.title,
            meta: seriesFindMeta(series),
            poster: poster,
            onTap: series.id > 0 ? () => onOpen(context, series, tag) : null,
          );
        }
        return CatalogTitleRow(
          key: ValueKey(('lookup', series.tmdbId)),
          media: MediaPreview(
            id: series.tmdbId,
            title: series.title,
            overview: series.overview,
            releaseDate: series.year > 0 ? '${series.year}' : null,
            mediaType: 'tv',
          ),
          meta: seriesFindMeta(series),
          heroTag: tag,
          posterUrl: poster,
          onChanged: changed,
          onOpen: () => onOpen(context, held ?? series, tag),
          heldAs: held == null ? null : mediaFindState(statusOf(held)),
        );
      },
    );
  }
}
