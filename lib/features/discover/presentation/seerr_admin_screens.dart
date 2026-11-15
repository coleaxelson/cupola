import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_issue_row.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SeerrIssuesScreen extends ConsumerStatefulWidget {
  const SeerrIssuesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<SeerrIssuesScreen> createState() => _SeerrIssuesScreenState();
}

class _SeerrIssuesScreenState extends ConsumerState<SeerrIssuesScreen> {
  SeerrIssueFilter _filter = SeerrIssueFilter.open;

  @override
  Widget build(BuildContext context) {
    // The lens's Seerr, which these pages read: a signed-out one reads signed
    // out before anything is asked of it.
    if (!watchSeerrConfigured(ref)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    // An account that may not see the issues is told so, and nothing is
    // asked of the server: it would refuse.
    final blocked = _SeerrBlockedTab.of(
      ref,
      SeerrAbility.viewIssues,
      icon: Icons.report_problem_outlined,
      topPadding: widget.topPadding,
    );
    if (blocked != null) return blocked;
    // Seeing the issues is not resolving them: where the server would refuse
    // (anybody else's issue without MANAGE_ISSUES), Resolve reads dimmed with
    // why, never a tap that fails.
    final gate = ref.watch(roleGateProvider(''));
    final accountUserId = ref.watch(seerrActingUserIdProvider(''));
    final issues = ref.watch(seerrIssuesProvider(_filter));
    final partial = issues.asData?.value;
    final lens = ref.watch(
      activeInstanceProvider(ServiceKey.seerr).select((i) => i?.id),
    );
    return ServiceListPage<SeerrIssue>(
      service: ServiceKey.seerr,
      value: issues.whenDataKept((result) => result.items),
      serviceName: 'Seerr issues',
      onRetry: () => ref.invalidate(seerrIssuesProvider(_filter)),
      // How many, in which state, and in what order: a list cut short reads
      // as a floor (`50+`), never as the whole.
      summary: (items) {
        final count = partial != null && partial.isPartial
            ? '${items.length}+'
            : '${items.length}';
        final what = switch (_filter) {
          SeerrIssueFilter.open => 'open',
          SeerrIssueFilter.resolved => 'resolved',
          SeerrIssueFilter.all => items.length == 1 ? 'issue' : 'issues',
        };
        return '$count $what${dotSeparator}the newest change first';
      },
      emptyIcon: Icons.report_problem_outlined,
      emptyTitle: 'No issues',
      emptyMessage: 'Seerr has no issues in this view.',
      topPadding: widget.topPadding,
      // Top only: the pills carry the gutter themselves, so a side inset here
      // put them a second gutter in from the rows below.
      header: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: SelectionPills<SeerrIssueFilter>(
          values: SeerrIssueFilter.values,
          selected: _filter,
          labelBuilder: (filter) => filter.label,
          onSelected: (value) => setState(() => _filter = value),
        ),
      ),
      banner: partial != null && partial.isPartial
          ? FaultBand.partial(
              message:
                  'Seerr returned ${partial.items.length} of '
                  '${partial.total} issues; later pages are unavailable.',
              onRetry: () => ref.invalidate(seerrIssuesProvider(_filter)),
            )
          : null,
      rowBuilder: (issue) => SeerrIssueRow(
        issue: issue,
        connectionId: lens ?? '',
        onOpen: () =>
            context.push(ServiceRoutes.seerrIssue(issue.id, instanceId: lens)),
        // The record's own status, not the filter that fetched it: keyed on
        // the filter, the "All" tab offered Resolve on nothing at all, open
        // issues included.
        onResolve: issue.isOpen ? () => _resolve(issue) : null,
        resolve: gate.resolveIssueAction(
          own:
              issue.createdBy?.id != null &&
              issue.createdBy?.id == accountUserId,
        ),
      ),
    );
  }

  Future<void> _resolve(SeerrIssue issue) async {
    // Asked first: the check glyph sat at the end of every row and resolved
    // on the tap, closing the issue for whoever reported it. It can be
    // reopened from the issue's own page, but it is not a free click.
    final result = await showResolveIssueConfirm(context, issue);
    if (!result.confirmed || !mounted) return;

    // A write, so the failure surfaces. Unguarded, a token that had lost
    // `MANAGE_ISSUES` threw out of the button callback: nothing invalidated,
    // nothing said, and the row still open, indistinguishable from a tap that
    // never registered.
    try {
      await ref.read(seerrServiceProvider).resolveIssue(issue.id);
      // Every list and page that speaks of the issue reads it again.
      final container = ref.container;
      final connection =
          ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
      if (mediaKeyOfIssue(issue) case final key?) {
        readReportsAgain(container, key: key, connectionId: connection);
      } else {
        container
          ..invalidate(mediaReportIssueProvider)
          ..invalidate(seerrIssuesProvider);
      }
      if (!mounted) return;
      SnackBarHelper.success(context, 'Issue resolved');
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not resolve the issue',
        detail: error,
      );
    }
  }
}

/// `Resolve this issue?` for the Issues tab: it names the title and the type,
/// and says who it closes the issue for and that it can be reopened.
Future<AppConfirmResult> showResolveIssueConfirm(
  BuildContext context,
  SeerrIssue issue, {
  bool useRootNavigator = true,
}) {
  final reporter = issue.createdBy?.displayName;
  return showAppConfirmDialog(
    context: context,
    useRootNavigator: useRootNavigator,
    icon: Icons.check_circle_outline_rounded,
    title: 'Resolve this issue?',
    message: [
      '${issue.media?.title ?? 'Unknown media'}\u00A0· ${issue.issueTypeLabel}.',
      'Seerr marks it resolved for ${reporter ?? 'whoever reported it'}. '
          'It can be reopened.',
    ].join('\n\n'),
    confirmLabel: 'Resolve issue',
    enterConfirms: true,
  );
}

class SeerrUsersScreen extends ConsumerWidget {
  const SeerrUsersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The lens's Seerr, which these pages read: a signed-out one reads signed
    // out before anything is asked of it.
    if (!watchSeerrConfigured(ref)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    // The users are the operator's to manage: an account that may not is
    // told so, and the list is not read.
    final blocked = _SeerrBlockedTab.of(
      ref,
      SeerrAbility.manageUsers,
      icon: Icons.people_outline_rounded,
      topPadding: topPadding,
    );
    if (blocked != null) return blocked;
    final users = ref.watch(seerrUsersProvider);
    final partial = users.asData?.value;
    return ServiceListPage<SeerrUser>.unsummarised(
      service: ServiceKey.seerr,
      value: users.whenDataKept((result) => result.items),
      serviceName: 'Seerr users',
      onRetry: () => ref.invalidate(seerrUsersProvider),
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No users',
      emptyMessage: 'Seerr returned no users.',
      topPadding: topPadding,
      banner: partial != null && partial.isPartial
          ? FaultBand.partial(
              message:
                  'Seerr returned ${partial.items.length} of '
                  '${partial.total} users; later pages are unavailable.',
              onRetry: () => ref.invalidate(seerrUsersProvider),
            )
          : null,
      rowBuilder: (user) => _UserCard(user: user),
    );
  }
}

/// A tab of the Seerr room the lens's account may not use: why, in place of
/// the list, and no read the server would refuse.
///
/// The operator reads it about the account (`Your account on Seerr can't
/// see issues.`); a household member, who has no Seerr room in their app,
/// reads it about themselves.
class _SeerrBlockedTab extends StatelessWidget {
  const _SeerrBlockedTab({
    required this.reason,
    required this.icon,
    required this.topPadding,
  });

  /// The tab for [ability] on the lens's Seerr, or null when the account may.
  static Widget? of(
    WidgetRef ref,
    SeerrAbility ability, {
    required IconData icon,
    required double topPadding,
  }) {
    final verdict = ref.watch(roleGateProvider('')).operatorAction(ability);
    if (verdict.acts) return null;
    return _SeerrBlockedTab(
      reason: switch (verdict) {
        Dimmed(:final reason) => reason,
        _ => RoleGateCopy.youCannot(ability),
      },
      icon: icon,
      topPadding: topPadding,
    );
  }

  final String reason;
  final IconData icon;
  final double topPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: topPadding + MediaQuery.paddingOf(context).top,
    ),
    child: AppEmptyState(icon: icon, title: reason),
  );
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final SeerrUser user;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.substring(0, 1).toUpperCase();
    return AppCard.outlined(
      semanticLabel: user.displayName,
      semanticValue: '${user.requestCount ?? '—'} requests',
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: ServiceKey.seerr.accent.withValues(alpha: 0.15),
            child: Text(initial),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email ?? '—',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Text(
            '${user.requestCount ?? '—'} requests',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
