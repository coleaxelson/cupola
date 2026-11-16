/// `Your reports` on her page of requests: what she reported, under what she
/// asked for, from her own session and only where her account may list them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Anna's account, which may report: REQUEST and CREATE_ISSUES.
final _mayReport = RoleGate(
  audience: Audience.requester,
  grant: SeerrGrant.account(
    permissions:
        SeerrPermission.request.value | SeerrPermission.createIssues.value,
  ),
);

SeerrIssue _report(
  int id,
  String title, {
  required SeerrIssueType type,
  SeerrIssueStatus status = SeerrIssueStatus.open,
  int season = 0,
  int episode = 0,
  String updatedAt = '2026-09-28T12:00:00.000Z',
  int replies = 0,
  int by = 7,
}) => SeerrIssue(
  id: id,
  type: type,
  status: status,
  problemSeason: season,
  problemEpisode: episode,
  media: SeerrIssueMedia(title: title, mediaType: 'movie'),
  createdBy: SeerrUser(id: by),
  createdAt: '2026-09-26T12:00:00.000Z',
  updatedAt: updatedAt,
  comments: [
    const SeerrIssueComment(id: 1, message: 'It is wrong'),
    for (var i = 0; i < replies; i++)
      SeerrIssueComment(id: 2 + i, message: 'Looking'),
  ],
);

/// The same issue with its conversation, the replies named.
SeerrIssue _conversation(SeerrIssue list, {required String replier}) =>
    SeerrIssue(
      id: list.id,
      type: list.type,
      status: list.status,
      media: list.media,
      createdBy: list.createdBy,
      problemSeason: list.problemSeason,
      problemEpisode: list.problemEpisode,
      createdAt: list.createdAt,
      updatedAt: list.updatedAt,
      comments: [
        const SeerrIssueComment(
          id: 1,
          message: 'It is wrong',
          authorId: 7,
          authorName: 'Anna',
        ),
        SeerrIssueComment(
          id: 2,
          message: 'Looking',
          authorId: 1,
          authorName: replier,
        ),
      ],
    );

void main() {
  final now = DateTime(2026, 10, 9, 20, 30);
  final reports = [
    _report(
      12,
      'Cosmos Laundromat',
      type: SeerrIssueType.audio,
      season: 2,
      episode: 3,
      updatedAt: '2026-10-01T12:00:00.000Z',
      replies: 1,
    ),
    _report(
      9,
      'Big Buck Bunny',
      type: SeerrIssueType.subtitles,
      status: SeerrIssueStatus.resolved,
    ),
  ];

  /// Her page over [reads], with [gate] saying what her account may do, the
  /// router answering a report's page with its location.
  Future<(ProfileHarness, List<String>)> pump(
    WidgetTester tester, {
    Future<SeerrAdminResult<SeerrIssue>> Function()? reads,
    RoleGate? gate,
    ConfigProfile? profile,
    List<int>? asked,
    bool conversationOut = false,
  }) async {
    final opened = <String>[];
    final harness = await ProfileHarness.start(
      profile ?? Profiles.p2,
      now: now,
      overrides: [
        calendarClockProvider.overrideWithValue(() => now),
        roleGateProvider.overrideWith(
          (ref, id) =>
              gate ??
              RoleGate(
                audience: Audience.requester,
                grant: SeerrGrant.account(
                  permissions: SeerrPermission.request.value,
                ),
              ),
        ),
        // Anna, whose reports these are.
        seerrActingUserIdProvider.overrideWith((ref, id) => 7),
        ownIssuesProvider.overrideWith((ref, id) {
          asked?.add(1);
          return (reads ??
              () async => SeerrAdminResult(items: const [], total: 0))();
        }),
        mediaReportIssueProvider.overrideWith(
          (ref, source) => conversationOut
              ? Completer<SeerrIssue>().future
              : Future.value(
                  _conversation(
                    reports.firstWhere((report) => report.id == source.issueId),
                    replier: 'Matt',
                  ),
                ),
        ),
      ],
    );
    harness.network.followFakeTime(tester.binding);
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const RequestsScreen()),
        GoRoute(
          path: '/requests/issues/:id',
          builder: (_, state) {
            opened.add(state.uri.toString());
            return const SizedBox.shrink();
          },
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
    return (harness, opened);
  }

  testWidgets('her reports come after her requests: how many are open, one '
      'row each, the newest change first', (tester) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      // Read oldest first: the page orders them.
      reads: () async =>
          SeerrAdminResult(items: reports.reversed.toList(), total: 2),
    );

    expect(find.text('Your reports'), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);
    // After the last of her requests.
    expect(
      tester.getTopLeft(find.text('Your reports')).dy,
      greaterThan(tester.getBottomLeft(find.text('Tears of Steel')).dy),
    );
    // The newest change first: the open one changed on 1 Oct, the resolved
    // one on 28 Sep.
    expect(
      tester.getTopLeft(find.text('Cosmos Laundromat\u00A0· S2\u00A0E3')).dy,
      lessThan(tester.getTopLeft(find.text('Big Buck Bunny')).dy),
    );
    expect(find.text('Reported'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    // The reply, by whom, once her conversation was read; the day otherwise.
    expect(find.text('Audio\u00A0· 1 reply from Matt'), findsOneWidget);
    expect(find.text('Subtitles\u00A0· Mon 28 Sep'), findsOneWidget);
    // Never a service name.
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('before her conversation is read a reply is counted, not '
      'attributed', (tester) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      reads: () async => SeerrAdminResult(items: [reports.first], total: 1),
    );
    // Not settled: the conversation is out.
    expect(find.text('Audio\u00A0· 1 reply'), findsNothing);
    expect(find.text('Audio\u00A0· 1 reply from Matt'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('an account that may view every issue reads only its own under '
      'Your reports, and counts only those', (tester) async {
    final viewsAll = RoleGate(
      audience: Audience.requester,
      grant: SeerrGrant.account(
        permissions:
            SeerrPermission.request.value | SeerrPermission.viewIssues.value,
      ),
    );
    final (harness, _) = await pump(
      tester,
      gate: viewsAll,
      reads: () async => SeerrAdminResult(
        items: [
          reports.first,
          _report(
            30,
            'Hero',
            type: SeerrIssueType.video,
            by: 99,
            updatedAt: '2026-10-05T12:00:00.000Z',
          ),
          _report(
            31,
            'Agent 327',
            type: SeerrIssueType.video,
            by: 99,
            updatedAt: '2026-10-06T12:00:00.000Z',
          ),
        ],
        total: 3,
      ),
    );

    expect(find.text('Your reports'), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('Cosmos Laundromat\u00A0· S2\u00A0E3'), findsOneWidget);
    expect(find.text('Hero'), findsNothing);
    expect(find.text('Agent 327'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a read cut short counts hers as a floor', (tester) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      reads: () async =>
          SeerrAdminResult(items: [reports.first], total: 400, isPartial: true),
    );

    expect(find.text('1+ open'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('only resolved reports: no count of open ones', (tester) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      reads: () async => SeerrAdminResult(items: [reports.last], total: 1),
    );

    expect(find.text('Your reports'), findsOneWidget);
    expect(find.textContaining('open'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a report opens her page of it, on her Seerr', (tester) async {
    final (harness, opened) = await pump(
      tester,
      gate: _mayReport,
      reads: () async => SeerrAdminResult(items: reports, total: 2),
    );

    await tester.ensureVisible(find.text('Big Buck Bunny'));
    await tester.pump();
    await tester.tap(find.text('Big Buck Bunny'));
    await harness.settle(tester);

    expect(opened, hasLength(1));
    expect(opened.single, startsWith('/requests/issues/9'));

    await harness.unmount(tester);
  });

  testWidgets('no reports: no section', (tester) async {
    final (harness, _) = await pump(tester, gate: _mayReport);

    expect(find.text('Your reports'), findsNothing);
    // Her requests are there all the same.
    expect(find.text('Tears of Steel'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a refusal: no section, and her requests as they were', (
    tester,
  ) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      reads: () async => throw Exception('refused'),
    );

    expect(find.text('Your reports'), findsNothing);
    expect(find.text('Tears of Steel'), findsOneWidget);
    // The page's own line is for a silent server, and Seerr answered.
    expect(find.text('Retry'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('an account that may not list issues asks the server nothing '
      'and draws nothing', (tester) async {
    final asked = <int>[];
    final (harness, _) = await pump(
      tester,
      asked: asked,
      reads: () async => SeerrAdminResult(items: reports, total: 2),
    );

    expect(find.text('Your reports'), findsNothing);
    expect(asked, isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('a Seerr that did not answer draws her one line and no '
      'reports', (tester) async {
    final (harness, _) = await pump(
      tester,
      gate: _mayReport,
      profile: Profiles.p2.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.didNotAnswer,
      ),
      reads: () async => SeerrAdminResult(items: reports, total: 2),
    );

    expect(find.text('Your reports'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await harness.unmount(tester);
  });
}
