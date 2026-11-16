import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/presentation/music_hit_row.dart';
import 'package:cupola/features/music/presentation/music_reach.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/search/presentation/discover_music_provider.dart';

/// `Music` in Discover's results: the music source's first three hits for the
/// words typed, after the movies and series, and the way to all of them.
///
/// Artists and albums sit together, each as the Music wall's Lidarr scope draws
/// it (`MusicHitRow.mixed`): held, it says where it stands and opens the
/// artist's page, on the album for an album; not held, it carries the plus
/// that adds it. `Show all music for “…”` opens the wall on the Lidarr scope
/// with the same words.
///
/// While the source answers after the others it is `Asking Lidarr` over two
/// rows of plates. It is absent when there is nothing to put in it: no music
/// source (the requester's Discover), nothing found, or a source that did not
/// answer, which the results say once at their head
/// ([DiscoverMusicFault]) and not here.
class DiscoverMusicSection extends ConsumerWidget {
  const DiscoverMusicSection({super.key, required this.query});

  /// The words the field holds.
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(discoverMusicProvider)) {
      DiscoverMusicAsking() => const _Asking(),
      DiscoverMusicFound(:final hits, :final held) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SearchHeading('Music'),
          for (final hit in hits) MusicHitRow.mixed(hit: hit, held: held),
          _ShowAll(query: query),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The source is still answering: the heading, what it is doing, and two rows
/// of plates the size of the rows to come.
class _Asking extends ConsumerWidget {
  const _Asking();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = watchMusicName(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SearchHeading('Music'),
        // The plates speak it (a live region); the words are for the eye.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              'Asking $name',
              style: AppType.caption.copyWith(
                color: CupolaRoom.of(context).inkTertiary,
              ),
            ),
          ),
        ),
        SearchRowsPending(
          label: 'Asking $name',
          rows: 2,
          shape: SearchRowsShape.square,
        ),
      ],
    );
  }
}

/// `Show all music for “sintel”`: the Music wall, on Lidarr's own search, with
/// the same words.
class _ShowAll extends ConsumerWidget {
  const _ShowAll({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = CupolaRoom.of(context).inkSecondary;
    return PressableScale(
      onTap: () {
        // Lidarr's own search, not the library's.
        ref.read(musicFindScopeProvider.notifier).state =
            MediaFindScope.service;
        ref.read(musicSearchQueryProvider.notifier).state = query;
        context.go(ServiceRoutes.lidarrLibrary);
      },
      semanticLabel: 'Show all music for $query',
      semanticHint: 'Opens the Music library on Lidarr’s search',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Show all music for “$query”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(color: color),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
