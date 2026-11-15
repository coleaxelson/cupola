import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/domain/album_kind.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/more_from_your_artists_provider.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_reach.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Every album the library's artists made that nothing is looking for, under
/// the artist who made it: what the shelf `More from your artists` opens.
///
/// The artists A to Z, each with their albums newest first, as rows (a square
/// cover, the title, the kind and the year, and the word the library keeps for
/// an album left alone). A tap opens the artist's page landed on the album, on
/// its tracks. The list is built as it scrolls: a library of thousands leaves
/// a few hundred.
class MoreFromYourArtistsPage extends ConsumerWidget {
  const MoreFromYourArtistsPage({super.key});

  /// What the page, and the shelf under its heading, say these are.
  static String leadFor(String name) =>
      'Albums $name knows from artists you have, not monitored.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = watchMusicName(ref);
    final body = ref.watch(hasMusicSourceProvider)
        ? _Albums(name: name)
        : NotConfiguredPlaceholder.forService(ServiceKey.lidarr);
    return AmbientScaffold(
      contentWellWidth: AppBreakpoints.contentWell,
      appBar: const GlassAppBar.inPage(pageTitle: 'More from your artists'),
      body: body,
    );
  }
}

class _Albums extends ConsumerWidget {
  const _Albums({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id;
    final read = ref.watch(moreFromYourArtistsProvider);
    final bottom = FloatingNavBarMetrics.getScrollViewBottomPadding(context);

    void readAgain() {
      ref
        ..invalidate(musicProvider)
        ..invalidate(musicAlbumsProvider)
        ..invalidate(moreFromYourArtistsProvider);
    }

    final shelf = read.value;
    if (shelf == null) {
      if (read.hasError && !read.isLoading) {
        return AppErrorState(
          error: read.error!,
          service: ServiceKey.lidarr,
          instanceId: lens,
          serviceName: name,
          onRetry: readAgain,
        );
      }
      return ListView(
        padding: EdgeInsets.only(top: AppSpacing.sm, bottom: bottom),
        children: const [ShimmerList(itemCount: 6, itemHeight: 76)],
      );
    }
    if (shelf.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => readAgain(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottom),
          children: const [
            PageTitle('More from your artists'),
            AppEmptyState(
              icon: Icons.album_outlined,
              title: 'Nothing left to find',
              message:
                  'Every album by your artists is monitored or on disk. '
                  'It reads again when you pull down.',
            ),
          ],
        ),
      );
    }

    final reach = watchMusicReach(ref);
    // Headings and albums as one flat list, so that only the rows on screen
    // are built.
    final groups = shelf.byArtist;
    final entries = <Object>[
      for (final group in groups) ...[group.artist, ...group.albums],
    ];
    final albumsOf = {
      for (final group in groups) group.artist.id: group.albums.length,
    };
    final artists = {for (final group in groups) group.artist.id: group.artist};
    return RefreshIndicator(
      onRefresh: () async => readAgain(),
      child: LayoutBuilder(
        builder: (context, box) => ListView.builder(
          primary: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: searchRowsPadding(box.maxWidth, bottom: bottom),
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                // The title's own inset is the gutter, which the list holds.
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: PageTitle.flush(
                  'More from your artists',
                  summary: Text(
                    MoreFromYourArtistsPage.leadFor(name),
                    style: AppType.meta.copyWith(
                      color: CupolaRoom.of(context).inkSecondary,
                    ),
                  ),
                ),
              );
            }
            return switch (entries[index - 1]) {
              final LidarrArtist artist => SearchHeading(
                artist.artistName,
                count: albumsOf[artist.id],
                top: index == 1 ? AppSpacing.xs : AppSpacing.xl,
              ),
              final LidarrAlbum album => _AlbumRow(
                album: album,
                artist: artists[album.artistId]!,
                reach: reach,
              ),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}

/// One album under its artist's heading.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.artist,
    required this.reach,
  });

  final LidarrAlbum album;
  final LidarrArtist artist;
  final MusicReach reach;

  @override
  Widget build(BuildContext context) {
    final art = musicArtOf(album.images, musicAlbumArt, reach);
    return SearchRow.album(
      key: ValueKey(('more-from-row', album.id)),
      title: album.title,
      meta: joinDisplayParts([
        AlbumKind.of(album).fact,
        album.year,
        albumTrackCount(album),
      ]),
      status: (label: albumUnmonitoredWord, tone: StatusTone.neutral),
      statusHollow: true,
      cover: art.url,
      coverHeaders: art.headers,
      hint: 'Opens ${artist.artistName}',
      onTap: () => context.push(
        ServiceRoutes.lidarrArtist(artist.id, albumId: album.id),
        extra: artist,
      ),
    );
  }
}
