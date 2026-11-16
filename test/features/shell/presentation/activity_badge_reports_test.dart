/// Activity's badge counts what Needs you lists as faults, the problems people
/// reported on Seerr included; the sidebar's per-service counts do not.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_decisions.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/activity_badge.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart';

DashboardDecision _decision(DecisionKind kind, ServiceKey service, int count) =>
    DashboardDecision(
      kind: kind,
      id: '${kind.name}-${service.name}',
      service: service,
      title: 'Title',
      detail: 'Detail',
      occurredAt: null,
      count: count,
    );

final _decisions = [
  _decision(DecisionKind.reportedProblems, ServiceKey.seerr, 1),
  _decision(DecisionKind.importBlocked, ServiceKey.radarr, 2),
];

void main() {
  test('one open report is a number on the badge', () {
    final container = ProviderContainer(
      overrides: [
        audienceProvider.overrideWithValue(Audience.operator),
        dashboardDecisionsProvider.overrideWithValue((
          decisions: [_decisions.first],
          coverage: SourceCoverage.none,
        )),
        pendingRequestCountProvider.overrideWith((ref) async => null),
        unseenReleaseSearchCountProvider.overrideWithValue(0),
      ],
    );
    addTearDown(container.dispose);

    final badge = container.read(activityBadgeProvider);
    expect(badge?.count, 1);
    expect(badge?.spoken, '1 needs you');
  });

  test(
    'the badge sums the reports with the other faults, as Needs you does',
    () {
      final container = ProviderContainer(
        overrides: [
          audienceProvider.overrideWithValue(Audience.operator),
          dashboardDecisionsProvider.overrideWithValue((
            decisions: _decisions,
            coverage: SourceCoverage.none,
          )),
          pendingRequestCountProvider.overrideWith((ref) async => null),
          unseenReleaseSearchCountProvider.overrideWithValue(0),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(activityBadgeProvider)?.count, 3);
    },
  );

  test('the sidebar’s counts still leave the reports out: Seerr is not '
      'failing', () {
    expect(faultCountsByService(_decisions), {ServiceKey.radarr: 2});
    expect(faultCountsByService(_decisions, withReports: true), {
      ServiceKey.radarr: 2,
      ServiceKey.seerr: 1,
    });
  });
}
