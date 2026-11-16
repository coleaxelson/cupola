import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_issue_words.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// One issue of the Issues tab: the title's poster under its own light, the
/// title, where the issue stands in its tone, who reported what and when, the
/// words themselves on two lines, and how many replied.
///
/// The row opens the issue ([onOpen]). Resolve is a button of its own at the
/// end of an open row ([onResolve]), a 44pt target as the gate says: dimmed
/// where the account may not resolve, answering a tap with the reason.
///
/// The row speaks one sentence (`Tears of Steel, Open, Video, Luca, yesterday:
/// It plays a different movie. 2 replies`); Resolve stays its own control.
class SeerrIssueRow extends StatelessWidget {
  const SeerrIssueRow({
    super.key,
    required this.issue,
    required this.connectionId,
    required this.onOpen,
    this.onResolve,
    this.resolve = const Live(),
  });

  final SeerrIssue issue;

  /// The connection the issue was read from: it tells the posters of two
  /// Seerrs apart.
  final String connectionId;
  final VoidCallback onOpen;

  /// Resolves the issue; null on a resolved row, which has nothing to resolve.
  final VoidCallback? onResolve;

  /// What the role gate says about Resolve on this connection.
  final GateVerdict resolve;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final media = issue.media;
    final title = media?.title ?? 'Unknown media';
    final state = issueState(issue, operator: true);
    final at = DateTime.tryParse(issue.createdAt ?? '');
    final meta = [
      ?issuePlace(issue),
      ?issue.type?.label,
      ?issue.createdBy?.displayName,
      if (at != null) formatDayWords(at, now: DateTime.now()),
    ].join(dotSeparator);
    final message = issue.message?.trim() ?? '';
    final replies = issue.replies.length;
    final poster = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final spoken = [
      title,
      state.word,
      meta,
      if (message.isNotEmpty) message,
      if (replies > 0) repliesLabel(replies),
    ].join('. ');
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.row,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: room.door,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PressableScale(
              onTap: onOpen,
              semanticLabel: spoken,
              excludeChildSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    height: 54,
                    child: MediaPosterCard(
                      heroTag: 'seerr_issue_row_${connectionId}_${issue.id}',
                      imageUrl: poster.isEmpty ? null : poster,
                      borderRadius: BorderRadius.circular(AppRadius.thumb),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppType.row.copyWith(color: room.ink),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          runSpacing: 2,
                          children: [
                            MediaStateWord(
                              state.word,
                              tone: state.tone,
                              hollow: false,
                            ),
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                style: AppType.meta
                                    .weight(FontWeight.w400)
                                    .copyWith(color: room.inkSecondary),
                              ),
                          ],
                        ),
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s),
                          Text(
                            message,
                            // Two lines at the reading size; whole at a large
                            // one, where a cut line is a cut sentence.
                            maxLines: mediaStacked(context) ? null : 2,
                            overflow: mediaStacked(context)
                                ? null
                                : TextOverflow.ellipsis,
                            style: AppType.meta
                                .weight(FontWeight.w400)
                                .copyWith(color: room.ink),
                          ),
                        ],
                        if (replies > 0) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            repliesLabel(replies),
                            style: AppType.caption
                                .weight(FontWeight.w400)
                                .copyWith(color: room.inkTertiary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onResolve case final onResolve?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: RoleGatedAction.builder(
                verdict: resolve,
                onTap: onResolve,
                builder: (context, onPressed, annotate) => IconButton(
                  tooltip: 'Resolve issue',
                  onPressed: onPressed,
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size.square(DesignTokens.sizeTouch),
                  ),
                  icon: annotate(
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 22,
                      color: room.inkSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
