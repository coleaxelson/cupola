/// Reporting a problem with a title: where the row is drawn and when, the
/// gate, the sheet, what it sends, and how each failure reads.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart' show episodeCodeSpace;
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/media_report_row.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/media/presentation/report_problem_sheet.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fixtures.dart';
import '../../../test_helpers/settings_scope.dart';

const _movie = MediaKey.movie(653);
const _tv = MediaKey.tv(358332);

final _anna = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'https://seerr.test',
  account: const SeerrAccountSignIn(
    kind: SeerrAccountKind.local,
    userId: 2,
    displayName: 'Anna',
    session: 's',
  ),
);
final _key = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'https://seerr.test',
  credential: 'k',
);

RoleGate _gate({
  bool may = true,
  Audience audience = Audience.requester,
  String? server,
}) => RoleGate(
  server: server == null
      ? null
      : SeerrServerFacts.fromPublicSettings({
          'initialized': true,
          'applicationTitle': server,
        }),
  audience: audience,
  grant: audience == Audience.operator && may
      ? const SeerrGrant.apiKey()
      : SeerrGrant.account(
          permissions:
              SeerrPermission.request.value |
              (may ? SeerrPermission.createIssues.value : 0),
        ),
);

List<MediaRow> _rows(
  ServiceInstance seerr, {
  Map<String, dynamic>? mediaInfo,
  bool movie = true,
}) => [
  MediaConnectionRow<MediaSeerrRecord>(
    seerr,
    MediaReadingAnswered(
      MediaAnswer(
        MediaSeerrRecord(
          details: movie
              ? {'title': 'Nosferatu', 'mediaInfo': ?mediaInfo}
              : {
                  'name': 'Cosmos Laundromat',
                  'firstAirDate': '2015-08-10',
                  'seasons': [
                    {'seasonNumber': 0, 'episodeCount': 2},
                    {'seasonNumber': 1, 'episodeCount': 10},
                    {'seasonNumber': 2, 'episodeCount': 10},
                    {'seasonNumber': 3, 'episodeCount': 8},
                  ],
                  'mediaInfo': ?mediaInfo,
                },
        ),
        DateTime(2026, 10, 3),
      ),
    ),
  ),
];

Map<String, dynamic> _info({
  int status = 5,
  List<Map<String, dynamic>> issues = const [],
}) => {'id': 81, 'status': status, 'issues': issues};

Map<String, dynamic> _seriesInfo() => {
  'id': 90,
  'status': 4,
  'issues': <Object>[],
  'seasons': [
    {'seasonNumber': 0, 'status': 5},
    {'seasonNumber': 1, 'status': 5},
    {'seasonNumber': 2, 'status': 4},
    {'seasonNumber': 3, 'status': 1},
  ],
};

Map<String, dynamic> _issue(int id, {int status = 1, int by = 2}) => {
  'id': id,
  'issueType': 1,
  'status': status,
  'createdAt': '2026-09-26T21:40:00Z',
  'updatedAt': '2026-09-26T21:40:00Z',
  'createdBy': {'id': by, 'displayName': by == 2 ? 'Anna' : 'Luca'},
};

class _Client extends FakeApiClient {
  _Client({
    this.error,
    this.hang = false,
    this.held,
    this.readError,
    this.whole = const {},
  });

  final Object? error;
  final bool hang;
  final posts = <Object?>[];

  /// What `GET /issue` answers: the issues the server holds. Null answers
  /// nothing at all.
  final List<Map<String, dynamic>>? held;

  /// What `GET /issue/{id}` answers, by id: the whole issue, replies included.
  final Map<int, Map<String, dynamic>> whole;

  /// What `GET /issue` fails with, when the read-back is meant to fail.
  final Object? readError;
  var reads = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    reads++;
    if (readError != null) return Future.error(readError!);
    final one = RegExp(r'/issue/(\d+)$').firstMatch(path);
    if (one != null) {
      return Future.value(
        Response(
          requestOptions: RequestOptions(path: path),
          data: whole[int.parse(one.group(1)!)],
        ),
      );
    }
    return Future.value(
      Response(
        requestOptions: RequestOptions(path: path),
        data: {
          'results': held ?? const <Object>[],
          'pageInfo': {'results': held?.length ?? 0},
        },
      ),
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) {
    posts.add(data);
    if (hang) return Completer<Response<dynamic>>().future;
    if (error != null) return Future.error(error!);
    return Future.value(
      Response(
        requestOptions: RequestOptions(path: path),
        data: jsonFixtureMap('seerr/issue_created.json'),
      ),
    );
  }
}

DioException _failed({
  DioExceptionType type = DioExceptionType.badResponse,
  int? status,
  Object? body,
  Object? cause,
}) => DioException(
  requestOptions: RequestOptions(path: '/api/v1/issue', method: 'POST'),
  type: type,
  error: cause,
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: '/api/v1/issue'),
          statusCode: status,
          data: body,
        ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required List<MediaRow> rows,
  required RoleGate gate,
  _Client? client,
  int? userId,
  Map<String, dynamic>? detail,
  Audience audience = Audience.requester,
  bool hangRead = false,
  bool failRead = false,
  List<String>? opened,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: <Override>[
        ...await settingsScopeOverrides(configured: [ServiceKey.seerr]),
        // The probe is not the scene's to run: it answers as if it had.
        instanceSummaryProvider.overrideWith(
          (ref, key) async => ServiceSummary(
            service: key.service,
            status: ServiceSummaryStatus.offline,
            host: 'seerr.test',
            version: null,
          ),
        ),
        mediaRowsProvider.overrideWith((ref, key) => rows),
        audienceProvider.overrideWithValue(audience),
        roleGateProvider.overrideWith((ref, id) => gate),
        seerrAccountUserIdProvider.overrideWith((ref, id) => userId),
        seerrServiceForProvider.overrideWith(
          (ref, id) => SeerrService(
            client ?? _Client(),
            numbering: SeerrNumbering.seerr,
          ),
        ),
        mediaReportIssueProvider.overrideWith(
          (ref, source) async => hangRead
              ? await Completer<SeerrIssue>().future
              : failRead
              ? throw StateError('no read')
              : SeerrIssue.fromJson(
                  detail ??
                      {
                        ..._issue(source.issueId),
                        'comments': [
                          {'id': 1, 'message': 'It freezes'},
                          {
                            'id': 2,
                            'message': 'Which copy?',
                            'user': {'id': 1, 'displayName': 'Matt'},
                          },
                        ],
                      },
                ),
        ),
        mediaSeasonFactsProvider.overrideWith(
          (ref, source) async => [
            for (var n = 1; n <= 3; n++)
              MediaEpisodeFacts(
                season: source.season,
                number: n,
                name: 'Name $n',
              ),
          ],
        ),
      ],
      child: opened == null
          ? MaterialApp(
              theme: AppTheme.darkTheme(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            )
          // A router that records where a tap leads and draws a stand-in
          // there: the issue's own page is the thread's test.
          : MaterialApp.router(
              theme: AppTheme.darkTheme(),
              routerConfig: GoRouter(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (context, state) => Scaffold(
                      body: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  for (final path in [
                    '/requests/issues/:issueId',
                    '/stack/seerr/issues/:issueId',
                  ])
                    GoRoute(
                      path: path,
                      builder: (context, state) {
                        opened.add(state.uri.toString());
                        return const Scaffold(body: Text('The issue'));
                      },
                    ),
                ],
              ),
            ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

MediaReportSource _source(List<MediaRow> rows, {bool movie = true}) =>
    mediaReportSourceOf(rows, movie: movie)!;

Future<void> _openSheet(
  WidgetTester tester, {
  required ServiceInstance seerr,
  bool movie = true,
  int season = 0,
  int episode = 0,
  _Client? client,
  Audience audience = Audience.requester,
  RoleGate? gate,
  int? userId = 2,
}) async {
  final rows = movie
      ? _rows(seerr, mediaInfo: _info())
      : _rows(seerr, mediaInfo: _seriesInfo(), movie: false);
  await _pump(
    tester,
    ReportProblemSheet(
      scope: (key: movie ? _movie : _tv, focus: null),
      source: _source(rows, movie: movie),
      season: season,
      episode: episode,
    ),
    rows: rows,
    gate: gate ?? _gate(audience: audience),
    client: client,
    audience: audience,
    userId: userId,
  );
}

Future<void> _fill(
  WidgetTester tester, {
  String type = 'Video',
  String text = '  It plays Sintel.  ',
}) async {
  await tester.tap(find.text(type));
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Submit report'));
  await tester.tap(find.text('Submit report'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('when a title can be reported', () {
    test('Seerr says it is on the server and names its media row', () {
      expect(
        mediaReportSourceOf(
          _rows(_anna, mediaInfo: _info()),
          movie: true,
        )?.mediaId,
        81,
      );
      // Not there, in Seerr's own states: requested, in the works, unknown.
      for (final status in [1, 2, 3]) {
        expect(
          mediaReportSourceOf(
            _rows(_anna, mediaInfo: _info(status: status)),
            movie: true,
          ),
          isNull,
        );
      }
      // No record at all, or one without an id.
      expect(mediaReportSourceOf(_rows(_anna), movie: true), isNull);
      expect(
        mediaReportSourceOf(
          _rows(_anna, mediaInfo: {'status': 5}),
          movie: true,
        ),
        isNull,
      );
      expect(mediaReportSourceOf(const [], movie: true), isNull);
    });

    test('the 4K copy counts, and partly available is a series only', () {
      expect(
        mediaReportSourceOf(
          _rows(_anna, mediaInfo: {'id': 1, 'status': 1, 'status4k': 5}),
          movie: true,
        ),
        isNotNull,
      );
      expect(
        mediaReportSourceOf(
          _rows(_anna, mediaInfo: _info(status: 4)),
          movie: true,
        ),
        isNull,
      );
      expect(
        mediaReportSourceOf(
          _rows(_anna, mediaInfo: _seriesInfo(), movie: false),
          movie: false,
        ),
        isNotNull,
      );
    });

    test('a series offers the seasons on the server, never Specials', () {
      final source = _source(
        _rows(_anna, mediaInfo: _seriesInfo(), movie: false),
        movie: false,
      );
      expect(source.seasons.map((s) => s.number), [1, 2]);
      expect(source.episodeCountOf(2), 10);
      expect(source.hasSeason(0), isFalse);
      expect(source.hasSeason(3), isFalse);
    });

    test('two Seerr that qualify: the focus, else the first', () {
      ServiceInstance seerr(String id) => ServiceInstance(
        id: id,
        service: ServiceKey.seerr,
        url: 'https://$id.test',
        credential: 'k',
      );
      final rows = [
        ..._rows(seerr('a'), mediaInfo: _info()),
        ..._rows(seerr('b'), mediaInfo: _info()),
      ];
      expect(mediaReportSourceOf(rows, movie: true)?.seerr.id, 'a');
      expect(mediaReportSourceOf(rows, movie: true, focus: 'b')?.seerr.id, 'b');
    });

    test('her own report is the open one when a newer one was resolved', () {
      final source = _source(
        _rows(
          _anna,
          mediaInfo: _info(
            issues: [
              {..._issue(1), 'createdAt': '2026-09-01T10:00:00Z'},
              {..._issue(2, status: 2), 'createdAt': '2026-10-01T10:00:00Z'},
            ],
          ),
        ),
      );
      expect(source.ownCurrent(2)?.id, 1);
    });

    test('her own latest report is the newest one she made', () {
      final source = _source(
        _rows(
          _anna,
          mediaInfo: _info(
            issues: [
              _issue(3, by: 3),
              {..._issue(1), 'createdAt': '2026-09-01T10:00:00Z'},
              _issue(2),
            ],
          ),
        ),
      );
      expect(source.ownCurrent(2)?.id, 2);
      expect(source.ownCurrent(null), isNull);
      expect(source.ownCurrent(9), isNull);
      expect(source.openIssues.map((i) => i.id), [3, 2, 1]);
    });
  });

  group('the requester\'s row', () {
    testWidgets('no Seerr record on the server, nothing is drawn', (
      tester,
    ) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(status: 2)),
        gate: _gate(),
      );
      expect(find.text('Report a problem'), findsNothing);
      expect(find.byType(PressableScale), findsNothing);
    });

    testWidgets('on the server: the way to report, one sentence', (
      tester,
    ) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info()),
        gate: _gate(),
        userId: 2,
      );
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Whoever runs the server sees it'), findsOneWidget);
      expect(find.textContaining('Seerr'), findsNothing);
    });

    testWidgets('dimmed: drawn, a 44pt target, its reason as the hint and '
        'as the toast on a tap, never disabled', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info()),
        gate: _gate(may: false),
        userId: 2,
      );
      const reason = "You can't report problems on this server.";
      final node = tester.getSemantics(find.byType(PressableScale));
      final data = node.getSemanticsData();
      expect(data.hint, reason);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, isNot(Tristate.isFalse));
      expect(
        tester.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Report a problem'));
      await tester.pump();
      expect(find.text(reason), findsOneWidget);
      expect(find.text('What\'s wrong?'), findsNothing);
    });

    testWidgets('her report is open: blue, the date and the replies from '
        'that one issue, then Report another problem', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12)])),
        gate: _gate(),
        userId: 2,
      );
      await tester.pump();
      expect(find.text('Your video report is open'), findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);
      expect(
        find.text('Sat 26 Sep${dotSeparator}1 reply from Matt'),
        findsOneWidget,
      );
      expect(find.text('Report another problem'), findsOneWidget);
      expect(find.text('Report a problem'), findsNothing);
      // The report and the way to report another both lead somewhere.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    });

    testWidgets('her report opens, under her Requests tab, on its connection', (
      tester,
    ) async {
      final opened = <String>[];
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12)])),
        gate: _gate(),
        userId: 2,
        opened: opened,
      );
      await tester.tap(find.text('Your video report is open'));
      await tester.pumpAndSettle();
      expect(opened, ['/requests/issues/12?i=seerr']);
      expect(find.text('The issue'), findsOneWidget);
    });

    testWidgets('her resolved report opens too', (tester) async {
      final opened = <String>[];
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12, status: 2)])),
        gate: _gate(),
        userId: 2,
        opened: opened,
      );
      await tester.tap(find.text('Your video report was resolved'));
      await tester.pumpAndSettle();
      expect(opened, ['/requests/issues/12?i=seerr']);
    });

    testWidgets('an open issue opens, inside Seerr\'s Issues tab', (
      tester,
    ) async {
      final opened = <String>[];
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: _rows(_key, mediaInfo: _info(issues: [_issue(12, by: 3)])),
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
        opened: opened,
      );
      await tester.tap(find.text('It freezes'));
      await tester.pumpAndSettle();
      expect(opened, ['/stack/seerr/issues/12?i=seerr']);
      expect(find.text('The issue'), findsOneWidget);
    });

    testWidgets('her report was resolved: green, then Report a problem', (
      tester,
    ) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12, status: 2)])),
        gate: _gate(),
        userId: 2,
      );
      expect(find.text('Your video report was resolved'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Report a problem'), findsOneWidget);
    });

    testWidgets('somebody else\'s report is not hers', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.requester(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12, by: 3)])),
        gate: _gate(),
        userId: 2,
      );
      expect(find.textContaining('Your video report'), findsNothing);
      expect(find.text('Report a problem'), findsOneWidget);
    });
  });

  group('the operator\'s group', () {
    testWidgets('open issues as rows, then Report a problem filed as the '
        'account', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12, by: 3)])),
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
        detail: {
          ..._issue(12, by: 3),
          'comments': [
            {'id': 1, 'message': 'It plays a different movie.'},
            {'id': 2, 'message': 'Which copy?'},
          ],
        },
      );
      await tester.pump();
      expect(find.text('Reported problems'), findsOneWidget);
      expect(find.text('1 open'), findsOneWidget);
      expect(find.text('It plays a different movie.'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.textContaining('Video${dotSeparator}Luca'), findsOneWidget);
      expect(find.textContaining('1 reply'), findsOneWidget);
      expect(find.text('Filed in Seerr as Anna'), findsOneWidget);
    });

    testWidgets('dimmed: the operator\'s own sentence is the toast and the '
        'hint', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info()),
        gate: _gate(
          may: false,
          audience: Audience.operator,
          server: 'Casa Requests',
        ),
        audience: Audience.operator,
      );
      const reason = "Your account on Casa Requests can't report problems.";
      expect(
        tester
            .getSemantics(find.byType(PressableScale))
            .getSemanticsData()
            .hint,
        reason,
      );
      expect(find.text('Filed on Casa Requests as Anna'), findsOneWidget);
      await tester.tap(find.text('Report a problem'));
      await tester.pump();
      expect(find.text(reason), findsOneWidget);
      expect(
        find.text("You can't report problems on this server."),
        findsNothing,
      );
    });

    testWidgets('while the issue is read a skeleton stands for its words; '
        'a failed read says the type\'s own', (tester) async {
      final rows = _rows(_anna, mediaInfo: _info(issues: [_issue(12, by: 3)]));
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: rows,
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
        hangRead: true,
      );
      expect(find.byType(ShimmerPlaceholder), findsOneWidget);
      expect(find.text('Video problem'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: rows,
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
        failRead: true,
      );
      await tester.pump();
      expect(find.byType(ShimmerPlaceholder), findsNothing);
      expect(find.text('Video problem'), findsOneWidget);
    });

    testWidgets('an issue\'s words stop at three lines, the rows around them '
        'wrap whole', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: _rows(_anna, mediaInfo: _info(issues: [_issue(12, by: 3)])),
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
        detail: {
          ..._issue(12, by: 3),
          'comments': [
            {'id': 1, 'message': List.filled(60, 'long words').join(' ')},
          ],
        },
      );
      await tester.pump();
      final texts = tester.widgetList<Text>(find.byType(Text));
      final words = texts.firstWhere((t) => t.data!.startsWith('long words'));
      expect(words.maxLines, 3);
      expect(words.overflow, TextOverflow.ellipsis);
      final action = texts.firstWhere((t) => t.data == 'Report a problem');
      expect(action.maxLines, isNull);
      expect(action.overflow, isNull);
    });

    testWidgets('nothing open: just the row, no heading; the key has no '
        'name', (tester) async {
      await _pump(
        tester,
        const MediaReportSection.operator(scope: (key: _movie, focus: null)),
        rows: _rows(_key, mediaInfo: _info(issues: [_issue(12, status: 2)])),
        gate: _gate(audience: Audience.operator),
        audience: Audience.operator,
      );
      expect(find.text('Reported problems'), findsNothing);
      expect(find.text('Filed in Seerr'), findsOneWidget);
    });
  });

  group('the sheet', () {
    testWidgets('a movie: four types, nothing preselected, no Where', (
      tester,
    ) async {
      await _openSheet(tester, seerr: _anna);
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Nosferatu'), findsOneWidget);
      for (final type in ['Video', 'Audio', 'Subtitles', 'Other']) {
        expect(find.text(type), findsOneWidget);
      }
      expect(
        find.text('Wrong movie, poor quality, or the picture breaks up'),
        findsOneWidget,
      );
      expect(find.text('Where'), findsNothing);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((s) => s.properties.checked == true),
        isEmpty,
      );
    });

    testWidgets('missing type and words are said, and nothing is sent', (
      tester,
    ) async {
      final client = _Client();
      await _openSheet(tester, seerr: _anna, client: client);
      await _submit(tester);
      expect(find.text("Choose what's wrong."), findsOneWidget);
      expect(find.text('Say what happens.'), findsOneWidget);
      expect(client.posts, isEmpty);
    });

    testWidgets('sends exactly the movie draft: type, trimmed words, media '
        'id, no season, no user', (tester) async {
      final client = _Client();
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      expect(client.posts, [
        {'issueType': 1, 'message': 'It plays Sintel.', 'mediaId': 81},
      ]);
    });

    testWidgets('a series from an episode sends its season and episode', (
      tester,
    ) async {
      final client = _Client();
      await _openSheet(
        tester,
        seerr: _anna,
        movie: false,
        season: 2,
        episode: 3,
        client: client,
      );
      expect(
        find.text('Cosmos Laundromat${dotSeparator}S2${episodeCodeSpace}E3'),
        findsOneWidget,
      );
      expect(
        find.text('Wrong episode, poor quality, or the picture breaks up'),
        findsOneWidget,
      );
      await _fill(tester, type: 'Audio', text: 'Russian audio');
      await _submit(tester);
      expect(client.posts, [
        {
          'issueType': 2,
          'message': 'Russian audio',
          'mediaId': 90,
          'problemSeason': 2,
          'problemEpisode': 3,
        },
      ]);
    });

    testWidgets('from the page: All seasons, All episodes, and the Season '
        'menu never offers Specials or a season off the server', (
      tester,
    ) async {
      final client = _Client();
      await _openSheet(tester, seerr: _anna, movie: false, client: client);
      expect(find.text('All seasons'), findsOneWidget);
      // The Episode row waits for a season.
      expect(find.text('Episode'), findsNothing);
      await tester.tap(find.text('All seasons'));
      await tester.pumpAndSettle();
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('Season 3'), findsNothing);
      expect(find.textContaining('Special'), findsNothing);
      expect(find.text('Season 0'), findsNothing);
      await tester.tap(find.text('Season 2').last);
      await tester.pumpAndSettle();
      expect(find.text('Episode'), findsOneWidget);
      expect(find.text('All episodes'), findsOneWidget);
      await _fill(tester);
      await _submit(tester);
      expect(client.posts.single, containsPair('problemSeason', 2));
      expect(client.posts.single, containsPair('problemEpisode', 0));
    });

    testWidgets('one season on the server is preselected', (tester) async {
      final info = {
        'id': 90,
        'status': 5,
        'issues': <Object>[],
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
        ],
      };
      final rows = _rows(_anna, mediaInfo: info, movie: false);
      await _pump(
        tester,
        ReportProblemSheet(
          scope: (key: _tv, focus: null),
          source: _source(rows, movie: false),
        ),
        rows: rows,
        gate: _gate(),
      );
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Cosmos Laundromat${dotSeparator}S1'), findsOneWidget);
    });

    testWidgets('sending: the button busy, one tap only, the sheet stays', (
      tester,
    ) async {
      final client = _Client(hang: true);
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      expect(find.text('Submitting'), findsOneWidget);
      await tester.tap(find.text('Submitting'));
      await tester.pump();
      expect(client.posts, hasLength(1));
      final pop = tester.widget<PopScope>(find.byType(PopScope).first);
      expect(pop.canPop, isFalse);
    });

    testWidgets('the requester reads one line and Retry, her words stay', (
      tester,
    ) async {
      await _openSheet(
        tester,
        seerr: _anna,
        client: _Client(error: _failed(type: DioExceptionType.connectionError)),
      );
      await _fill(tester);
      await _submit(tester);
      expect(find.text("Can't reach the server."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Your report is still here.'), findsOneWidget);
      expect(find.textContaining('Seerr'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  It plays Sintel.  ',
      );
      expect(find.text('Submit report'), findsOneWidget);
    });

    /// What the server holds after Anna's report went in and its answer was
    /// lost: her issue 77, on media 81, a video problem, with her words.
    Map<String, dynamic> filed({
      String words = 'It plays Sintel.',
      int by = 2,
    }) => {
      ..._issue(77, by: by),
      'media': {'id': 81, 'mediaType': 'movie', 'tmdbId': 653},
      'comments': [
        {'id': 5, 'message': words},
      ],
    };

    testWidgets('a timeout after the send finds the report on the server and '
        'counts as filed: no Retry, no second report', (tester) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.receiveTimeout),
        held: [filed()],
      );
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      await tester.pump();

      expect(client.reads, 1);
      expect(client.posts, hasLength(1));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Your report is still here.'), findsNothing);
    });

    testWidgets('a list that sends the row without its replies is read issue '
        'by issue: the report is found, not sent again', (tester) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.receiveTimeout),
        held: [
          {...filed(), 'comments': <Object>[]},
        ],
        whole: {77: filed()},
      );
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      await tester.pump();

      expect(client.posts, hasLength(1));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Your report is still here.'), findsNothing);
    });

    testWidgets('a timeout with nothing of hers on the server offers Retry as '
        'before', (tester) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.receiveTimeout),
        held: [
          filed(words: 'Another thing'),
          filed(by: 3),
        ],
      );
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      await tester.pump();

      expect(client.reads, 1);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Your report is still here.'), findsOneWidget);
    });

    testWidgets('a report she had already made, same words, is not taken for '
        'the new one', (tester) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.receiveTimeout),
        held: [filed()],
      );
      final rows = _rows(_anna, mediaInfo: _info(issues: [_issue(77)]));
      await _pump(
        tester,
        ReportProblemSheet(
          scope: (key: _movie, focus: null),
          source: _source(rows),
          season: 0,
          episode: 0,
        ),
        rows: rows,
        gate: _gate(),
        client: client,
        userId: 2,
      );
      await _fill(tester);
      await _submit(tester);
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a timeout whose read-back fails too does not say nothing was '
        'sent, and keeps Retry', (tester) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.receiveTimeout),
        readError: _failed(type: DioExceptionType.connectionError),
      );
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);
      await tester.pump();

      expect(
        find.text('Your report is still here. We can’t tell if it arrived.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a refusal that certainly never arrived is not read back', (
      tester,
    ) async {
      final client = _Client(
        error: _failed(type: DioExceptionType.connectionError),
      );
      await _openSheet(tester, seerr: _anna, client: client);
      await _fill(tester);
      await _submit(tester);

      expect(client.reads, 0);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('the operator\'s caption is where it is filed', (tester) async {
      await _openSheet(
        tester,
        seerr: _anna,
        audience: Audience.operator,
        gate: _gate(audience: Audience.operator, server: 'Casa Requests'),
      );
      expect(find.text('Filed on Casa Requests as Anna.'), findsOneWidget);
      expect(find.textContaining('Whoever runs'), findsNothing);
    });

    testWidgets('the operator reads the full sentence', (tester) async {
      await _openSheet(
        tester,
        seerr: _key,
        audience: Audience.operator,
        client: _Client(error: _failed(type: DioExceptionType.connectionError)),
      );
      await _fill(tester);
      await _submit(tester);
      expect(find.text('Seerr did not answer.'), findsOneWidget);
      expect(find.text('Your report is still here.'), findsOneWidget);
    });

    testWidgets('signed out: Sign in again leads, the draft stays', (
      tester,
    ) async {
      await _openSheet(
        tester,
        seerr: _anna,
        client: _Client(
          error: _failed(status: 403, cause: const SeerrSessionEnded()),
        ),
      );
      await _fill(tester);
      await _submit(tester);
      expect(find.text('You were signed out'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Submit report'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('refused: amber, no Retry, Submit dims and says why', (
      tester,
    ) async {
      await _openSheet(
        tester,
        seerr: _anna,
        client: _Client(
          error: _failed(
            status: 403,
            cause: const SeerrRefused(SeerrRefusal.permissionDenied),
          ),
        ),
      );
      await _fill(tester);
      await _submit(tester);
      const reason = "You can't report problems on this server.";
      expect(find.text(reason), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pump();
      // The toast says it again, and nothing more was sent.
      expect(find.text(reason), findsNWidgets(2));
    });

    testWidgets('the title is gone: neutral, Close', (tester) async {
      await _openSheet(
        tester,
        seerr: _anna,
        client: _Client(
          error: _failed(
            status: 404,
            body: const {'message': 'Media does not exist.'},
          ),
        ),
      );
      await _fill(tester);
      await _submit(tester);
      expect(
        find.text('This title is no longer on the server.'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Submit report'), findsNothing);
    });
  });

  group('the episode sheet\'s row', () {
    testWidgets('a season on the server: opens the sheet on that episode', (
      tester,
    ) async {
      final rows = _rows(_anna, mediaInfo: _seriesInfo(), movie: false);
      await _pump(
        tester,
        const MediaEpisodeReportRow(
          scope: (key: _tv, focus: null),
          season: 2,
          number: 3,
        ),
        rows: rows,
        gate: _gate(),
      );
      expect(find.text('Report a problem with this episode'), findsOneWidget);
      await tester.tap(find.text('Report a problem with this episode'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cosmos Laundromat${dotSeparator}S2${episodeCodeSpace}E3'),
        findsOneWidget,
      );
    });

    testWidgets('Specials, a season off the server, or no Seerr: no row', (
      tester,
    ) async {
      final rows = _rows(_anna, mediaInfo: _seriesInfo(), movie: false);
      for (final season in [0, 3, 7]) {
        await _pump(
          tester,
          MediaEpisodeReportRow(
            scope: (key: _tv, focus: null),
            season: season,
            number: 1,
          ),
          rows: rows,
          gate: _gate(),
        );
        expect(find.textContaining('Report a problem'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('dimmed like the title\'s own row', (tester) async {
      final rows = _rows(_anna, mediaInfo: _seriesInfo(), movie: false);
      await _pump(
        tester,
        const MediaEpisodeReportRow(
          scope: (key: _tv, focus: null),
          season: 1,
          number: 1,
        ),
        rows: rows,
        gate: _gate(may: false),
      );
      await tester.tap(find.text('Report a problem with this episode'));
      await tester.pump();
      expect(
        find.text("You can't report problems on this server."),
        findsOneWidget,
      );
    });
  });
}
