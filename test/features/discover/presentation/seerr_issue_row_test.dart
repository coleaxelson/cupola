/// The Issues tab: each row, what it says in its tone, the target it makes
/// of itself, and Resolve at its end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

final _now = DateTime.now();
final _yesterday = DateTime(_now.year, _now.month, _now.day - 1, 21, 40);

SeerrIssue _issue(
  int id, {
  String title = 'Tears of Steel',
  int season = 0,
  int episode = 0,
  int type = 1,
  int status = 1,
  String by = 'Luca',
  String message = 'It plays a different movie: the file is Sintel.',
  int replies = 0,
}) =>
    SeerrIssue.fromJson({
      'id': id,
      'issueType': type,
      'status': status,
      'problemSeason': season,
      'problemEpisode': episode,
      'createdAt': _yesterday.toUtc().toIso8601String(),
      'updatedAt': _yesterday.toUtc().toIso8601String(),
      'media': {
        'id': 80 + id,
        'mediaType': season > 0 ? 'tv' : 'movie',
        'tmdbId': 600 + id,
      },
      'createdBy': {'id': 5, 'displayName': by},
      'comments': [
        {'id': id * 10, 'message': message},
        for (var i = 0; i < replies; i++)
          {'id': id * 10 + i + 1, 'message': 'r'},
      ],
    }).copyWith(
      media: SeerrIssueMedia(
        id: 80 + id,
        tmdbId: 600 + id,
        title: title,
        mediaType: season > 0 ? 'tv' : 'movie',
      ),
    );

RoleGate _manager() =>
    const RoleGate(audience: Audience.operator, grant: SeerrGrant.apiKey());

RoleGate _cannotManage() => RoleGate(
  audience: Audience.operator,
  grant: SeerrGrant.account(permissions: SeerrPermission.viewIssues.value),
  server: SeerrServerFacts.fromPublicSettings({
    'initialized': true,
    'applicationTitle': 'Casa Requests',
  }),
);

Future<List<String>> _pump(
  WidgetTester tester, {
  required List<SeerrIssue> issues,
  RoleGate? gate,
  FakeSeerrService? service,
  double textScale = 1,
  bool partial = false,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: SeerrIssuesScreen(topPadding: 0)),
      ),
      GoRoute(
        path: '/stack/seerr/issues/:issueId',
        builder: (context, state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('The issue'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: <Override>[
        ...await settingsScopeOverrides(configured: [ServiceKey.seerr]),
        audienceProvider.overrideWithValue(Audience.operator),
        roleGateProvider.overrideWith((ref, id) => gate ?? _manager()),
        seerrAccountUserIdProvider.overrideWith((ref, id) => 1),
        seerrServiceProvider.overrideWith(
          (ref) => service ?? FakeSeerrService(),
        ),
        seerrIssuesProvider.overrideWith(
          (ref, filter) async => SeerrAdminResult<SeerrIssue>(
            items: issues,
            total: partial ? 80 : issues.length,
            isPartial: partial,
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

/// A row's state word, not the filter pill of the same name.
Finder _stateWords(String word) =>
    find.descendant(of: find.byType(MediaStateWord), matching: find.text(word));

void main() {
  testWidgets('a row: title, state, who and when, the words, the replies', (
    tester,
  ) async {
    await _pump(
      tester,
      issues: [
        _issue(1, replies: 2),
        _issue(
          2,
          title: 'Cosmos Laundromat',
          season: 2,
          episode: 3,
          type: 2,
          by: 'Anna',
          message: 'The audio is in Russian, the subtitles say English.',
        ),
      ],
    );
    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(_stateWords('Open'), findsNWidgets(2));
    expect(find.text('Video\u00A0· Luca\u00A0· yesterday'), findsOneWidget);
    expect(
      find.text(
        '${formatEpisodeCode(2, 3)}\u00A0· Audio\u00A0· Anna\u00A0· yesterday',
      ),
      findsOneWidget,
    );
    expect(
      find.text('It plays a different movie: the file is Sintel.'),
      findsOneWidget,
    );
    expect(find.text('2 replies'), findsOneWidget);
    // The one with no replies says nothing of them.
    expect(find.textContaining('repl'), findsOneWidget);
    // How many, in which state and in what order.
    expect(find.text('2 open\u00A0· the newest change first'), findsOneWidget);
  });

  testWidgets('a resolved row is green and has nothing to resolve', (
    tester,
  ) async {
    await _pump(tester, issues: [_issue(1, status: 2)]);
    expect(_stateWords('Resolved'), findsOneWidget);
    expect(_stateWords('Open'), findsNothing);
    expect(find.byTooltip('Resolve issue'), findsNothing);
  });

  testWidgets('a list cut short counts as a floor', (tester) async {
    await _pump(tester, issues: [_issue(1), _issue(2)], partial: true);
    expect(find.text('2+ open\u00A0· the newest change first'), findsOneWidget);
  });

  testWidgets('the whole row opens the issue, on its connection', (
    tester,
  ) async {
    final opened = await _pump(tester, issues: [_issue(7, replies: 1)]);
    await tester.tap(
      find.text('It plays a different movie: the file is Sintel.'),
    );
    await tester.pumpAndSettle();
    expect(opened, ['/stack/seerr/issues/7?i=seerr']);
    expect(find.text('The issue'), findsOneWidget);
  });

  testWidgets(
    'Resolve is a 44pt button of its own: it asks, and does not open',
    (tester) async {
      final service = FakeSeerrService();
      final opened = await _pump(
        tester,
        issues: [_issue(7, by: 'Anna')],
        service: service,
      );
      final size = tester.getSize(find.byTooltip('Resolve issue'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byTooltip('Resolve issue'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Resolve this issue?'), findsOneWidget);
      expect(
        find.textContaining(
          'Seerr marks it resolved for Anna. It can be reopened.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve issue'));
      await tester.pumpAndSettle();
      expect(service.resolveIssueCalled, isTrue);
    },
  );

  testWidgets('an account that cannot manage issues: dimmed, and says why', (
    tester,
  ) async {
    final service = FakeSeerrService();
    await _pump(
      tester,
      issues: [_issue(7)],
      gate: _cannotManage(),
      service: service,
    );
    await tester.tap(find.byTooltip('Resolve issue'));
    await tester.pump();
    expect(
      find.text("Your account on Casa Requests can't manage issues."),
      findsOneWidget,
    );
    expect(service.resolveIssueCalled, isFalse);
    expect(find.text('Resolve this issue?'), findsNothing);
  });

  testWidgets('at twice the reading size the words are whole', (tester) async {
    const long =
        'The Italian subtitles run two seconds late from the start, all the '
        'way through, and one line is cut in the middle of a word.';
    await _pump(
      tester,
      issues: [_issue(1, message: long, replies: 2)],
      textScale: 2,
    );
    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at the reading size the words keep two lines', (tester) async {
    const long =
        'The Italian subtitles run two seconds late from the start, all the '
        'way through, and one line is cut in the middle of a word.';
    await _pump(tester, issues: [_issue(1, message: long)]);
    expect(tester.widget<Text>(find.text(long)).maxLines, 2);
  });
}
