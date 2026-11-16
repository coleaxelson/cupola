import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart'
    show spokenFromDotted;
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show runDecision;

/// What people reported with what they watch, as one fault in Needs you:
/// `3 reported problems`, the flag in amber by the Seerr that holds them, who
/// said it in one sentence, the newest of them each opening its issue, and
/// `Review 3` in the amber fill, which opens the Issues tab on Open.
///
/// The headline's count is Seerr's own, the rows are only the newest few
/// ([DashboardDecision.members]); a Seerr that did not give its rows is the
/// headline, the source and the remedy alone. A line of a wide list is
/// [DecisionFaultCard.row], the same words on the one line every fault has.
class ReportedProblemsCard extends ConsumerWidget {
  const ReportedProblemsCard({
    super.key,
    required this.decision,
    this.divided = false,
    this.whole = false,
  });

  final DashboardDecision decision;
  final bool divided;

  /// The Needs you page's card: a slab of its own, the headline set larger.
  final bool whole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final amber = statusToneColor(
      Theme.of(context).colorScheme,
      StatusTone.warning,
      surface: room.slab,
    );
    final words = faultWordsOf(decision);
    final label = faultActionLabel(decision);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: whole ? AppSpacing.lg : AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: [
                words.headline,
                ?words.explanation,
                words.source,
              ].join('. '),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    words.headline,
                    style: (whole ? AppType.section : AppType.row).copyWith(
                      color: room.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 16, color: amber),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          words.source,
                          style: AppType.meta
                              .weight(FontWeight.w600)
                              .copyWith(color: room.inkSecondary),
                        ),
                      ),
                    ],
                  ),
                  if (words.explanation case final sentence?) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      sentence,
                      style: AppType.body.copyWith(color: room.inkSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (decision.members.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Column(
                  children: [
                    for (final member in decision.members)
                      _IssueLine(member: member),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => runDecision(context, ref, decision),
                style: remedyFillStyle(context),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: Text(
                  label,
                  semanticsLabel: 'Review the reported problems',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the newest issues under the headline: the poster in the title's
/// light, the title and who said what about where and when. Opens the issue.
class _IssueLine extends StatelessWidget {
  const _IssueLine({required this.member});

  final DashboardDecision member;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final at = member.occurredAt;
    final detail = [
      if (member.detail.isNotEmpty) member.detail,
      if (at != null) formatDayWords(at, now: DateTime.now()),
    ].join(dotSeparator);
    final route = member.route;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: room.hair)),
      ),
      child: PressableScale(
        onTap: route == null ? null : () => context.pushMounted(route),
        semanticLabel: '${member.title}. ${spokenFromDotted(detail)}',
        excludeChildSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
            child: Row(
              children: [
                HomeRowArt(
                  posterUrl: member.posterUrl,
                  icon: Icons.movie_outlined,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.title,
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      if (detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            detail,
                            style: AppType.meta.copyWith(
                              color: room.inkSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
