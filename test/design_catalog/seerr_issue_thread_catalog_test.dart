@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/issue_files_provider.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/seerr_issue_thread_screen.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// The artwork's light, as the app reads it.
TitleLight? _light;

Future<void> _readLight() async {
  final bytes = io.File(
    'design/system/assets/Imagery/poster.jpg',
  ).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: titleLightDecodeSize,
    targetHeight: titleLightDecodeSize,
  );
  final rgba = (await (await codec.getNextFrame()).image.toByteData())!;
  _light = await titleLightFromPixels([
    for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
      0xFF000000 |
          rgba.getUint8(i) << 16 |
          rgba.getUint8(i + 1) << 8 |
          rgba.getUint8(i + 2),
  ]);
}

DateTime get _yesterday {
  final now = catalogNow;
  return DateTime(now.year, now.month, now.day - 1, 21, 40);
}

DateTime get _morning {
  final now = catalogNow;
  return DateTime(now.year, now.month, now.day, 8, 12);
}

String _iso(DateTime at) => at.toUtc().toIso8601String();

Map<String, dynamic> _comment(
  int id,
  String message, {
  required int by,
  required String name,
  DateTime? at,
}) => {
  'id': id,
  'message': message,
  'createdAt': _iso(at ?? _yesterday),
  'updatedAt': _iso(at ?? _yesterday),
  'user': {'id': by, 'displayName': name},
};

/// Tears of Steel, reported by Luca (user 5), answered by Matt (user 1).
Map<String, dynamic> _operatorIssue({
  int status = 1,
  Map<String, dynamic>? modifiedBy,
}) => {
  'id': 12,
  'issueType': 1,
  'status': status,
  'createdAt': _iso(_yesterday),
  'updatedAt': _iso(_yesterday),
  'media': {'id': 81, 'mediaType': 'movie', 'tmdbId': 603, 'status': 5},
  'createdBy': {'id': 5, 'displayName': 'Luca'},
  'modifiedBy': modifiedBy,
  'comments': [
    _comment(
      1,
      'It plays a different movie: the file is Sintel.',
      by: 5,
      name: 'Luca',
    ),
    _comment(
      2,
      'Which copy, the 4K or the normal one?',
      by: 1,
      name: 'Matt',
      at: _yesterday.add(const Duration(minutes: 25)),
    ),
    _comment(
      3,
      'The normal one, on the living room TV.',
      by: 5,
      name: 'Luca',
      at: _morning,
    ),
  ],
};

/// Cosmos Laundromat S2 E3, reported by Luca.
Map<String, dynamic> _episodeIssue() => {
  ..._operatorIssue(),
  'issueType': 2,
  'problemSeason': 2,
  'problemEpisode': 3,
  'media': {'id': 90, 'mediaType': 'tv', 'tmdbId': 358332, 'status': 5},
  'comments': [
    _comment(
      1,
      'The audio is in Russian, the subtitles say English.',
      by: 5,
      name: 'Luca',
    ),
  ],
};

/// Cosmos Laundromat S2 E3, reported by Anna (user 2), answered by Matt.
Map<String, dynamic> _requesterIssue({
  int status = 1,
  bool replied = true,
  Map<String, dynamic>? modifiedBy,
}) => {
  ..._episodeIssue(),
  'status': status,
  'createdBy': {'id': 2, 'displayName': 'Anna'},
  'modifiedBy': modifiedBy,
  'comments': [
    _comment(
      1,
      'The audio is in Russian, the subtitles say English.',
      by: 2,
      name: 'Anna',
      at: _yesterday.subtract(const Duration(days: 1)),
    ),
    if (replied) ...[
      _comment(
        2,
        'Is it every episode, or only this one?',
        by: 1,
        name: 'Matt',
        at: _yesterday.subtract(const Duration(days: 1, hours: -1)),
      ),
      _comment(
        3,
        'Only this one. The others are fine.',
        by: 2,
        name: 'Anna',
        at: _yesterday,
      ),
    ],
  ],
};

/// A Seerr that holds one issue and the pages of the titles it hydrates from.
class _Seerr extends FakeApiClient {
  _Seerr(this.issue, {this.failRead, this.failWrite});

  final Map<String, dynamic> issue;
  final Object? failRead;
  final Object? failWrite;

  Response<dynamic> _ok(String path, Object? data) => Response(
    requestOptions: RequestOptions(path: path),
    data: data,
  );

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (path == '/api/v1/issue/12') {
      if (failRead != null) throw failRead!;
      return _ok(path, issue);
    }
    if (path == '/api/v1/movie/603') {
      return _ok(path, {
        'title': 'Tears of Steel',
        'releaseDate': '2012-09-26',
        'posterPath': CatalogArt.tmdbPoster,
      });
    }
    if (path == '/api/v1/tv/358332') {
      return _ok(path, {
        'name': 'Cosmos Laundromat',
        'firstAirDate': '2015-08-10',
        'posterPath': CatalogArt.tmdbPoster,
      });
    }
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.receiveTimeout,
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    if (failWrite != null) throw failWrite!;
    return _ok(path, null);
  }
}

DioException get _timeout => DioException(
  requestOptions: RequestOptions(path: '/api/v1/issue/12/comment'),
  type: DioExceptionType.receiveTimeout,
);

DioException get _deleted => DioException(
  requestOptions: RequestOptions(path: '/api/v1/issue/12', method: 'GET'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/api/v1/issue/12'),
    statusCode: 500,
    data: {'message': 'Issue not found.'},
  ),
);

/// Matt's account on this Seerr, with MANAGE_ISSUES: user 1.
RoleGate _manager() => RoleGate(
  audience: Audience.operator,
  grant: SeerrGrant.account(permissions: SeerrPermission.manageIssues.value),
);

/// Matt's account on somebody else's Seerr, with no issue permission.
RoleGate _cannotManage() => RoleGate(
  audience: Audience.operator,
  grant: SeerrGrant.account(permissions: SeerrPermission.request.value),
  server: SeerrServerFacts.fromPublicSettings({
    'initialized': true,
    'applicationTitle': 'Casa Requests',
  }),
);

/// Anna (user 2), who may report.
RoleGate _requester({bool may = true}) => RoleGate(
  audience: Audience.requester,
  grant: SeerrGrant.account(
    permissions:
        SeerrPermission.request.value |
        (may ? SeerrPermission.createIssues.value : 0),
  ),
);

/// The two copies of Tears of Steel the arrs hold.
List<IssueFile> get _movieFiles => [
  IssueFile(
    connectionId: 'radarr-4k',
    connectionName: 'Radarr${dotSeparator}4K',
    quality: 'Remux-2160p',
    size: 9800000000,
    fileName: 'Tears of Steel (2012) Remux-2160p.mkv',
    importedAt: _yesterday,
    target: const ReleaseSearchTarget.movie(
      movieId: 9,
      label: 'Tears of Steel',
    ).stampedWith('radarr-4k'),
  ),
  IssueFile(
    connectionId: 'radarr',
    connectionName: 'Radarr',
    quality: 'Bluray-1080p',
    size: 1200000000,
    fileName: 'Sintel (2010) Bluray-1080p.mkv',
    importedAt: catalogNow.subtract(const Duration(days: 20)),
    target: const ReleaseSearchTarget.movie(
      movieId: 3,
      label: 'Tears of Steel',
    ).stampedWith('radarr'),
  ),
];

/// The file of the episode.
List<IssueFile> get _episodeFiles => [
  IssueFile(
    connectionId: 'sonarr',
    connectionName: 'Sonarr',
    quality: 'WEBDL-720p',
    size: 820000000,
    fileName: 'Cosmos.Laundromat.S02E03.The.Second.Cycle.720p.WEB.mkv',
    importedAt: _yesterday.subtract(const Duration(days: 3)),
    episode: true,
    target: const ReleaseSearchTarget.episode(
      episodeId: 31,
      seriesId: 5,
      seasonNumber: 2,
      label: 'Cosmos Laundromat',
    ).stampedWith('sonarr'),
  ),
];

List<Override> _world(
  _Seerr client, {
  required RoleGate gate,
  Audience audience = Audience.operator,
  int userId = 1,
  List<IssueFile> files = const [],
}) => [
  audienceProvider.overrideWithValue(audience),
  roleGateProvider.overrideWith((ref, id) => gate),
  seerrAccountUserIdProvider.overrideWith((ref, id) => userId),
  seerrServiceForProvider.overrideWith(
    (ref, id) => SeerrService(client, numbering: SeerrNumbering.seerr),
  ),
  titleLightProvider.overrideWith((ref, url) async => _light),
  issueFilesProvider.overrideWith((ref, scope) => files),
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
            _ => 'Episode $n',
          },
        ),
    ],
  ),
];

/// The page on a navigator of the scene's own, so what it opens (a menu, a
/// dialog) is drawn inside the scene and not over the sheet, and with a
/// messenger of its own, so a toast raised in one scene is never drawn in
/// another.
Widget _page({Future<void> Function(BuildContext context)? over}) =>
    ScaffoldMessenger(
      child: ClipRect(
        child: Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => _Over(open: over, child: const _Thread()),
          ),
        ),
      ),
    );

class _Thread extends StatelessWidget {
  const _Thread();

  @override
  Widget build(BuildContext context) =>
      const SeerrIssueThreadScreen(issueId: 12, connectionId: 'seerr');
}

/// Opens what [open] opens once the page is up, over it: the dialog a button
/// raises, drawn as the AppDialog card draws one.
class _Over extends StatefulWidget {
  const _Over({required this.child, this.open});

  final Widget child;
  final Future<void> Function(BuildContext context)? open;

  @override
  State<_Over> createState() => _OverState();
}

class _OverState extends State<_Over> {
  @override
  void initState() {
    super.initState();
    final open = widget.open;
    if (open == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) open(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A toast as the page raises it, kept up for the sheet: the catalog draws the
/// scene after the four seconds a real one lasts.
Future<void> _toast(
  WidgetTester tester,
  Finder scene,
  String text, {
  bool failure = false,
}) async {
  final context = tester.element(
    find.descendant(of: scene, matching: find.byType(CustomScrollView)).first,
  );
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  await tester.pump();
  if (failure) {
    SnackBarHelper.error(
      context,
      text,
      cause: _timeout,
      onRetry: () {},
      duration: const Duration(days: 1),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(days: 1)),
    );
  }
  await tester.pump();
}

Finder _in(Finder scene, Finder finder) =>
    find.descendant(of: scene, matching: finder);

CatalogScene _scene(
  String caption, {
  required _Seerr client,
  required RoleGate gate,
  Audience audience = Audience.operator,
  int userId = 1,
  List<IssueFile> files = const [],
  double height = 900,
  double textScale = 1,
  Future<void> Function(BuildContext context)? over,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) => CatalogScene(
  caption,
  (_) => _page(over: over),
  width: 390,
  height: height,
  textScale: textScale,
  act: act,
  overrides: _world(
    client,
    gate: gate,
    audience: audience,
    userId: userId,
    files: files,
  ),
);

Future<void> _openMenu(WidgetTester tester, Finder scene) async {
  await tester.tap(_in(scene, find.byTooltip('Edit or delete your reply')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_readLight);

  catalogCard(
    'SeerrIssueThread',
    overrides: () => settingsScopeOverrides(configured: [ServiceKey.seerr]),
    scenes: [
      // ── the operator ────────────────────────────────────────────────────
      _scene(
        'Operator · an open issue: the report, amber Open, the replies (his '
        'own as You), the composer, the files it could be with the search '
        'for a new release, Resolve, Delete issue and Open in Seerr',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        files: _movieFiles,
        height: 1100,
      ),
      _scene(
        'Operator · an issue about one episode: the card names the episode '
        'and its own file is the one that could be at fault',
        client: _Seerr(_episodeIssue()),
        gate: _manager(),
        files: _episodeFiles,
        height: 1060,
      ),
      _scene(
        'Operator · resolved: green, by whom and when, Reopen in the place of '
        'Resolve, and no files to look at',
        client: _Seerr(
          _operatorIssue(
            status: 2,
            modifiedBy: {'id': 1, 'displayName': 'Matt'},
          ),
        ),
        gate: _manager(),
        files: _movieFiles,
        height: 980,
      ),
      _scene(
        "Operator · his reply's menu: Edit reply and Delete reply, each as the "
        'gate says',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        height: 640,
        act: (tester, scene) => _openMenu(tester, scene),
      ),
      _scene(
        'Operator · editing his reply in place: a field, Cancel and Save',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        height: 640,
        act: (tester, scene) async {
          await _openMenu(tester, scene);
          await tester.tap(_in(scene, find.text('Edit reply')));
          await tester.pumpAndSettle();
          await tester.enterText(
            _in(scene, find.byType(TextField)).first,
            'Which copy, the 4K or the 1080p one?',
          );
          await tester.pump();
        },
      ),
      _scene(
        "Operator · Delete reply asks first: neutral, and says who won't see "
        'it',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        height: 640,
        over: (context) => showDeleteReplyConfirm(
          context,
          who: 'Luca',
          useRootNavigator: false,
        ),
      ),
      _scene(
        'Operator · Delete issue asks first: for the reporter too, and it '
        'cannot be undone',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        height: 640,
        over: (context) => showDeleteIssueConfirm(
          context,
          reporter: 'Luca',
          useRootNavigator: false,
        ),
      ),
      _scene(
        "Operator · Matt's account on a Seerr where it may not manage issues: "
        'Resolve and the composer dimmed and still targets, a tap says why',
        client: _Seerr(_operatorIssue()),
        gate: _cannotManage(),
        height: 900,
        act: (tester, scene) async {
          final reason = _cannotManage().resolveIssueAction(own: false).reason;
          await _toast(tester, scene, reason!);
        },
      ),
      _scene(
        'Operator · a reply that did not send keeps its words in the '
        'composer, and Retry sends the same request again',
        client: _Seerr(_operatorIssue(), failWrite: _timeout),
        gate: _manager(),
        height: 900,
        act: (tester, scene) async {
          await tester.enterText(
            _in(scene, find.byType(TextField)).first,
            'Got it, a new copy is on its way.',
          );
          await tester.tap(_in(scene, find.byIcon(Icons.send_rounded)));
          await tester.pumpAndSettle();
          await _toast(
            tester,
            scene,
            'Could not send the reply. Nothing was sent.',
            failure: true,
          );
        },
      ),
      _scene(
        'Operator · an issue somebody deleted meanwhile: where it went, and '
        'back to the list',
        client: _Seerr(_operatorIssue(), failRead: _deleted),
        gate: _manager(),
        height: 560,
      ),
      // ── the requester ───────────────────────────────────────────────────
      _scene(
        'Requester · her report, answered: blue Reported, her own words as '
        'You, the person who replied by name, Mark as resolved; never a '
        'service name',
        client: _Seerr(_requesterIssue()),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 1040,
      ),
      _scene(
        'Requester · just reported, nobody has replied: Add a detail, and '
        'Delete report while it is still alone',
        client: _Seerr(_requesterIssue(replied: false)),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 900,
      ),
      _scene(
        'Requester · after it was resolved: green, by whom and when, and '
        'Reopen',
        client: _Seerr(
          _requesterIssue(
            status: 2,
            modifiedBy: {'id': 1, 'displayName': 'Matt'},
          ),
        ),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 960,
      ),
      _scene(
        'Requester · Delete report asks first, in no service name',
        client: _Seerr(_requesterIssue(replied: false)),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 700,
        over: (context) =>
            showDeleteReportConfirm(context, useRootNavigator: false),
      ),
      _scene(
        'Requester · her account may no longer report: Mark as resolved and '
        'the composer dimmed, a tap says why',
        client: _Seerr(_requesterIssue()),
        gate: _requester(may: false),
        audience: Audience.requester,
        userId: 2,
        height: 1040,
        act: (tester, scene) async {
          final reason = _requester(
            may: false,
          ).resolveIssueAction(own: true).reason;
          await _toast(tester, scene, reason!);
        },
      ),
      _scene(
        'Requester · a report that was deleted meanwhile, with the way back to her requests',
        client: _Seerr(_requesterIssue(), failRead: _deleted),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 560,
      ),
      // ── twice the reading size ──────────────────────────────────────────
      _scene(
        'Operator · at twice the reading size: every line wraps, nothing is '
        'cut',
        client: _Seerr(_operatorIssue()),
        gate: _manager(),
        files: _movieFiles,
        height: 3600,
        textScale: catalogTextScale,
      ),
      _scene(
        'Requester · at twice the reading size',
        client: _Seerr(_requesterIssue()),
        gate: _requester(),
        audience: Audience.requester,
        userId: 2,
        height: 2900,
        textScale: catalogTextScale,
      ),
    ],
  );
}
