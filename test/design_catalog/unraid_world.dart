import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import 'catalog.dart';

/// What the Unraid API answers about one of its documents, in a scene.
enum UnraidCatalogAnswer {
  /// The document answers.
  answers,

  /// The resolver failed on the server: 200 with an `errors` entry, as a
  /// stopped Docker service or a failed CPU read answers.
  fails,

  /// The API does not know the field: 400 `GRAPHQL_VALIDATION_FAILED`, as an
  /// API older than the field answers.
  unknown,

  /// Still on its way: the request never completes while the sheet is drawn.
  pending,
}

/// An Unraid server as its GraphQL API answers, at the HTTP level.
///
/// The client the app ships talks to it through Dio, so a scene draws what the
/// app draws against that server, failures included: Apollo answers a field
/// the schema does not have with **400** and `GRAPHQL_VALIDATION_FAILED`, and
/// a resolver that throws with 200 and an `errors` entry. The schema is the
/// one Unraid 7.3.5 serves (API 4.37.11): `docker { containers }` and
/// `metrics`, no `dockerContainers`.
class UnraidCatalogApi implements HttpClientAdapter {
  UnraidCatalogApi({
    this.docker = UnraidCatalogAnswer.answers,
    this.metrics = UnraidCatalogAnswer.answers,
  });

  final UnraidCatalogAnswer docker;
  final UnraidCatalogAnswer metrics;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final body = options.data;
    final document = body is Map ? '${body['query']}' : '';
    final root = _rootField(document);
    final answer = switch (root) {
      'docker' => docker,
      'metrics' => metrics,
      'info' || 'array' => UnraidCatalogAnswer.answers,
      _ => UnraidCatalogAnswer.unknown,
    };
    return switch (answer) {
      UnraidCatalogAnswer.pending => Completer<ResponseBody>().future,
      UnraidCatalogAnswer.unknown => Future.value(
        _json(400, {
          'errors': [
            {
              'message': 'Cannot query field "$root" on type "Query".',
              'extensions': {'code': 'GRAPHQL_VALIDATION_FAILED'},
            },
          ],
        }),
      ),
      UnraidCatalogAnswer.fails => Future.value(
        _json(200, {
          'data': {root: null},
          'errors': [
            {
              'message': root == 'docker'
                  ? 'connect ENOENT /var/run/docker.sock'
                  : 'Failed to read system metrics',
              'path': [root],
              'extensions': {'code': 'INTERNAL_SERVER_ERROR'},
            },
          ],
        }),
      ),
      UnraidCatalogAnswer.answers => Future.value(
        _json(200, {
          'data': {root: _world[root]},
        }),
      ),
    };
  }

  @override
  void close({bool force = false}) {}
}

/// The first field under the operation: `info` in `query { info { … } }`.
String _rootField(String document) {
  final open = document.indexOf('{');
  if (open < 0) return '';
  final match = RegExp(r'[A-Za-z_]\w*').firstMatch(document.substring(open));
  return match?.group(0) ?? '';
}

ResponseBody _json(int status, Map<String, Object?> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// A tower with fifteen drives, up for thirteen days: the server in the issue
/// that asked for this page.
Map<String, Object?> get _world => {
  'info': {
    'os': {
      'distro': 'Unraid',
      'release': '7.3.5',
      'uptime': catalogNow
          .subtract(const Duration(days: 13, hours: 4))
          .toUtc()
          .toIso8601String(),
    },
  },
  'array': {
    'state': 'STARTED',
    'capacity': {
      'kilobytes': {
        'free': '61000000000',
        'used': '115000000000',
        'total': '176000000000',
      },
    },
    'parities': [
      {'name': 'parity', 'status': 'DISK_OK', 'temp': 34},
      {'name': 'parity2', 'status': 'DISK_OK', 'temp': 35},
    ],
    'disks': [
      for (final (index, temp) in const [
        33, 36, 35, null, 37, 34, 38, 36, 35, 39, 34, 33, //
      ].indexed)
        {'name': 'disk${index + 1}', 'status': 'DISK_OK', 'temp': temp},
    ],
    'caches': [
      {'name': 'cache', 'status': 'DISK_OK', 'temp': 41},
    ],
  },
  'docker': {
    'containers': [
      _container('plex', 'RUNNING', 'Up 13 days'),
      _container('sonarr', 'RUNNING', 'Up 13 days'),
      _container('radarr', 'RUNNING', 'Up 13 days'),
      _container('qbittorrent', 'RUNNING', 'Up 13 days (healthy)'),
      _container('seerr', 'RUNNING', 'Up 6 days'),
      _container('immich', 'RUNNING', 'Up 6 days'),
      _container('homeassistant', 'RUNNING', 'Up 2 days'),
      _container('tdarr', 'EXITED', 'Exited (0) 2 days ago', autoStart: false),
    ],
  },
  'metrics': {
    'cpu': {'percentTotal': 12.4},
    'memory': {
      // `BigInt` crosses the wire as a number or a string, by server.
      'total': 68719476736,
      'available': '40407810048',
      'percentTotal': 41.2,
    },
  },
};

Map<String, Object?> _container(
  String name,
  String state,
  String status, {
  bool autoStart = true,
}) => {
  'id': 'c0ffee:${name.hashCode.toUnsigned(32).toRadixString(16)}',
  'names': ['/$name'],
  'state': state,
  'status': status,
  'autoStart': autoStart,
};

/// The overrides an Unraid scene adds to a configured connection at
/// `tower.lan`: the app's own client over [api], a reachability probe that
/// has answered (the probe builds a client of its own, which would dial), and
/// no metrics poll.
List<Override> unraidCatalogOverrides(UnraidCatalogApi api) {
  final client = UnraidClient(
    url: 'http://tower.lan',
    apiKey: 'catalog',
    dio: Dio(BaseOptions(baseUrl: 'http://tower.lan'))..httpClientAdapter = api,
  );
  return [
    unraidClientProvider.overrideWithValue(client),
    unraidClientForProvider.overrideWith((ref, instanceId) => client),
    // The page reads the metrics again on a timer; a sheet draws one read.
    unraidMetricsPollProvider.overrideWith((ref) {}),
    serviceSummaryProvider.overrideWith(
      (ref, service) async => ServiceSummary(
        service: service,
        status: ServiceSummaryStatus.online,
        host: 'tower.lan',
        version: '7.3.5',
      ),
    ),
  ];
}
