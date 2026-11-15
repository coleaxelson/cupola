import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/rail_arrows.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/discover/presentation/more_from_your_artists_page.dart';
import 'package:cupola/features/music/domain/album_kind.dart';
import 'package:cupola/features/music/domain/more_from_your_artists.dart';
import 'package:cupola/features/music/presentation/more_from_your_artists_provider.dart';
import 'package:cupola/features/music/presentation/music_reach.dart';

/// Albums the library's artists made that nothing is looking for: a shelf of
/// Discover, after what Seerr says is missing from the library (or under the
/// calendar, with no Seerr).
///
/// Drawn only for the operator, with a music source, and once it has something
/// to show: while it is read, and when the read failed, it is nothing at all,
/// as the atrium's other optional shelves are. Its heading opens the whole of
/// it, grouped by artist ([MoreFromYourArtistsPage]).
class MoreFromYourArtistsShelf extends ConsumerWidget {
  const MoreFromYourArtistsShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasMusicSourceProvider)) return const SizedBox.shrink();
    final shelf = ref.watch(moreFromYourArtistsProvider).value;
    if (shelf == null || shelf.isEmpty) return const SizedBox.shrink();
    final albums = shelf.shelf;
    final name = watchMusicName(ref);
    final reach = watchMusicReach(ref);
    return RailArrows(
      builder: (context, controller, arrows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'More from your artists',
            subtitle: MoreFromYourArtistsPage.leadFor(name),
            onTap: () =>
                context.push(ServiceRoutes.discoverMoreFromYourArtists),
            semanticHint: 'Opens every album, by artist',
            rail: arrows,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: ArtistAlbumTile.heightFor(context),
            child: ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: albums.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.carouselGap),
              itemBuilder: (context, index) => ArtistAlbumTile(
                key: ValueKey(('more-from-album', albums[index].album.id)),
                entry: albums[index],
                reach: reach,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// One album of the shelf: its cover in a square with its own light, the
/// title under it, and who made it, what kind of release it is and when.
///
/// No plus on the cover: the shelf says what is there to be found, and
/// choosing is done on the artist's page, which a tap opens landed on the
/// album, on its tracks. The tile speaks one sentence (`Big Buck Bunny Suite,
/// EP by Jan Morgenstern, 2008, unmonitored`) and the hint says where it goes.
class ArtistAlbumTile extends StatelessWidget {
  const ArtistAlbumTile({super.key, required this.entry, required this.reach});

  final ArtistAlbum entry;

  /// Where the cover is read from.
  final MusicReach reach;

  /// The tile's width, and its cover's side.
  static const double side = 132;

  /// Two lines of title and two of the line under it, at the reading size the
  /// person chose up to the compact tile's ceiling
  /// (`TextScaleMetrics.clampedScalerOf`), so a rail is as tall as its tiles
  /// can be and nothing is clipped at the foot.
  static double heightFor(BuildContext context) {
    final scaler = TextScaleMetrics.clampedScalerOf(context);
    double line(TextStyle style) =>
        scaler.scale(style.fontSize ?? 14) * (style.height ?? 1.3);
    // Up to the next whole pixel: the lines' heights are fractions, and a
    // column that is a thousandth short is an overflow.
    return (side +
            AppSpacing.sm +
            2 * line(AppType.label) +
            2 * line(AppType.caption))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final (:album, :artist) = entry;
    final room = CupolaRoom.of(context);
    final kind = AlbumKind.of(album);
    final art = musicArtOf(album.images, musicAlbumArt, reach);
    final year = album.year;
    final line = joinDisplayParts([artist.artistName, kind.fact, year]);
    final clamped = TextScaleMetrics.clampedScalerOf(context);
    return SizedBox(
      width: side,
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.lidarrArtist(artist.id, albumId: album.id),
          extra: artist,
        ),
        semanticLabel: joinDisplayParts([
          album.title,
          '${kind.noun} by ${artist.artistName}',
          year,
          'unmonitored',
        ], separator: ', '),
        semanticHint: 'Opens the artist',
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: side,
              height: side,
              child: ContentCard.lit(
                imageUrl: art.url,
                httpHeaders: art.headers,
                fallbackIcon: Icons.album_outlined,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // The words lay out on the same clamp the tile grew by.
            Text(
              album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaleMetrics.wholeWordScaler(
                clamped,
                text: album.title,
                style: AppType.label,
                width: side,
                maxLines: 2,
              ),
              style: AppType.label.copyWith(color: room.ink),
            ),
            Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaleMetrics.wholeWordScaler(
                clamped,
                text: line,
                style: AppType.caption,
                width: side,
                maxLines: 2,
              ),
              style: AppType.caption.copyWith(color: room.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
