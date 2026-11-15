import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/music/domain/album_kind.dart';

/// An artist's albums by kind: `All 9`, `Albums 1`, `Singles 4`... one pill
/// per kind the artist has, each with how many, the chosen one on the strong
/// fill. A rail that scrolls sideways when the kinds outgrow the row, fading
/// out at its end while there is more behind it.
///
/// Drawn only for an artist with more than one kind (the page decides): one
/// pill alone would filter nothing. [selected] null is `All`. With
/// [onFindTrack], the lens that opens the track finder stands at the end of
/// the row, outside the rail.
class ArtistTypePills extends StatelessWidget {
  const ArtistTypePills({
    super.key,
    required this.kinds,
    required this.total,
    required this.selected,
    required this.onSelected,
    this.onFindTrack,
    this.artistName = '',
  });

  /// The kinds the artist has and how many albums of each, in the pills'
  /// order ([albumKindsOf]); their counts add up to [total].
  final List<AlbumKindCount> kinds;
  final int total;
  final AlbumKind? selected;
  final ValueChanged<AlbumKind?> onSelected;

  /// Opens the track finder; null for no lens (the artist's albums are not
  /// all read yet).
  final VoidCallback? onFindTrack;

  /// Whose tracks the lens finds, for its name to a screen reader.
  final String artistName;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final kind in kinds) kind.kind: kind.count};
    return Row(
      children: [
        Expanded(
          child: _FadingRail(
            child: SelectionPills<AlbumKind?>(
              padding: EdgeInsets.zero,
              values: [null, for (final kind in kinds) kind.kind],
              selected: selected,
              labelBuilder: (kind) => kind?.label ?? 'All',
              countBuilder: (kind) => '${kind == null ? total : counts[kind]}',
              onSelected: onSelected,
            ),
          ),
        ),
        if (onFindTrack case final onFindTrack?)
          // The glyph sits where the page's edge is, the target reaching
          // past it.
          Transform.translate(
            offset: const Offset(AppSpacing.sm + AppSpacing.xxs, 0),
            child: ArtistFindLens(artistName: artistName, onTap: onFindTrack),
          ),
      ],
    );
  }
}

/// Fades the end of a sideways rail while more of it lies beyond the edge.
class _FadingRail extends StatefulWidget {
  const _FadingRail({required this.child});

  final Widget child;

  @override
  State<_FadingRail> createState() => _FadingRailState();
}

class _FadingRailState extends State<_FadingRail> {
  var _more = false;

  bool _beyondEdge(ScrollMetrics metrics) =>
      metrics.maxScrollExtent - metrics.pixels > 1;

  void _measure(ScrollMetrics metrics) {
    final more = _beyondEdge(metrics);
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          // After the frame: a rebuild during layout is not allowed.
          final metrics = notification.metrics;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _measure(metrics);
          });
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _measure(notification.metrics);
            return false;
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                const Color(0xFF000000),
                const Color(0xFF000000),
                _more ? const Color(0x00000000) : const Color(0xFF000000),
              ],
              stops: const [0, 0.85, 1],
            ).createShader(bounds),
            child: widget.child,
          ),
        ),
      );
}

/// The lens at the end of the pills: opens the track finder. 44 square.
class ArtistFindLens extends StatelessWidget {
  const ArtistFindLens({
    super.key,
    required this.artistName,
    required this.onTap,
  });

  final String artistName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Find a track by $artistName',
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: DesignTokens.sizeTouch,
        child: Center(
          child: Icon(Icons.search_rounded, size: 20, color: room.inkSecondary),
        ),
      ),
    );
  }
}

/// `Find a track`, quiet, for an artist whose albums are of one kind: there
/// are no pills for a lens to stand beside, and a lone icon would be an
/// orphan. Aligned to the start of the column.
class ArtistFindTrackButton extends StatelessWidget {
  const ArtistFindTrackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.search_rounded, size: 18),
        label: const Text('Find a track'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, DesignTokens.sizeTouch),
          visualDensity: VisualDensity.standard,
          foregroundColor: room.inkSecondary,
          textStyle: AppType.label,
          padding: const EdgeInsets.only(right: AppSpacing.md),
        ),
      ),
    );
  }
}
