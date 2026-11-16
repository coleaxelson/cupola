import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_issue_words.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/requests/presentation/widgets/requests_slab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart'
    show spokenFromDotted;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/core/utils/image_utils.dart';

/// What she reported with what she watches, under her requests: `Your
/// reports` with how many are still open, one row per report, the newest
/// change first, each opening her report.
///
/// Read from her own session and kept to what she reported (Seerr answers
/// everyone's to an account that may view issues), and only when her account
/// may list issues at all: nothing is asked that the server would refuse.
/// **Absent** with no reports, with none of the above, and while the read is
/// out or did not answer: her requests already carry the page's one line for
/// a silent server, and a second one here would say the same twice. Never
/// names a service.
class YourReportsSection extends ConsumerWidget {
  const YourReportsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mayList = ref.watch(roleGateProvider('')).mayListIssues;
    if (!mayList) return const SizedBox.shrink();
    final read = ref.watch(ownIssuesProvider('')).asData?.value;
    // Seerr answers everyone's issues to an account that may view them: hers
    // are the ones she reported, and with no account to tell them by, none.
    final me = ref.watch(seerrActingUserIdProvider(''));
    final reports = read?.items.where((report) => report.isReportedBy(me));
    if (reports == null || reports.isEmpty) return const SizedBox.shrink();
    final newestFirst = [...reports]
      ..sort((a, b) => _changedAt(b).compareTo(_changedAt(a)));
    final open = newestFirst.where((report) => report.isOpen).length;
    // A read cut short may hold more of hers than it shows: a floor.
    final openCount = read!.isPartial ? '$open+' : '$open';
    final lens =
        ref.watch(
          activeInstanceProvider(ServiceKey.seerr).select((i) => i?.id),
        ) ??
        '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaHeading(
            'Your reports',
            trailing: open > 0 ? '$openCount open' : null,
          ),
          RequestsSlab(
            children: [
              for (final (index, report) in newestFirst.indexed)
                _ReportRow(
                  key: ValueKey('report-${report.id}'),
                  report: report,
                  connectionId: lens,
                  divided: index > 0,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// When the report last changed: the moment the newest first is ordered by.
  static DateTime _changedAt(SeerrIssue report) =>
      DateTime.tryParse(report.updatedAt ?? report.createdAt ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// One report: the poster in the title's light, the title (and where in a
/// series), where it stands, and what happened since.
///
/// The Seerr list names no reply's author, so a report with replies reads her
/// conversation once for the name (`1 reply from Matt`); until it answers the
/// row says how many replied, which is true without it.
class _ReportRow extends ConsumerWidget {
  const _ReportRow({
    super.key,
    required this.report,
    required this.connectionId,
    required this.divided,
  });

  final SeerrIssue report;
  final String connectionId;
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final state = issueState(report, operator: false);
    final title = [
      report.media?.title ?? 'Unknown media',
      ?issuePlace(report),
    ].join(dotSeparator);
    String? replies;
    if (report.replies.isNotEmpty) {
      final conversation = ref
          .watch(
            mediaReportIssueProvider((
              connectionId: connectionId,
              issueId: report.id,
            )),
          )
          .value;
      replies = conversation == null
          ? repliesLabel(report.replies.length)
          : replyLineFrom(
              conversation,
              me: ref.watch(seerrActingUserIdProvider(connectionId)),
            );
    }
    final changed = DateTime.tryParse(
      report.updatedAt ?? report.createdAt ?? '',
    );
    final meta = [
      ?report.type?.label,
      ?replies ??
          (changed == null
              ? null
              : formatDayWords(changed, now: DateTime.now())),
    ].join(dotSeparator);
    final poster = ImageUtils.buildTmdbPosterUrl(
      report.media?.posterPath,
      size: 'w154',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.requestsIssue(report.id, instanceId: connectionId),
        ),
        semanticLabel: spokenFromDotted(
          [title, state.word, meta].join(dotSeparator),
        ),
        excludeChildSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                HomeRowArt(posterUrl: poster, icon: Icons.movie_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.row.copyWith(color: room.ink)),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: MediaStateWord(
                          state.word,
                          tone: state.tone,
                          hollow: false,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta,
                            style: AppType.meta.copyWith(
                              color: room.inkSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: room.inkTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
