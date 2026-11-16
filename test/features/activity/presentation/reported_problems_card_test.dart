/// The card of the problems people reported, in Needs you, and its line on
/// the Home: what each says and what each tap opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/activity/presentation/widgets/reported_problems_card.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

DashboardDecision _member(int id, String title, String detail) =>
    DashboardDecision(
      kind: DecisionKind.reportedProblems,
      id: 'seerr-issue-seerr-$id',
      service: ServiceKey.seerr,
      title: title,
      detail: detail,
      occurredAt: DateTime.utc(2020, 9, 26, 12),
      actionId: id,
      instanceId: 'seerr',
      route: '/stack/seerr/issues/$id?i=seerr',
    );

DashboardDecision _problems({int count = 3, List<String>? reporters}) =>
    DashboardDecision(
      kind: DecisionKind.reportedProblems,
      id: 'seerr-issues-seerr',
      service: ServiceKey.seerr,
      title: '$count reported problems',
      detail: 'Seerr\u00A0· Issues',
      occurredAt: DateTime.utc(2020, 9, 26, 12),
      route: ServiceRoutes.seerrIssues,
      count: count,
      instanceId: 'seerr',
      reporters: reporters ?? const ['Luca', 'Anna'],
      members: [
        _member(3, 'Tears of Steel', 'Video\u00A0· Luca'),
        _member(2, 'Cosmos Laundromat', 'S2\u00A0E3\u00A0· Audio\u00A0· Anna'),
        _member(1, 'Big Buck Bunny', 'Subtitles\u00A0· Anna'),
      ],
    );

void main() {
  /// [card] on a router that answers where it leads with the location.
  Future<(ProfileHarness, List<String>)> pump(
    WidgetTester tester,
    Widget card,
  ) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: SingleChildScrollView(child: card)),
        ),
        GoRoute(
          path: '/stack/seerr/issues',
          builder: (_, state) {
            seen.add(state.uri.toString());
            return const SizedBox.shrink();
          },
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) {
                seen.add(state.uri.toString());
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await harness.settle(tester);
    return (harness, seen);
  }

  testWidgets('says the count, the Seerr, who said it, the newest three '
      'and the remedy with its number', (tester) async {
    final (harness, _) = await pump(
      tester,
      ReportedProblemsCard(decision: _problems(), whole: true),
    );

    expect(find.text('3 reported problems'), findsOneWidget);
    expect(find.text('Seerr\u00A0· Issues'), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    expect(
      find.text('Luca and Anna say something is wrong with what they watch.'),
      findsOneWidget,
    );
    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.textContaining('Video\u00A0· Luca\u00A0· '), findsOneWidget);
    expect(
      find.textContaining('S2\u00A0E3\u00A0· Audio\u00A0· Anna\u00A0· '),
      findsOneWidget,
    );
    expect(find.text('Review 3'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a mini row opens its own issue', (tester) async {
    final (harness, seen) = await pump(
      tester,
      ReportedProblemsCard(decision: _problems()),
    );

    await tester.tap(find.text('Cosmos Laundromat'));
    await harness.settle(tester);

    expect(seen, ['/stack/seerr/issues/2?i=seerr']);

    await harness.unmount(tester);
  });

  testWidgets('Review opens the Issues tab', (tester) async {
    final (harness, seen) = await pump(
      tester,
      ReportedProblemsCard(decision: _problems()),
    );

    await tester.tap(find.text('Review 3'));
    await harness.settle(tester);

    expect(seen.single, startsWith(ServiceRoutes.seerrIssues));
    expect(seen.single, isNot(contains('/issues/')));

    await harness.unmount(tester);
  });

  testWidgets('Review lands on Open whichever filter the tab was left on', (
    tester,
  ) async {
    final (harness, seen) = await pump(
      tester,
      ReportedProblemsCard(decision: _problems()),
    );
    // The tab's branch stays mounted: it holds Resolved from before.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReportedProblemsCard)),
    );
    container
        .read(seerrIssueFilterProvider.notifier)
        .choose(SeerrIssueFilter.resolved);

    await tester.tap(find.text('Review 3'));
    await harness.settle(tester);

    expect(seen.single, startsWith(ServiceRoutes.seerrIssues));
    expect(container.read(seerrIssueFilterProvider), SeerrIssueFilter.open);

    await harness.unmount(tester);
  });

  testWidgets('with no rows read the card is the count, the source and the '
      'remedy, and says nobody', (tester) async {
    final lone = DashboardDecision(
      kind: DecisionKind.reportedProblems,
      id: 'seerr-issues-seerr',
      service: ServiceKey.seerr,
      title: '1 reported problem',
      detail: 'Seerr\u00A0· Issues',
      occurredAt: null,
      route: ServiceRoutes.seerrIssues,
      instanceId: 'seerr',
    );
    final (harness, _) = await pump(
      tester,
      ReportedProblemsCard(decision: lone),
    );

    expect(find.text('1 reported problem'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.textContaining('say something'), findsNothing);
    expect(find.textContaining('says something'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a line of a wide list is the plain fault line, with the same '
      'words and remedy', (tester) async {
    final (harness, _) = await pump(
      tester,
      NeedsYouCard.row(
        entry: (id: 'x', decision: _problems(), downloadKey: null),
      ),
    );

    expect(find.byType(ReportedProblemsCard), findsNothing);
    expect(find.text('3 reported problems'), findsOneWidget);
    expect(find.text('Review 3'), findsOneWidget);

    await harness.unmount(tester);
  });

  group('the Home line', () {
    final now = DateTime(2026, 10, 9, 20, 53);

    Future<void> line(
      WidgetTester tester,
      List<DashboardDecision> faults,
    ) async {
      final needs = needsYouOf(silent: const [], decisions: faults, now: now)!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: NeedsYouLine(needs: needs, onTap: () {}),
          ),
        ),
      );
    }

    testWidgets('leads with the flag, the count and Review, with the others '
        'as +N', (tester) async {
      await line(tester, [
        DashboardDecision(
          kind: DecisionKind.stalledDownload,
          id: 'stall',
          service: ServiceKey.radarr,
          title: 'Big Buck Bunny',
          detail: 'x',
          occurredAt: null,
        ),
        _problems(),
      ]);

      expect(find.text('3 reported problems'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('another lead keeps its warning', (tester) async {
      await line(tester, [
        DashboardDecision(
          kind: DecisionKind.stalledDownload,
          id: 'stall',
          service: ServiceKey.radarr,
          title: 'Big Buck Bunny',
          detail: 'x',
          occurredAt: null,
        ),
      ]);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.flag_rounded), findsNothing);
    });
  });
}
