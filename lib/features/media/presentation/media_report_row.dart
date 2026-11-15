import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/report_problem_sheet.dart';

/// Who sees a report, as the requester's row says it.
const _requesterLine = 'Whoever runs the server sees it';

/// Where a report is filed, as the operator's row says it: `Filed in Seerr as
/// Matt`, or `Filed in Seerr` when the account has no name (the key). A Seerr
/// that has a title of its own is named by it: `Filed on Casa Requests as
/// Matt`.
String mediaReportFiledLine({String? serverTitle, String? accountName}) {
  final named = serverTitle != null && serverTitle != 'Seerr';
  final where = named ? 'Filed on $serverTitle' : 'Filed in Seerr';
  return accountName == null ? where : '$where as $accountName';
}

/// One row of a title's problem reports: a way to report, or a report that
/// stands.
///
/// A row of a [MediaGroup], tapped whole when it leads somewhere ([onTap]) and
/// speaking one sentence. A report row with no page to open draws no chevron
/// and no target: it states, it does not promise.
class MediaReportRow extends StatelessWidget {
  /// The way to report a problem: a glyph tile in the ink, the title and what
  /// reporting does under it.
  const MediaReportRow.action({
    super.key,
    required this.title,
    required this.onTap,
    this.detail,
    this.glyph = Icons.flag_outlined,
    this.verdict = const Live(),
  }) : tone = null,
       word = null,
       sub = null,
       loadingTitle = false,
       maxTitleLines = null;

  /// A report that stands: its glyph in the tone of where it is, the title,
  /// and under it a state word with [sub], the rest of the line.
  const MediaReportRow.report({
    super.key,
    required this.title,
    required StatusTone this.tone,
    required String this.sub,
    required this.word,
    this.onTap,
    this.maxTitleLines,
    this.loadingTitle = false,
  }) : detail = null,
       glyph = Icons.flag_outlined,
       verdict = const Live();

  final String title;

  /// What reporting does, under an [MediaReportRow.action]'s title.
  final String? detail;

  /// A report's state word and the rest of its line.
  final String? word;
  final String? sub;

  /// The tone of a report's glyph and state dot; null for an action.
  final StatusTone? tone;
  final IconData glyph;

  /// How many lines the title may take before it ends in an ellipsis; null,
  /// all of them: a title wraps and is never cut.
  final int? maxTitleLines;

  /// The title is still being read: a skeleton line stands where it will be.
  final bool loadingTitle;
  final VoidCallback? onTap;

  /// What the gate says of an action: [Dimmed] keeps the row, its 44pt target
  /// and its name, drains it and answers a tap with the reason.
  final GateVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = this.tone;
    final glyphColor = tone == null
        ? room.inkSecondary
        : statusToneColor(scheme, tone, surface: room.door);
    final under = switch ((tone, detail)) {
      (final StatusTone t, _) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: 2,
          children: [
            MediaStateWord(word ?? '', tone: t, hollow: false),
            Text(
              sub ?? '',
              style: AppType.meta
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkSecondary),
            ),
          ],
        ),
      ),
      (_, final String d) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          d,
          style: AppType.meta
              .weight(FontWeight.w400)
              .copyWith(color: room.inkSecondary),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: room.fillQuiet,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(glyph, size: 19, color: glyphColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loadingTitle)
                    // The shape of the line it stands for.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: ShimmerPlaceholder.text(width: 200, height: 16),
                    )
                  else
                    Text(
                      title,
                      maxLines: maxTitleLines,
                      overflow: maxTitleLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                  under,
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: room.inkTertiary,
              ),
            ],
          ],
        ),
      ),
    );

    final spoken = [
      if (!loadingTitle) title,
      ?word,
      ?sub,
      ?detail,
    ].where((part) => part.isNotEmpty).join('. ');
    if (tone != null) {
      // A report that stands: one sentence, a button only once it leads
      // somewhere.
      return onTap == null
          ? Semantics(
              container: true,
              label: spoken,
              excludeSemantics: true,
              child: content,
            )
          : PressableScale(
              onTap: onTap,
              semanticLabel: spoken,
              excludeChildSemantics: true,
              child: content,
            );
    }
    return RoleGatedAction.builder(
      verdict: verdict,
      onTap: onTap!,
      builder: (context, onPressed, annotate) => PressableScale(
        onTap: onPressed,
        semanticLabel: spoken,
        // On the row's own node: a hint inside a silenced child never speaks.
        semanticHint: verdict.reason,
        excludeChildSemantics: true,
        haptic: verdict.acts,
        child: annotate(content),
      ),
    );
  }
}

/// A title's problem reports, on its page: the way to report one, and the
/// reports that stand.
///
/// Drawn only where Seerr says the title is on the server
/// ([mediaReportSourceOf]); otherwise nothing, and no gap.
///
/// The requester reads one group under the lead: her own latest report (blue
/// while it waits, green once it is resolved) and the way to report another.
/// The operator reads the title's open issues under `Reported problems`, then
/// the way to report, in the group after `On your server`.
class MediaReportSection extends ConsumerWidget {
  const MediaReportSection.requester({super.key, required this.scope})
    : operator = false;

  const MediaReportSection.operator({super.key, required this.scope})
    : operator = true;

  final MediaReportScope scope;
  final bool operator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(mediaReportSourceProvider(scope));
    if (source == null) return const SizedBox.shrink();
    final gate = ref.watch(roleGateProvider(source.seerr.id));
    final verdict = gate.reportIssueAction();
    if (verdict is Absent) return const SizedBox.shrink();
    final userId = ref.watch(seerrActingUserIdProvider(source.seerr.id));

    final report = _reportRow(
      context,
      ref,
      source,
      verdict: verdict,
      title: 'Report a problem',
      detail: operator
          ? mediaReportFiledLine(
              serverTitle: gate.server?.title,
              accountName: reportAccountName(source),
            )
          : _requesterLine,
      glyph: operator ? Icons.add_rounded : Icons.flag_outlined,
    );

    if (operator) {
      final open = source.openIssues;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open.isEmpty)
            const SizedBox(height: AppSpacing.section)
          else
            MediaHeading('Reported problems', trailing: '${open.length} open'),
          MediaGroup(
            children: [
              for (final issue in open)
                _OperatorIssueRow(connectionId: source.seerr.id, issue: issue),
              report,
            ],
          ),
        ],
      );
    }

    final own = source.ownLatest(userId);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: MediaGroup(
        children: [
          if (own != null) ...[
            _OwnReportRow(connectionId: source.seerr.id, issue: own),
            if (own.isOpen)
              _reportRow(
                context,
                ref,
                source,
                verdict: verdict,
                title: 'Report another problem',
                glyph: Icons.add_rounded,
              )
            else
              report,
          ] else
            report,
        ],
      ),
    );
  }

  Widget _reportRow(
    BuildContext context,
    WidgetRef ref,
    MediaReportSource source, {
    required GateVerdict verdict,
    required String title,
    String? detail,
    required IconData glyph,
  }) => MediaReportRow.action(
    title: title,
    detail: detail,
    glyph: glyph,
    verdict: verdict,
    onTap: () => showReportProblemSheet(context, scope: scope, source: source),
  );
}

/// The name of the account the report is filed as, or null for the key.
String? reportAccountName(MediaReportSource source) {
  final name = source.seerr.account?.displayName.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// The row of the requester's own latest report: blue and open while it
/// waits on someone else, green and quiet once it is resolved. Tapped, it
/// opens the report.
class _OwnReportRow extends ConsumerWidget {
  const _OwnReportRow({required this.connectionId, required this.issue});

  final String connectionId;
  final SeerrIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = issue.type?.label.toLowerCase();
    final what = type == null || issue.type == SeerrIssueType.other
        ? 'Your report'
        : 'Your $type report';
    final now = DateTime.now();
    final at = DateTime.tryParse(issue.createdAt ?? '');
    final when = at == null
        ? null
        : capitalizeFirst(formatDayWords(at, now: now));
    if (issue.isResolved) {
      final resolvedAt = DateTime.tryParse(issue.updatedAt ?? '');
      return MediaReportRow.report(
        title: '$what was resolved',
        tone: StatusTone.success,
        word: 'Resolved',
        sub: resolvedAt == null
            ? ''
            : capitalizeFirst(formatDayWords(resolvedAt, now: now)),
        onTap: () => context.push(
          ServiceRoutes.requestsIssue(issue.id, instanceId: connectionId),
        ),
      );
    }
    // The replies are in the issue itself, and only that one is read.
    final read = ref.watch(
      mediaReportIssueProvider((connectionId: connectionId, issueId: issue.id)),
    );
    final replies = read.value == null
        ? null
        : _repliesLine(read.value!.replies, ref, connectionId);
    return MediaReportRow.report(
      title: '$what is open',
      tone: StatusTone.info,
      word: 'Reported',
      sub: [?when, ?replies].join(dotSeparator),
      onTap: () => context.push(
        ServiceRoutes.requestsIssue(issue.id, instanceId: connectionId),
      ),
    );
  }
}

/// `1 reply from Matt`, `3 replies`; null with none.
String? _repliesLine(
  List<SeerrIssueComment> replies,
  WidgetRef ref,
  String connectionId,
) {
  if (replies.isEmpty) return null;
  final me = ref.watch(seerrActingUserIdProvider(connectionId));
  final names = {
    for (final reply in replies)
      if (!reply.isBy(me)) reply.authorName ?? '',
  };
  final count = _replies(replies.length);
  // Named only when every reply is one other person's.
  return names.length == 1 &&
          names.first.isNotEmpty &&
          replies.every((reply) => !reply.isBy(me))
      ? '$count from ${names.first}'
      : count;
}

String _replies(int count) => count == 1 ? '1 reply' : '$count replies';

/// One open issue of the title, for the operator: its words, who reported it
/// and when, how many replied. Amber: a fault waiting to be fixed. Tapped, it
/// opens the issue.
class _OperatorIssueRow extends ConsumerWidget {
  const _OperatorIssueRow({required this.connectionId, required this.issue});

  final String connectionId;
  final SeerrIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seerr's list on a title carries neither the words nor the replies.
    final answer = ref.watch(
      mediaReportIssueProvider((connectionId: connectionId, issueId: issue.id)),
    );
    final read = answer.value;
    final full = read ?? issue;
    final type = full.type?.label;
    final at = DateTime.tryParse(full.createdAt ?? '');
    final scope = switch ((full.problemSeason, full.problemEpisode)) {
      (0, _) => null,
      (final season, 0) => formatSeasonCode(season),
      (final season, final episode) => formatEpisodeCode(season, episode),
    };
    final replies = read == null || read.replies.isEmpty
        ? null
        : _replies(read.replies.length);
    return MediaReportRow.report(
      // The skeleton while the read is out; the type's own words only once it
      // failed.
      title: read?.message ?? '${type ?? 'Reported'} problem',
      loadingTitle: answer.isLoading && read == null,
      maxTitleLines: 3,
      tone: StatusTone.warning,
      word: 'Open',
      sub: [
        ?type,
        ?scope,
        ?full.createdBy?.displayName,
        if (at != null) formatDayWords(at, now: DateTime.now()),
        ?replies,
      ].join(dotSeparator),
      onTap: () => context.push(
        ServiceRoutes.seerrIssue(issue.id, instanceId: connectionId),
      ),
    );
  }
}

/// `Report a problem with this episode`, at the end of an episode's sheet:
/// drawn for a season on the server only, and under the same conditions and
/// gate as the title's own row. Opens the report with the season and the
/// episode filled in.
class MediaEpisodeReportRow extends ConsumerWidget {
  const MediaEpisodeReportRow({
    super.key,
    required this.scope,
    required this.season,
    required this.number,
  });

  final MediaReportScope scope;
  final int season;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Season 0 is every season to Seerr: Specials cannot be reported on.
    if (season <= 0) return const SizedBox.shrink();
    final source = ref.watch(mediaReportSourceProvider(scope));
    if (source == null || !source.hasSeason(season)) {
      return const SizedBox.shrink();
    }
    final gate = ref.watch(roleGateProvider(source.seerr.id));
    final verdict = gate.reportIssueAction();
    if (verdict is Absent) return const SizedBox.shrink();
    final operator = ref.watch(audienceProvider) == Audience.operator;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section),
      child: MediaGroup(
        children: [
          MediaReportRow.action(
            title: 'Report a problem with this episode',
            detail: operator
                ? mediaReportFiledLine(
                    serverTitle: gate.server?.title,
                    accountName: reportAccountName(source),
                  )
                : _requesterLine,
            verdict: verdict,
            onTap: () => showReportProblemSheet(
              context,
              scope: scope,
              source: source,
              season: season,
              episode: number,
            ),
          ),
        ],
      ),
    );
  }
}
