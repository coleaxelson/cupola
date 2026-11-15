@Tags(['catalog'])
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/media_report_row.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/media/presentation/report_problem_sheet.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

const _movie = MediaKey.movie(653);
const _series = MediaKey.tv(358332);

final _at = DateTime(2026, 10, 3, 20, 41);

/// Anna's account on the household's Seerr, user 2, and the operator's own.
final _anna = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'https://nas.home.arpa:5055',
  account: const SeerrAccountSignIn(
    kind: SeerrAccountKind.local,
    userId: 2,
    displayName: 'Anna',
    session: 'catalog',
  ),
);
final _matt = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'https://nas.home.arpa:5055',
  account: const SeerrAccountSignIn(
    kind: SeerrAccountKind.local,
    userId: 1,
    displayName: 'Matt',
    session: 'catalog',
  ),
);
final _key = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'https://nas.home.arpa:5055',
  credential: 'catalog',
);

RoleGate _annaMayReport() => RoleGate(
  audience: Audience.requester,
  grant: SeerrGrant.account(
    permissions:
        SeerrPermission.request.value | SeerrPermission.createIssues.value,
  ),
);

RoleGate _annaMayNot() => RoleGate(
  audience: Audience.requester,
  grant: SeerrGrant.account(permissions: SeerrPermission.request.value),
);

RoleGate _operator() =>
    const RoleGate(audience: Audience.operator, grant: SeerrGrant.apiKey());

/// Matt's account on somebody else's Seerr, titled `Casa Requests`, which may
/// not report.
RoleGate _mattMayNot() => RoleGate(
  audience: Audience.operator,
  grant: SeerrGrant.account(permissions: SeerrPermission.request.value),
  server: SeerrServerFacts.fromPublicSettings({
    'initialized': true,
    'applicationTitle': 'Casa Requests',
  }),
);

Map<String, dynamic> _issue(
  int id, {
  int status = 1,
  int by = 2,
  String name = 'Anna',
  DateTime? at,
  int type = 1,
}) {
  final when = (at ?? DateTime(2026, 9, 26, 21, 40)).toUtc().toIso8601String();
  return {
    'id': id,
    'issueType': type,
    'status': status,
    'createdAt': when,
    'updatedAt': when,
    'createdBy': {'id': by, 'displayName': name},
  };
}

/// Seerr's record of Nosferatu: on the server, with [issues] as `mediaInfo`
/// lists them.
List<MediaRow> _movieRows(
  ServiceInstance seerr, {
  List<Map<String, dynamic>> issues = const [],
  int status = 5,
}) => [
  MediaConnectionRow<MediaSeerrRecord>(
    seerr,
    MediaReadingAnswered(
      MediaAnswer(
        MediaSeerrRecord(
          details: {
            'id': 653,
            'title': 'Nosferatu',
            'releaseDate': '1922-02-16',
            'mediaInfo': {'id': 81, 'status': status, 'issues': issues},
          },
        ),
        _at,
      ),
    ),
  ),
];

/// Seerr's record of Cosmos Laundromat: two seasons on the server, the third
/// not there.
List<MediaRow> _seriesRows(ServiceInstance seerr) => [
  MediaConnectionRow<MediaSeerrRecord>(
    seerr,
    MediaReadingAnswered(
      MediaAnswer(
        const MediaSeerrRecord(
          details: {
            'id': 358332,
            'name': 'Cosmos Laundromat',
            'firstAirDate': '2015-08-10',
            'seasons': [
              {'seasonNumber': 0, 'episodeCount': 2},
              {'seasonNumber': 1, 'episodeCount': 10},
              {'seasonNumber': 2, 'episodeCount': 10},
              {'seasonNumber': 3, 'episodeCount': 8},
            ],
            'mediaInfo': {
              'id': 90,
              'status': 4,
              'issues': [],
              'seasons': [
                {'seasonNumber': 1, 'status': 5},
                {'seasonNumber': 2, 'status': 5},
                {'seasonNumber': 3, 'status': 1},
              ],
            },
          },
        ),
        _at,
      ),
    ),
  ),
];

/// A Seerr that never answers a report, or answers it with [error].
class _Reports extends FakeApiClient {
  _Reports(this.error);

  /// Null: the request is still out.
  final Object? error;

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) {
    final error = this.error;
    if (error == null) return Completer<Response<dynamic>>().future;
    return Future.error(error);
  }
}

DioException _failure({
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

List<Override> _world({
  required List<MediaRow> rows,
  required RoleGate gate,
  required Audience audience,
  Object? error,
  int? userId,
  SeerrIssue Function(int id)? issue,
  bool hangIssue = false,
  MediaKey key = _movie,
}) => [
  // Seerr has been silent since 20:41, as the app saw it.
  silenceClockProvider.overrideWithValue(
    SilenceClock()..noteSilent(silenceKey(ServiceKey.seerr, 'seerr'), _at),
  ),
  instanceSummaryProvider.overrideWith(
    (ref, key) async => ServiceSummary(
      service: key.service,
      status: ServiceSummaryStatus.offline,
      host: 'nas.home.arpa',
      version: null,
    ),
  ),
  mediaRowsProvider.overrideWith((ref, k) => rows),
  audienceProvider.overrideWithValue(audience),
  roleGateProvider.overrideWith((ref, id) => gate),
  seerrAccountUserIdProvider.overrideWith((ref, id) => userId),
  mediaReportIssueProvider.overrideWith(
    (ref, source) => hangIssue
        ? Completer<SeerrIssue>().future
        : Future.value((issue ?? _detail)(source.issueId)),
  ),
  seerrServiceForProvider.overrideWith(
    (ref, id) => SeerrService(_Reports(error), numbering: SeerrNumbering.seerr),
  ),
  mediaSeasonFactsProvider.overrideWith(
    (ref, source) async => [
      for (var n = 1; n <= 10; n++)
        MediaEpisodeFacts(
          season: source.season,
          number: n,
          name: switch (n) {
            1 => 'The Laundry',
            2 => 'Victor',
            3 => 'The Second Cycle',
            4 => 'Tachyon',
            5 => 'Every Life',
            _ => 'Episode $n',
          },
        ),
    ],
  ),
];

SeerrIssue _detail(
  int id, {
  String reply = 'Which copy, the 4K or the normal one?',
  String message = 'It plays a different movie: the file is Sintel.',
  String by = 'Anna',
  int byId = 2,
  List<(String, int, String)> replies = const [('Matt', 1, 'Which copy?')],
}) => SeerrIssue.fromJson({
  ..._issue(id, by: byId, name: by),
  'comments': [
    {
      'id': 1,
      'message': message,
      'user': {'id': byId, 'displayName': by},
    },
    for (final (i, (name, userId, text)) in replies.indexed)
      {
        'id': 2 + i,
        'message': text,
        'user': {'id': userId, 'displayName': name},
      },
  ],
});

/// The page's own room under a section, as a list gives it room: a group is
/// as tall as its rows, never as tall as the room. The room is a Scaffold, so
/// a toast has somewhere to land.
Widget _room(Widget child) => ScaffoldMessenger(
  // Its own messenger: a toast raised in one scene is never drawn in another.
  child: MediaRoom(
    light: null,
    child: ListView(padding: const EdgeInsets.all(16), children: [child]),
  ),
);

/// A toast as the page raises it, kept up for the sheet: the catalog draws
/// the scene after the four seconds a real one lasts.
Future<void> _toast(WidgetTester tester, Finder scene, String text) async {
  // The scene's own messenger, inside the scene.
  ScaffoldMessenger.of(
    tester.element(
      find.descendant(of: scene, matching: find.byType(ListView)).first,
    ),
  ).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(days: 1)),
  );
  await tester.pump();
}

CatalogScene _section(
  String caption,
  Widget section, {
  required List<Override> overrides,
  double height = 190,
  double textScale = 1,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) => CatalogScene(
  caption,
  (_) => _room(section),
  width: 390,
  height: height,
  textScale: textScale,
  overrides: overrides,
  act: act,
);

/// The sheet as it stands open over the page: the panel drawn in place.
Widget _sheet(
  MediaReportSource source, {
  MediaKey key = _movie,
  int season = 0,
  int episode = 0,
}) => Builder(
  builder: (context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Theme.of(context).colorScheme.surface),
      const ColoredBox(color: Colors.black54),
      Align(
        alignment: Alignment.bottomCenter,
        child: ReportProblemSheet(
          scope: (key: key, focus: null),
          source: source,
          season: season,
          episode: episode,
        ),
      ),
    ],
  ),
);

MediaReportSource _source(ServiceInstance seerr, {MediaKey key = _movie}) =>
    mediaReportSourceOf(
      key.isMovie ? _movieRows(seerr) : _seriesRows(seerr),
      movie: key.isMovie,
    )!;

Future<void> _fill(
  WidgetTester tester,
  Finder scene, {
  String type = 'Video',
  String text = 'It plays a different movie: Sintel, not Nosferatu.',
}) async {
  await tester.tap(find.descendant(of: scene, matching: find.text(type)));
  await tester.enterText(
    find.descendant(of: scene, matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

Future<void> _submit(WidgetTester tester, Finder scene) async {
  await tester.tap(
    find.descendant(of: scene, matching: find.text('Submit report')),
  );
  await tester.pump();
}

CatalogScene _sheetScene(
  String caption, {
  required ServiceInstance seerr,
  required RoleGate gate,
  required Audience audience,
  Object? error,
  MediaKey key = _movie,
  int season = 0,
  int episode = 0,
  double height = 900,
  double textScale = 1,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) => CatalogScene(
  caption,
  (_) => _sheet(
    _source(seerr, key: key),
    key: key,
    season: season,
    episode: episode,
  ),
  width: 390,
  height: height,
  textScale: textScale,
  act: act,
  overrides: _world(
    rows: const [],
    gate: gate,
    audience: audience,
    error: error,
    key: key,
  ),
);

/// A failed send, acted: the words are in, Submit is pressed, Seerr answers
/// with [error].
CatalogScene _failedScene(
  String caption, {
  required ServiceInstance seerr,
  required RoleGate gate,
  required Audience audience,
  required Object error,
  double height = 860,
}) => _sheetScene(
  caption,
  seerr: seerr,
  gate: gate,
  audience: audience,
  error: error,
  height: height,
  act: (tester, scene) async {
    await _fill(tester, scene);
    await _submit(tester, scene);
  },
);

void main() {
  catalogCard(
    'MediaReport',
    overrides: () => settingsScopeOverrides(configured: [ServiceKey.seerr]),
    scenes: [
      _section(
        'Requester · her account may not report (no Create issues): the row '
        'is dimmed and still a target, and a tap says why',
        MediaReportSection.requester(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_anna),
          gate: _annaMayNot(),
          audience: Audience.requester,
          userId: 2,
        ),
        height: 260,
        act: (tester, scene) async =>
            _toast(tester, scene, "You can't report problems on this server."),
      ),
      _section(
        "Operator · Matt's account on a Seerr that may not report: dimmed, "
        'the server named by its own title',
        MediaReportSection.operator(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_matt),
          gate: _mattMayNot(),
          audience: Audience.operator,
          userId: 1,
        ),
        height: 260,
        act: (tester, scene) async => _toast(
          tester,
          scene,
          "Your account on Casa Requests can't report problems.",
        ),
      ),
      _section(
        'Requester · her report is open: blue, it waits on someone else; the '
        'date and the replies, then the way to report another',
        MediaReportSection.requester(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_anna, issues: [_issue(12)]),
          gate: _annaMayReport(),
          audience: Audience.requester,
          userId: 2,
          issue: _detail,
        ),
      ),
      _section(
        'Requester · her report was resolved: green and quiet, and she can '
        'report again',
        MediaReportSection.requester(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_anna, issues: [_issue(12, status: 2)]),
          gate: _annaMayReport(),
          audience: Audience.requester,
          userId: 2,
        ),
      ),
      _section(
        'Operator · one problem open: its words, who and when, the replies; '
        'then the way to report one',
        MediaReportSection.operator(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(
            _matt,
            issues: [
              _issue(
                12,
                by: 3,
                name: 'Luca',
                at: DateTime.now().subtract(const Duration(days: 1)),
              ),
            ],
          ),
          gate: _operator(),
          audience: Audience.operator,
          userId: 1,
          issue: (id) => _detail(
            id,
            by: 'Luca',
            byId: 3,
            replies: const [
              ('Matt', 1, 'Which copy, the 4K or the normal one?'),
              ('Luca', 3, 'The normal one, on the living room TV.'),
            ],
          ),
        ),
        height: 300,
      ),
      _section(
        "Operator · the issue's words still being read: a skeleton line in "
        "the title's place",
        MediaReportSection.operator(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_matt, issues: [_issue(12, by: 3, name: 'Luca')]),
          gate: _operator(),
          audience: Audience.operator,
          userId: 1,
          hangIssue: true,
        ),
        height: 300,
      ),
      _section(
        'Operator · nothing open: the way to report, and no heading',
        MediaReportSection.operator(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_key),
          gate: _operator(),
          audience: Audience.operator,
        ),
        height: 190,
      ),
      _section(
        'Reported · the toast, and the row says so',
        MediaReportSection.requester(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_anna, issues: [_issue(12, at: DateTime.now())]),
          gate: _annaMayReport(),
          audience: Audience.requester,
          userId: 2,
          issue: (id) => _detail(id, replies: const []),
        ),
        height: 300,
        act: (tester, scene) async => _toast(tester, scene, 'Problem reported'),
      ),
      _section(
        'At twice the reading size',
        MediaReportSection.requester(scope: (key: _movie, focus: null)),
        overrides: _world(
          rows: _movieRows(_anna, issues: [_issue(12)]),
          gate: _annaMayReport(),
          audience: Audience.requester,
          userId: 2,
          issue: _detail,
        ),
        height: 460,
        textScale: catalogTextScale,
      ),
      _sheetScene(
        'Sheet · a movie: Video chosen and the words written, under the four '
        'types with their hints',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        act: (tester, scene) async => _fill(tester, scene),
      ),
      _sheetScene(
        'Sheet · Matt: under the words, the line says where it is filed',
        seerr: _matt,
        gate: _operator(),
        audience: Audience.operator,
        height: 880,
      ),
      _sheetScene(
        'Sheet · a series from an episode: Season and Episode filled in, '
        'the title says S2 E3',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        key: _series,
        season: 2,
        episode: 3,
        act: (tester, scene) async => _fill(
          tester,
          scene,
          type: 'Audio',
          text: 'The audio is in Russian, the subtitles say English.',
        ),
      ),
      _sheetScene(
        'Sheet · a series from its page: All seasons, All episodes; the '
        'Episode row waits for a season',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        key: _series,
        height: 820,
      ),
      _sheetScene(
        'Sheet · submitted with nothing chosen: both fields say what is '
        'missing',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        height: 880,
        act: (tester, scene) async => _submit(tester, scene),
      ),
      _sheetScene(
        'Sheet · sending: the button busy, one tap only, the sheet stays',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        act: (tester, scene) async {
          await _fill(tester, scene);
          await _submit(tester, scene);
        },
      ),
      _failedScene(
        "Sheet · Anna, the server did not answer: one line, Retry, and her "
        'words stay',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        error: _failure(type: DioExceptionType.connectionError),
      ),
      _failedScene(
        'Sheet · Matt, Seerr did not answer: the full sentence, Retry',
        seerr: _matt,
        gate: _operator(),
        audience: Audience.operator,
        error: _failure(type: DioExceptionType.connectionError),
      ),
      _failedScene(
        'Sheet · signed out: blue, and Sign in again leads',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        error: _failure(status: 403, cause: const SeerrSessionEnded()),
      ),
      _failedScene(
        "Sheet · the server refused: amber, no Retry, Submit dims",
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        error: _failure(
          status: 403,
          cause: const SeerrRefused(SeerrRefusal.permissionDenied),
        ),
      ),
      _failedScene(
        'Sheet · Seerr no longer has the title: neutral, Close',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        error: _failure(
          status: 404,
          body: const {'message': 'Media does not exist.'},
        ),
      ),
      _sheetScene(
        'Sheet · at twice the reading size',
        seerr: _anna,
        gate: _annaMayReport(),
        audience: Audience.requester,
        height: 1700,
        textScale: catalogTextScale,
        act: (tester, scene) async => _submit(tester, scene),
      ),
    ],
  );
}
