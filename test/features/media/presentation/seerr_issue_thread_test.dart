/// An issue and its conversation: what each audience reads, what each verdict
/// draws, the exact requests every write sends, and how each failure reads.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/media/presentation/issue_files_provider.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/seerr_issue_thread_screen.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

final _now = DateTime.now();

/// Yesterday at 21:40, local: `yesterday 21:40`.
final _yesterday = DateTime(_now.year, _now.month, _now.day - 1, 21, 40);

/// Today at 08:12, local: `today 08:12`.
final _morning = DateTime(_now.year, _now.month, _now.day, 8, 12);

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
Map<String, dynamic> _issue({
  int status = 1,
  int type = 1,
  int season = 0,
  int episode = 0,
  String media = 'movie',
  int tmdb = 603,
  Map<String, dynamic>? modifiedBy,
  List<Map<String, dynamic>>? comments,
  int by = 5,
  String name = 'Luca',
}) => {
  'id': 12,
  'issueType': type,
  'status': status,
  'problemSeason': season,
  'problemEpisode': episode,
  'createdAt': _iso(_yesterday),
  'updatedAt': _iso(_yesterday),
  'media': {'id': 81, 'mediaType': media, 'tmdbId': tmdb, 'status': 5},
  'createdBy': {'id': by, 'displayName': name},
  'modifiedBy': modifiedBy,
  'comments':
      comments ??
      [
        _comment(
          1,
          'It plays a different movie: the file is Sintel.',
          by: by,
          name: name,
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
          by: by,
          name: name,
          at: _morning,
        ),
      ],
};

/// A Seerr that holds one issue and the title page it hydrates from, applies
/// what is written to it, and remembers every request in order.
class _Seerr extends FakeApiClient {
  _Seerr(this.issue);

  Map<String, dynamic> issue;
  final requests = <String>[];
  final bodies = <Object?>[];

  /// Thrown by the next write, then cleared.
  Object? failWrite;

  /// Thrown by every read of the issue while set.
  Object? failRead;

  void _note(String method, String path, Object? data) {
    requests.add('$method $path');
    bodies.add(data);
  }

  List<Map<String, dynamic>> get _comments =>
      List<Map<String, dynamic>>.from(issue['comments'] as List);

  Response<dynamic> _ok(String path, [Object? data]) => Response(
    requestOptions: RequestOptions(path: path),
    data: data,
  );

  void _checkWrite() {
    final error = failWrite;
    if (error != null) {
      failWrite = null;
      throw error;
    }
  }

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    _note('GET', path, null);
    if (path == '/api/v1/issue/12') {
      if (failRead != null) throw failRead!;
      return _ok(path, issue);
    }
    if (path == '/api/v1/movie/603') {
      return _ok(path, {
        'title': 'Tears of Steel',
        'releaseDate': '2012-09-26',
        'posterPath': '/tos.jpg',
      });
    }
    if (path == '/api/v1/tv/358332') {
      return _ok(path, {
        'name': 'Cosmos Laundromat',
        'firstAirDate': '2015-08-10',
        'posterPath': '/cosmos.jpg',
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
    _note('POST', path, data);
    _checkWrite();
    if (path.endsWith('/comment')) {
      issue = {
        ...issue,
        'comments': [
          ..._comments,
          _comment(
            90 + _comments.length,
            (data as Map)['message'] as String,
            by: 1,
            name: 'Matt',
          ),
        ],
      };
    } else if (path.endsWith('/resolved')) {
      issue = {
        ...issue,
        'status': 2,
        'modifiedBy': {'id': 1, 'displayName': 'Matt'},
      };
    } else if (path.endsWith('/open')) {
      issue = {...issue, 'status': 1};
    }
    return _ok(path);
  }

  @override
  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    _note('PUT', path, data);
    _checkWrite();
    final id = int.parse(path.split('/').last);
    issue = {
      ...issue,
      'comments': [
        for (final comment in _comments)
          if (comment['id'] == id)
            {...comment, 'message': (data as Map)['message']}
          else
            comment,
      ],
    };
    return _ok(path);
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    _note('DELETE', path, null);
    _checkWrite();
    if (path.contains('issueComment')) {
      final id = int.parse(path.split('/').last);
      issue = {
        ...issue,
        'comments': [
          for (final comment in _comments)
            if (comment['id'] != id) comment,
        ],
      };
    }
    return _ok(path);
  }

  /// The body of the last write.
  Object? get lastWriteBody {
    for (var i = requests.length - 1; i >= 0; i--) {
      if (!requests[i].startsWith('GET')) return bodies[i];
    }
    return null;
  }

  List<String> get writes => [
    for (final request in requests)
      if (!request.startsWith('GET')) request,
  ];

  int get issueReads =>
      requests.where((r) => r == 'GET /api/v1/issue/12').length;
}

DioException _failed({
  DioExceptionType type = DioExceptionType.badResponse,
  int? status,
  Object? body,
  String path = '/api/v1/issue/12',
  String method = 'GET',
}) => DioException(
  requestOptions: RequestOptions(path: path, method: method),
  type: type,
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: path),
          statusCode: status,
          data: body,
        ),
);

DioException get _timeout => _failed(type: DioExceptionType.receiveTimeout);

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

class _Opened {
  _Opened(this.client, this.navigator, this.container);

  final _Seerr client;
  final NavigatorState navigator;
  final ProviderContainer container;
}

/// Opens the issue on a navigator with a page under it, so Back has
/// somewhere to go.
Future<_Opened> _open(
  WidgetTester tester, {
  required _Seerr client,
  RoleGate? gate,
  Audience audience = Audience.operator,
  int? userId = 1,
  List<IssueFile> files = const [],
  double textScale = 1,
  GoRouter? router,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = <Override>[
    ...await settingsScopeOverrides(configured: [ServiceKey.seerr]),
    audienceProvider.overrideWithValue(audience),
    roleGateProvider.overrideWith((ref, id) => gate ?? _manager()),
    seerrAccountUserIdProvider.overrideWith((ref, id) => userId),
    seerrServiceForProvider.overrideWith(
      (ref, id) => SeerrService(client, numbering: SeerrNumbering.seerr),
    ),
    titleLightProvider.overrideWith((ref, url) async => null),
    ...extra,
    issueFilesProvider.overrideWith((ref, scope) => files),
    mediaSeasonFactsProvider.overrideWith(
      (ref, source) async => [
        for (var n = 1; n <= 4; n++)
          MediaEpisodeFacts(
            season: source.season,
            number: n,
            name: n == 3 ? 'The Second Cycle' : 'Episode $n',
          ),
      ],
    ),
  ];
  const screen = SeerrIssueThreadScreen(issueId: 12);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: router != null
          ? MaterialApp.router(
              theme: AppTheme.darkTheme(),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
            )
          : MaterialApp(
              theme: AppTheme.darkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const Scaffold(body: Text('The list')),
            ),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  if (router == null) {
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => screen)));
  }
  await tester.pumpAndSettle();
  return _Opened(
    client,
    navigator,
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))),
  );
}

Finder _text(String text) => find.text(text);

Finder get _field => find.byType(TextField);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  group('the operator reads the issue', () {
    testWidgets('the title, the report, where it stands, the conversation', (
      tester,
    ) async {
      await _open(tester, client: _Seerr(_issue()));

      // The title card: the hydrated name, the year, and that it is on the
      // server, then the report's own words as the heading.
      expect(_text('Tears of Steel'), findsOneWidget);
      expect(_text('Movie\u00A0· 2012\u00A0· on your server'), findsOneWidget);
      expect(
        _text('It plays a different movie: the file is Sintel.'),
        findsOneWidget,
      );
      // Amber `Open`, and who reported it and when.
      expect(_text('Open'), findsOneWidget);
      expect(_text('Video\u00A0· Luca\u00A0· yesterday 21:40'), findsOneWidget);
      // Replies: the count, one's own as `You`, the person's name otherwise.
      expect(_text('Replies'), findsOneWidget);
      expect(_text('2'), findsOneWidget);
      expect(_text('You'), findsOneWidget);
      expect(_text('Luca'), findsOneWidget);
      expect(_text('today 08:12'), findsOneWidget);
      expect(_text('Which copy, the 4K or the normal one?'), findsOneWidget);
      // The composer names the reporter and says who reads what is sent.
      expect(
        tester.widget<TextField>(_field).decoration?.hintText,
        'Reply to Luca',
      );
      expect(
        _text('Luca reads replies in Seerr, or in Cupola.'),
        findsOneWidget,
      );
      // The actions.
      expect(_text('Resolve'), findsOneWidget);
      expect(_text('Delete issue'), findsOneWidget);
      expect(_text('Open in Seerr'), findsOneWidget);
      // No file section while the copies name no file.
      expect(_text('Files it could be'), findsNothing);
    });

    testWidgets('with the API key, user 1 is the reader: its reply is You, '
        'with its menu; anybody else\'s is not', (tester) async {
      // The key has no account, and Seerr authenticates it as user 1.
      await _open(
        tester,
        client: _Seerr(_issue()),
        gate: const RoleGate(
          audience: Audience.operator,
          grant: SeerrGrant.apiKey(),
        ),
        userId: null,
      );
      expect(_text('You'), findsOneWidget);
      expect(_text('Luca'), findsOneWidget);
      expect(find.byTooltip('Edit or delete your reply'), findsOneWidget);
    });

    testWidgets('an episode issue names the episode', (tester) async {
      await _open(
        tester,
        client: _Seerr(
          _issue(media: 'tv', tmdb: 358332, season: 2, episode: 3, type: 2),
        ),
      );
      expect(_text('Cosmos Laundromat'), findsOneWidget);
      expect(
        _text('${formatEpisodeCode(2, 3)}\u00A0· The Second Cycle'),
        findsOneWidget,
      );
      expect(_text('Audio\u00A0· Luca\u00A0· yesterday 21:40'), findsOneWidget);
    });

    testWidgets('a whole season', (tester) async {
      await _open(
        tester,
        client: _Seerr(_issue(media: 'tv', tmdb: 358332, season: 2)),
      );
      expect(_text('Season 2\u00A0· All episodes'), findsOneWidget);
    });

    testWidgets('a whole series', (tester) async {
      await _open(tester, client: _Seerr(_issue(media: 'tv', tmdb: 358332)));
      expect(_text('Series\u00A0· 2015\u00A0· on your server'), findsOneWidget);
    });

    testWidgets('resolved: green, by whom and when, Reopen for Resolve', (
      tester,
    ) async {
      final client = _Seerr(
        _issue(status: 2, modifiedBy: {'id': 1, 'displayName': 'Matt'}),
      );
      await _open(tester, client: client);
      expect(_text('Resolved'), findsOneWidget);
      expect(_text('Open'), findsNothing);
      expect(
        _text('Video\u00A0· Luca\u00A0· resolved by you, yesterday 21:40'),
        findsOneWidget,
      );
      expect(_text('Reopen'), findsOneWidget);
      expect(_text('Resolve'), findsNothing);
    });

    testWidgets('resolved by somebody else names them', (tester) async {
      await _open(
        tester,
        client: _Seerr(
          _issue(status: 2, modifiedBy: {'id': 9, 'displayName': 'Sara'}),
        ),
      );
      expect(
        _text('Video\u00A0· Luca\u00A0· resolved by Sara, yesterday 21:40'),
        findsOneWidget,
      );
    });

    testWidgets('no replies: a line, and the composer', (tester) async {
      await _open(
        tester,
        client: _Seerr(
          _issue(comments: [_comment(1, 'It freezes', by: 5, name: 'Luca')]),
        ),
      );
      expect(_text('No replies yet.'), findsOneWidget);
      expect(_text('Replies'), findsNothing);
      expect(_field, findsOneWidget);
    });

    testWidgets('the title card opens the title through its page', (
      tester,
    ) async {
      final location = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const SeerrIssueThreadScreen(issueId: 12),
          ),
          GoRoute(
            path: '/media/:kind/:id',
            builder: (context, state) {
              location.add(state.uri.toString());
              return const Scaffold(body: Text('The title'));
            },
          ),
        ],
      );
      await _open(tester, client: _Seerr(_issue()), router: router);
      await tester.tap(_text('Tears of Steel'));
      await tester.pumpAndSettle();
      expect(_text('The title'), findsOneWidget);
      // The connection the issue lives on leads, and the poster flies.
      expect(location.single, startsWith('/media/movie/603'));
      expect(location.single, contains('i=seerr'));
    });
  });

  group('the files it could be', () {
    final file = IssueFile(
      connectionId: 'radarr-4k',
      connectionName: 'Radarr\u00A0· 4K',
      quality: 'Remux-2160p',
      size: 9800000000,
      fileName: 'Tears of Steel (2012) Remux-2160p.mkv',
      importedAt: _yesterday,
      target: const ReleaseSearchTarget.movie(
        movieId: 7,
        label: 'Tears of Steel',
      ),
    );

    testWidgets('each copy: quality and size, the file, where, when', (
      tester,
    ) async {
      await _open(tester, client: _Seerr(_issue()), files: [file]);
      await _scrollTo(tester, _text('Files it could be'));
      expect(_text('Files it could be'), findsOneWidget);
      expect(
        _text('2160p Remux\u00A0· ${formatBytes(9800000000)}'),
        findsOneWidget,
      );
      expect(_text('Tears of Steel (2012) Remux-2160p.mkv'), findsOneWidget);
      expect(
        _text('Radarr\u00A0· 4K\u00A0· imported yesterday'),
        findsOneWidget,
      );
      expect(_text('Search a new release'), findsOneWidget);
      expect(
        _text('Replacing a file keeps the issue open until you resolve it.'),
        findsOneWidget,
      );
    });

    testWidgets('Search a new release runs the search for that copy', (
      tester,
    ) async {
      final searched = <ReleaseSearchTarget>[];
      await _open(
        tester,
        client: _Seerr(_issue()),
        files: [file],
        extra: [
          releaseSearchRunnerProvider.overrideWithValue((target, token) {
            searched.add(target);
            return Completer<List<dynamic>>().future;
          }),
        ],
      );
      await _scrollTo(tester, _text('Search a new release'));
      await tester.tap(_text('Search a new release'));
      await tester.pump();
      await tester.pump();
      expect(searched, [file.target]);
    });

    testWidgets('the copy chosen is the copy searched', (tester) async {
      final searched = <ReleaseSearchTarget>[];
      final hd = IssueFile(
        connectionId: 'radarr',
        connectionName: 'Radarr',
        quality: 'Bluray-1080p',
        fileName: 'Tears of Steel (2012) Bluray-1080p.mkv',
        target: const ReleaseSearchTarget.movie(
          movieId: 3,
          label: 'Tears of Steel',
        ).stampedWith('radarr'),
      );
      await _open(
        tester,
        client: _Seerr(_issue()),
        files: [hd, file],
        extra: [
          releaseSearchRunnerProvider.overrideWithValue((target, token) {
            searched.add(target);
            return Completer<List<dynamic>>().future;
          }),
        ],
      );
      await _scrollTo(tester, _text('Search a new release'));
      await tester.tap(_text('Search a new release'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Search releases on Radarr\u00A0· 4K'),
      );
      await tester.pump();
      await tester.pump();
      expect(searched, [file.target]);
    });

    testWidgets(
      'several copies: the search asks which, as the title page does',
      (tester) async {
        final hd = IssueFile(
          connectionId: 'radarr',
          connectionName: 'Radarr',
          quality: 'Bluray-1080p',
          size: 1200000000,
          fileName: 'Tears of Steel (2012) Bluray-1080p.mkv',
          importedAt: _yesterday,
          target: const ReleaseSearchTarget.movie(
            movieId: 3,
            label: 'Tears of Steel',
          ).stampedWith('radarr'),
        );
        await _open(tester, client: _Seerr(_issue()), files: [hd, file]);
        await _scrollTo(tester, _text('Search a new release'));
        await tester.tap(_text('Search a new release'));
        await tester.pumpAndSettle();
        // One row per copy, each saying what it does there.
        expect(_text('Radarr'), findsWidgets);
        expect(
          find.bySemanticsLabel('Search releases on Radarr'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Search releases on Radarr\u00A0· 4K'),
          findsOneWidget,
        );
      },
    );

    testWidgets('only while the issue is open', (tester) async {
      await _open(tester, client: _Seerr(_issue(status: 2)), files: [file]);
      expect(_text('Files it could be'), findsNothing);
      expect(_text('Search a new release'), findsNothing);
    });

    testWidgets('the requester never reads them', (tester) async {
      await _open(
        tester,
        client: _Seerr(_issue(by: 2, name: 'Anna')),
        audience: Audience.requester,
        gate: _requester(),
        userId: 2,
        files: [file],
      );
      expect(_text('Files it could be'), findsNothing);
    });
  });

  group('the requester reads her report', () {
    Map<String, dynamic> hers({
      int status = 1,
      List<Map<String, dynamic>>? comments,
      Map<String, dynamic>? modifiedBy,
    }) => _issue(
      by: 2,
      name: 'Anna',
      type: 2,
      status: status,
      modifiedBy: modifiedBy,
      comments:
          comments ??
          [
            _comment(1, 'The audio is in Russian.', by: 2, name: 'Anna'),
            _comment(
              2,
              'Is it every episode, or only this one?',
              by: 1,
              name: 'Matt',
            ),
            _comment(
              3,
              'Only this one. The others are fine.',
              by: 2,
              name: 'Anna',
              at: _morning,
            ),
          ],
    );

    Future<void> openHers(
      WidgetTester tester, {
      Map<String, dynamic>? issue,
      _Seerr? client,
      RoleGate? gate,
    }) => _open(
      tester,
      client: client ?? _Seerr(issue ?? hers()),
      audience: Audience.requester,
      gate: gate ?? _requester(),
      userId: 2,
    );

    testWidgets('blue `Reported`, never a service name, never "issue"', (
      tester,
    ) async {
      await openHers(tester);
      expect(_text('Reported'), findsOneWidget);
      expect(_text('Open'), findsNothing);
      // Hers: no reporter's name, her own words as `You`.
      expect(_text('Audio\u00A0· yesterday 21:40'), findsOneWidget);
      expect(_text('Replies'), findsOneWidget);
      expect(_text('You'), findsOneWidget);
      expect(_text('Matt'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field).decoration?.hintText,
        'Reply to Matt',
      );
      expect(_text('Matt sees your reply.'), findsOneWidget);
      expect(_text('Mark as resolved'), findsOneWidget);
      expect(
        _text('When it plays right again. Matt can reopen it, and so can you.'),
        findsOneWidget,
      );
      // The operator's furniture is not part of her app.
      expect(_text('Resolve'), findsNothing);
      expect(_text('Delete issue'), findsNothing);
      expect(_text('Open in Seerr'), findsNothing);
      expect(_text('Files it could be'), findsNothing);
      expect(find.textContaining('Seerr'), findsNothing);
      expect(find.textContaining('issue'), findsNothing);
      // Replies came in, so the report can no longer be deleted.
      expect(_text('Delete report'), findsNothing);
    });

    testWidgets('just reported: Add a detail, and Delete report', (
      tester,
    ) async {
      await openHers(
        tester,
        issue: hers(
          comments: [
            _comment(1, 'The audio is in Russian.', by: 2, name: 'Anna'),
          ],
        ),
      );
      expect(_text('No replies yet.'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field).decoration?.hintText,
        'Add a detail',
      );
      expect(
        _text('Whoever runs the server sees what you add.'),
        findsOneWidget,
      );
      expect(_text('Mark as resolved'), findsOneWidget);
      expect(_text('Delete report'), findsOneWidget);
      expect(
        _text('Only while nobody has replied, as on the server.'),
        findsOneWidget,
      );
    });

    testWidgets('only her own comments make `Add a detail`', (tester) async {
      await openHers(
        tester,
        issue: hers(
          comments: [
            _comment(1, 'The audio is in Russian.', by: 2, name: 'Anna'),
            _comment(2, 'Also the subtitles.', by: 2, name: 'Anna'),
          ],
        ),
      );
      expect(
        tester.widget<TextField>(_field).decoration?.hintText,
        'Add a detail',
      );
      // Two comments: the report is no longer alone, nothing to delete.
      expect(_text('Delete report'), findsNothing);
    });

    testWidgets('after it was resolved: green, by whom, Reopen', (
      tester,
    ) async {
      await openHers(
        tester,
        issue: hers(status: 2, modifiedBy: {'id': 1, 'displayName': 'Matt'}),
      );
      expect(_text('Resolved'), findsOneWidget);
      expect(
        _text('Audio\u00A0· resolved by Matt, yesterday 21:40'),
        findsOneWidget,
      );
      expect(_text('Reopen'), findsOneWidget);
      expect(_text('Mark as resolved'), findsNothing);
      expect(_text('If it still plays wrong.'), findsOneWidget);
    });

    testWidgets("somebody else's issue is not hers to act on", (tester) async {
      // A report that is not hers reaches her only by a stale link: the page
      // reads, and every control is absent.
      await openHers(tester, issue: _issue(by: 9, name: 'Luca'));
      expect(_field, findsNothing);
      expect(_text('Mark as resolved'), findsNothing);
      expect(_text('Delete report'), findsNothing);
    });

    testWidgets('a deleted report reads that, and goes back to her requests', (
      tester,
    ) async {
      final client = _Seerr(
        hers(),
      )..failRead = _failed(status: 500, body: {'message': 'Issue not found.'});
      await openHers(tester, client: client);
      expect(_text('This report was deleted.'), findsOneWidget);
      expect(_text('Back to Issues'), findsNothing);
      await tester.tap(_text('Back to Requests'));
      await tester.pumpAndSettle();
      expect(_text('The list'), findsOneWidget);
    });
  });

  group('what is written', () {
    testWidgets('a reply: the words, then the issue is read again', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      final reads = client.issueReads;
      await tester.enterText(_field, '  Got it, a new copy is on its way.  ');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pumpAndSettle();
      expect(client.writes, ['POST /api/v1/issue/12/comment']);
      expect(client.lastWriteBody, {
        'message': 'Got it, a new copy is on its way.',
      });
      // Read again, the composer emptied, the reply on the page as one's own.
      expect(client.issueReads, reads + 1);
      expect(tester.widget<TextField>(_field).controller?.text, '');
      expect(_text('Got it, a new copy is on its way.'), findsOneWidget);
    });

    testWidgets(
      'every write reads the issue, the Issues list and the title rows again',
      (tester) async {
        var lists = 0;
        var records = 0;
        final client = _Seerr(_issue());
        final opened = await _open(
          tester,
          client: client,
          extra: [
            seerrIssuesProvider.overrideWith((ref, filter) async {
              lists++;
              return const SeerrAdminResult<SeerrIssue>(items: [], total: 0);
            }),
            mediaSeerrRecordProvider.overrideWith((ref, source) async {
              records++;
              return MediaAnswer(
                const MediaSeerrRecord(details: {}),
                DateTime(2026),
              );
            }),
          ],
        );
        // The list and the title's record are alive, as they are under the
        // page that opened this one.
        opened.container
          ..listen(seerrIssuesProvider(SeerrIssueFilter.open), (_, _) {})
          ..listen(
            mediaSeerrRecordProvider((
              key: const MediaKey.movie(603),
              connectionId: 'seerr',
            )),
            (_, _) {},
          );
        await tester.pumpAndSettle();
        final (l, r, i) = (lists, records, client.issueReads);
        await tester.tap(_text('Resolve'));
        await tester.pumpAndSettle();
        expect(client.issueReads, i + 1);
        expect(lists, l + 1);
        expect(records, r + 1);
      },
    );

    testWidgets('an empty reply sends nothing', (tester) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      await tester.enterText(_field, '   ');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pumpAndSettle();
      expect(client.writes, isEmpty);
    });

    testWidgets('a reply that did not send keeps its words and can retry', (
      tester,
    ) async {
      final client = _Seerr(_issue())..failWrite = _timeout;
      await _open(tester, client: client);
      await tester.enterText(_field, 'Got it, a new copy is on its way.');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not send the reply. Nothing was sent.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(_field).controller?.text,
        'Got it, a new copy is on its way.',
      );
      // Retry sends the same request again, and this time it goes.
      await tester.tap(_text('Retry'));
      await tester.pumpAndSettle();
      expect(client.writes, [
        'POST /api/v1/issue/12/comment',
        'POST /api/v1/issue/12/comment',
      ]);
      expect(tester.widget<TextField>(_field).controller?.text, '');
    });

    testWidgets('a refusal offers no Retry', (tester) async {
      final client = _Seerr(_issue())
        ..failWrite = _failed(
          status: 403,
          method: 'POST',
          path: '/api/v1/issue/12/comment',
          body: {
            'message': 'You do not have permission to access this endpoint',
          },
        );
      await _open(tester, client: client);
      await tester.enterText(_field, 'Hello');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not send the reply. Nothing was sent.'),
        findsOneWidget,
      );
      expect(_text('Retry'), findsNothing);
      expect(tester.widget<TextField>(_field).controller?.text, 'Hello');
    });

    testWidgets('editing happens in place: Cancel leaves it, Save sends', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Edit reply'));
      await tester.pumpAndSettle();
      expect(_text('Editing your reply'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Which copy, the 4K or the normal one?'),
        findsOneWidget,
      );
      // Cancel: the words are back, nothing was written.
      await tester.tap(_text('Cancel'));
      await tester.pumpAndSettle();
      expect(_text('Editing your reply'), findsNothing);
      expect(client.writes, isEmpty);

      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Edit reply'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Which copy, the 4K or the normal one?'),
        'Which copy, the 4K or the 1080p one?',
      );
      await tester.tap(_text('Save'));
      await tester.pumpAndSettle();
      expect(client.writes, ['PUT /api/v1/issueComment/2']);
      expect(client.lastWriteBody, {
        'message': 'Which copy, the 4K or the 1080p one?',
      });
      expect(_text('Editing your reply'), findsNothing);
      expect(_text('Which copy, the 4K or the 1080p one?'), findsOneWidget);
    });

    testWidgets('a save that failed keeps the editor and the words', (
      tester,
    ) async {
      final client = _Seerr(_issue())..failWrite = _timeout;
      await _open(tester, client: client);
      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Edit reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Edited words');
      await tester.tap(_text('Save'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not save the reply. Nothing changed.'),
        findsOneWidget,
      );
      expect(_text('Editing your reply'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Edited words'), findsOneWidget);
    });

    testWidgets('deleting a reply asks first, and says what happens', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Delete reply'));
      await tester.pumpAndSettle();
      expect(_text('Delete this reply?'), findsOneWidget);
      expect(
        _text("Luca won't see it any more. This cannot be undone."),
        findsOneWidget,
      );
      // Keep it: nothing is sent.
      await tester.tap(_text('Keep it'));
      await tester.pumpAndSettle();
      expect(client.writes, isEmpty);

      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Delete reply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete reply'));
      await tester.pumpAndSettle();
      expect(client.writes, ['DELETE /api/v1/issueComment/2']);
      expect(_text('Which copy, the 4K or the normal one?'), findsNothing);
      expect(_text('Replies'), findsOneWidget);
    });

    testWidgets('a reply deleted meanwhile is read again, not a fault', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      client.failWrite = _failed(
        status: 404,
        method: 'DELETE',
        path: '/api/v1/issueComment/2',
        body: {'message': 'Issue comment not found.'},
      );
      final reads = client.issueReads;
      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Delete reply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete reply'));
      await tester.pumpAndSettle();
      expect(client.issueReads, reads + 1);
      expect(find.textContaining('Could not'), findsNothing);
    });

    testWidgets('Resolve sends once, then reads green; Reopen undoes it', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      await tester.tap(_text('Resolve'));
      await tester.pumpAndSettle();
      expect(client.writes, ['POST /api/v1/issue/12/resolved']);
      expect(_text('Resolved'), findsOneWidget);
      expect(_text('Reopen'), findsOneWidget);
      await tester.tap(_text('Reopen'));
      await tester.pumpAndSettle();
      expect(client.writes.last, 'POST /api/v1/issue/12/open');
      expect(_text('Open'), findsOneWidget);
      expect(_text('Resolve'), findsOneWidget);
    });

    testWidgets('a failed Resolve says nothing changed, with Retry', (
      tester,
    ) async {
      final client = _Seerr(_issue())..failWrite = _timeout;
      await _open(tester, client: client);
      await tester.tap(_text('Resolve'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not resolve the issue. Nothing changed.'),
        findsOneWidget,
      );
      expect(_text('Open'), findsOneWidget);
      await tester.tap(_text('Retry'));
      await tester.pumpAndSettle();
      expect(client.writes, [
        'POST /api/v1/issue/12/resolved',
        'POST /api/v1/issue/12/resolved',
      ]);
      expect(_text('Resolved'), findsOneWidget);
    });

    testWidgets('the requester marks it as resolved in her own words', (
      tester,
    ) async {
      final client = _Seerr(
        _issue(
          by: 2,
          name: 'Anna',
          comments: [_comment(1, 'It freezes', by: 2, name: 'Anna')],
        ),
      )..failWrite = _timeout;
      await _open(
        tester,
        client: client,
        audience: Audience.requester,
        gate: _requester(),
        userId: 2,
      );
      await tester.tap(_text('Mark as resolved'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not mark it as resolved. Nothing changed.'),
        findsOneWidget,
      );
      expect(find.textContaining('issue'), findsNothing);
      await tester.tap(_text('Retry'));
      await tester.pumpAndSettle();
      expect(client.writes.last, 'POST /api/v1/issue/12/resolved');
      expect(_text('Resolved'), findsOneWidget);
      await tester.tap(_text('Reopen'));
      await tester.pumpAndSettle();
      expect(client.writes.last, 'POST /api/v1/issue/12/open');
    });

    testWidgets('Delete issue asks, names who loses it, and leaves the page', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      await _scrollTo(tester, _text('Delete issue'));
      await tester.tap(_text('Delete issue'));
      await tester.pumpAndSettle();
      expect(_text('Delete this issue?'), findsOneWidget);
      expect(
        _text(
          'Seerr removes it and its replies, for Luca too. '
          'This cannot be undone.',
        ),
        findsOneWidget,
      );
      await tester.tap(_text('Keep it'));
      await tester.pumpAndSettle();
      expect(client.writes, isEmpty);

      await tester.tap(_text('Delete issue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete issue'));
      await tester.pumpAndSettle();
      expect(client.writes, ['DELETE /api/v1/issue/12']);
      // Back on the list, and it is said.
      expect(_text('The list'), findsOneWidget);
      expect(_text('Issue deleted'), findsOneWidget);
    });

    testWidgets('the requester deletes her report: asked in her own words', (
      tester,
    ) async {
      final client = _Seerr(
        _issue(
          by: 2,
          name: 'Anna',
          comments: [_comment(1, 'It freezes', by: 2, name: 'Anna')],
        ),
      );
      await _open(
        tester,
        client: client,
        audience: Audience.requester,
        gate: _requester(),
        userId: 2,
      );
      await tester.tap(_text('Delete report'));
      await tester.pumpAndSettle();
      expect(_text('Delete this report?'), findsOneWidget);
      expect(
        _text(
          "Whoever runs the server won't see it any more. "
          'This cannot be undone.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete report'));
      await tester.pumpAndSettle();
      expect(client.writes, ['DELETE /api/v1/issue/12']);
      expect(_text('The list'), findsOneWidget);
      expect(_text('Report deleted'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the page and says nothing changed', (
      tester,
    ) async {
      final client = _Seerr(_issue())..failWrite = _timeout;
      await _open(tester, client: client);
      await _scrollTo(tester, _text('Delete issue'));
      await tester.tap(_text('Delete issue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete issue'));
      await tester.pumpAndSettle();
      expect(
        _text('Could not delete the issue. Nothing changed.'),
        findsOneWidget,
      );
      expect(_text('The list'), findsNothing);
      expect(_text('Delete issue'), findsOneWidget);
    });

    testWidgets('an issue deleted meanwhile reads gone after a write', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client);
      client
        ..failWrite = _failed(
          status: 500,
          method: 'POST',
          path: '/api/v1/issue/12/resolved',
          body: {'message': 'Issue not found.'},
        )
        ..failRead = _failed(
          status: 500,
          body: {'message': 'Issue not found.'},
        );
      await tester.tap(_text('Resolve'));
      await tester.pumpAndSettle();
      expect(_text('This issue is gone'), findsOneWidget);
      expect(find.textContaining('Could not'), findsNothing);
    });
  });

  group('when the issue is gone or cannot be read', () {
    testWidgets('gone: where it went, and back to the list', (tester) async {
      final client = _Seerr(
        _issue(),
      )..failRead = _failed(status: 500, body: {'message': 'Issue not found.'});
      await _open(tester, client: client);
      expect(_text('This issue is gone'), findsOneWidget);
      expect(_text('Someone deleted it in Seerr.'), findsOneWidget);
      await tester.tap(_text('Back to Issues'));
      await tester.pumpAndSettle();
      expect(_text('The list'), findsOneWidget);
    });

    testWidgets('a read that answers 404 is gone too', (tester) async {
      final client = _Seerr(
        _issue(),
      )..failRead = _failed(status: 404, body: {'message': 'Issue not found.'});
      await _open(tester, client: client);
      expect(_text('This issue is gone'), findsOneWidget);
    });

    testWidgets('a read that failed says so, and can be tried again', (
      tester,
    ) async {
      final client = _Seerr(_issue())..failRead = _timeout;
      await _open(tester, client: client);
      expect(_text('Retry'), findsOneWidget);
      client.failRead = null;
      await tester.tap(_text('Retry'));
      await tester.pumpAndSettle();
      expect(
        _text('It plays a different movie: the file is Sintel.'),
        findsOneWidget,
      );
    });
  });

  group('the gate decides every control', () {
    testWidgets(
      "an account that cannot manage issues: Resolve and the composer are "
      'dimmed, still targets, and a tap says why',
      (tester) async {
        final client = _Seerr(_issue());
        await _open(tester, client: client, gate: _cannotManage());
        // Both are drawn.
        expect(_text('Resolve'), findsOneWidget);
        expect(_field, findsOneWidget);
        await tester.tap(_text('Resolve'));
        await tester.pump();
        expect(
          _text("Your account on Casa Requests can't manage issues."),
          findsOneWidget,
        );
        // The composer is one target that answers the same.
        ScaffoldMessenger.of(
          tester.element(_text('Resolve')),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Reply to Luca'));
        await tester.pump();
        expect(
          _text("Your account on Casa Requests can't manage issues."),
          findsOneWidget,
        );
        expect(client.writes, isEmpty);
      },
    );

    testWidgets(
      'a requester who may no longer report: dimmed with the reason',
      (tester) async {
        final client = _Seerr(_issue(by: 2, name: 'Anna'));
        await _open(
          tester,
          client: client,
          audience: Audience.requester,
          gate: _requester(may: false),
          userId: 2,
        );
        await tester.tap(_text('Mark as resolved'));
        await tester.pump();
        expect(
          _text("You can't report problems on this server."),
          findsOneWidget,
        );
        expect(client.writes, isEmpty);
      },
    );

    testWidgets("somebody else's reply has no menu; hers dimmed per verdict", (
      tester,
    ) async {
      await _open(tester, client: _Seerr(_issue()));
      // One menu: the one reply that is Matt's.
      expect(find.byTooltip('Edit or delete your reply'), findsOneWidget);
    });

    testWidgets('an account that cannot edit sees the entry dimmed', (
      tester,
    ) async {
      final client = _Seerr(_issue());
      await _open(tester, client: client, gate: _cannotManage());
      await tester.tap(find.byTooltip('Edit or delete your reply'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Edit reply'));
      await tester.pumpAndSettle();
      expect(
        _text("Your account on Casa Requests can't manage issues."),
        findsOneWidget,
      );
      expect(_text('Editing your reply'), findsNothing);
      expect(client.writes, isEmpty);
    });
  });

  group('the way out', () {
    testWidgets(
      'Open in Seerr goes to the issue at the address it is reached at',
      (tester) async {
        final launched = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/url_launcher'),
              (call) async {
                if (call.method == 'launch') {
                  launched.add((call.arguments as Map)['url']! as String);
                  return true;
                }
                return call.method == 'canLaunch';
              },
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/url_launcher'),
                null,
              ),
        );
        await _open(tester, client: _Seerr(_issue()));
        await _scrollTo(tester, _text('Open in Seerr'));
        await tester.tap(_text('Open in Seerr'));
        await tester.pumpAndSettle();
        expect(launched, ['https://seerr.test/issues/12']);
      },
    );
  });

  testWidgets('at twice the reading size nothing is cut', (tester) async {
    // An overflow is a test failure of its own; the words are all there.
    await _open(tester, client: _Seerr(_issue()), textScale: 2);
    expect(
      _text('It plays a different movie: the file is Sintel.'),
      findsOneWidget,
    );
  });
}
