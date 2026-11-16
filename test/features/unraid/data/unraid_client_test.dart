import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

UnraidClient _client(
  CapturingHttpAdapter adapter, {
  String key = 'UNRAID-KEY',
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://unraid.local'))
    ..httpClientAdapter = adapter;
  return UnraidClient(url: 'https://unraid.local', apiKey: key, dio: dio);
}

void main() {
  group('UnraidClient', () {
    test('getInfo sends the x-api-key header and a GraphQL body', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/info.json'),
      );
      final client = _client(adapter);

      final info = await client.getInfo();

      expect(info.version, '7.2.0');
      expect(adapter.lastHeaders!['x-api-key'], 'UNRAID-KEY');
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['query'], contains('info'));
    });

    test('getArray computes used percentage and parses disks', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/array.json'),
      );
      final array = await _client(adapter).getArray();

      expect(array.state, 'STARTED');
      expect(array.usedPercent, 60);
      expect(array.disks, hasLength(2));
      expect(array.disks[1].temp, 47);
    });

    test(
      'getDockerContainers strips the leading slash and flags running',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('unraid/docker.json'),
        );
        final containers = await _client(adapter).getDockerContainers();

        expect(containers, hasLength(2));
        expect(containers.first.name, 'plex');
        expect(containers.first.running, isTrue);
        expect(containers[1].running, isFalse);
      },
    );

    test('throws UnraidException on a GraphQL error', () async {
      final adapter = CapturingHttpAdapter(
        response: {
          'errors': [
            {'message': 'Unauthorized'},
          ],
        },
      );
      final client = _client(adapter);

      expect(client.getInfo(), throwsA(isA<UnraidException>()));
    });

    test(
      'reads current-schema VMs, notifications and shares independently',
      () async {
        final vmsAdapter = CapturingHttpAdapter(
          response: {
            'data': {
              'vms': {
                'domains': [
                  {'id': 'vm:1', 'name': 'Home Assistant', 'state': 'RUNNING'},
                ],
              },
            },
          },
        );
        expect(
          (await _client(vmsAdapter).getVms()).single.name,
          'Home Assistant',
        );

        final notificationsAdapter = CapturingHttpAdapter(
          response: {
            'data': {
              'notifications': {
                'overview': {
                  'unread': {'info': 0, 'warning': 1, 'alert': 0, 'total': 1},
                  'archive': {'info': 2, 'warning': 0, 'alert': 0, 'total': 2},
                },
                'list': [
                  {
                    'id': 'notification:1',
                    'title': 'Disk warm',
                    'subject': 'disk1',
                    'description': '47 C',
                    'importance': 'WARNING',
                    'type': 'UNREAD',
                  },
                ],
              },
            },
          },
        );
        final notifications = await _client(
          notificationsAdapter,
        ).getNotifications();
        expect(notifications.unread.total, 1);
        expect(notifications.items.single.title, 'Disk warm');
        expect((notificationsAdapter.lastBody as Map)['variables'], {
          'filter': {'type': 'UNREAD', 'offset': 0, 'limit': 100},
        });

        final sharesAdapter = CapturingHttpAdapter(
          response: {
            'data': {
              'shares': [
                {
                  'id': 'share:1',
                  'name': 'media',
                  'used': '400',
                  'size': '1000',
                },
              ],
            },
          },
        );
        expect(
          (await _client(sharesAdapter).getShares()).single.usedFraction,
          0.4,
        );
      },
    );

    test('uses variables for VM mutations', () async {
      final adapter = CapturingHttpAdapter(
        response: {
          'data': {
            'vm': {'start': true},
          },
        },
      );

      expect(
        await _client(adapter).runVmAction('vm:abc', UnraidVmAction.start),
        isTrue,
      );
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['query'], contains(r'start(id: $id)'));
      expect(body['variables'], {'id': 'vm:abc'});
    });
  });

  group('UnraidClient: containers on the current schema', () {
    test('reads `docker { containers }` and sends that document', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/docker.json'),
      );
      final containers = await _client(adapter).getDockerContainers();

      final query = (adapter.lastBody as Map)['query'] as String;
      expect(query, contains('docker { containers {'));
      expect(query, isNot(contains('dockerContainers')));
      expect(containers.map((c) => c.name), ['plex', 'sonarr']);
      expect(containers.first.running, isTrue);
      expect(containers[1].running, isFalse);
    });

    test('an empty containers list is a census of none', () async {
      final adapter = CapturingHttpAdapter(
        response: {
          'data': {
            'docker': {'containers': <Object>[]},
          },
        },
      );
      expect(await _client(adapter).getDockerContainers(), isEmpty);
    });

    for (final (label, body) in <(String, Map<String, dynamic>)>[
      (
        'docker is null',
        {
          'data': {'docker': null},
        },
      ),
      (
        'containers is missing',
        {
          'data': {'docker': <String, dynamic>{}},
        },
      ),
      (
        'containers is null',
        {
          'data': {
            'docker': {'containers': null},
          },
        },
      ),
      ('data is empty', {'data': <String, dynamic>{}}),
    ]) {
      test('$label: invalidResponse, never an empty list', () async {
        final adapter = CapturingHttpAdapter(response: body);
        await expectLater(
          _client(adapter).getDockerContainers(),
          throwsA(
            isA<UnraidException>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.invalidResponse,
            ),
          ),
        );
      });
    }
  });

  group('UnraidClient: a GraphQL error on a 4xx or 5xx answer', () {
    Map<String, dynamic> errorBody(String message, [String? code]) => {
      'errors': [
        {
          'message': message,
          'extensions': ?(code == null ? null : {'code': code}),
        },
      ],
    };

    Future<UnraidException> failure(
      CapturingHttpAdapter adapter, {
      bool metrics = false,
    }) async {
      final client = _client(adapter);
      try {
        await (metrics ? client.getMetrics() : client.getDockerContainers());
      } on UnraidException catch (e) {
        return e;
      }
      fail('expected an UnraidException');
    }

    test('a 400 GRAPHQL_VALIDATION_FAILED keeps the server message and '
        'code, and says the field is unknown', () async {
      final e = await failure(
        CapturingHttpAdapter(
          statusCode: 400,
          response: errorBody(
            'Cannot query field "dockerContainers" on type "Query".',
            'GRAPHQL_VALIDATION_FAILED',
          ),
        ),
      );

      expect(e.reason, ServiceFailureReason.unknown);
      expect(e.message, contains('Cannot query field "dockerContainers"'));
      expect(e.code, 'GRAPHQL_VALIDATION_FAILED');
      expect(e.unknownField, isTrue);
      expect(e.forbidden, isFalse);
    });

    for (final status in [400, 401]) {
      test(
        'a $status with UNAUTHENTICATED is a key that does not work',
        () async {
          final e = await failure(
            CapturingHttpAdapter(
              statusCode: status,
              response: errorBody('Invalid API key', 'UNAUTHENTICATED'),
            ),
          );
          expect(e.reason, ServiceFailureReason.unauthorized);
          expect(e.message, 'Invalid API key');
          expect(e.unknownField, isFalse);
        },
      );
    }

    test('FORBIDDEN in a 4xx body is forbidden', () async {
      final e = await failure(
        CapturingHttpAdapter(
          statusCode: 403,
          response: errorBody('Missing permission', 'FORBIDDEN'),
        ),
      );
      expect(e.forbidden, isTrue);
      expect(e.message, 'Missing permission');
    });

    test(
      'a 5xx with a GraphQL body keeps serverError and the message',
      () async {
        final e = await failure(
          CapturingHttpAdapter(
            statusCode: 500,
            response: errorBody('Docker socket unavailable', 'INTERNAL'),
          ),
        );
        expect(e.reason, ServiceFailureReason.serverError);
        expect(e.message, 'Docker socket unavailable');
        expect(e.unknownField, isFalse);
      },
    );

    test('a 5xx body as a JSON string is read too', () async {
      final e = await failure(
        CapturingHttpAdapter(
          statusCode: 500,
          response: '{"errors":[{"message":"Boom","extensions":{"code":"X"}}]}',
        ),
      );
      expect(e.reason, ServiceFailureReason.serverError);
      expect(e.message, 'Boom');
    });

    test('a non-JSON 400 still classifies by its status', () async {
      final e = await failure(
        CapturingHttpAdapter(statusCode: 400, response: 'Bad Request'),
      );
      expect(e.code, isNull);
      expect(e.unknownField, isFalse);
      expect(e.reason, isNot(ServiceFailureReason.unauthorized));
      expect(e.cause, isA<DioException>());
    });

    test('a non-JSON 502 keeps the status classification', () async {
      final e = await failure(
        CapturingHttpAdapter(
          statusCode: 502,
          response: '<html>Bad gateway</html>',
        ),
      );
      expect(e.reason, classifyConnectionFailure(e.cause));
      expect(e.unknownField, isFalse);
      expect(e.code, isNull);
    });

    test('the same reading applies to the metrics document', () async {
      final e = await failure(
        CapturingHttpAdapter(
          statusCode: 400,
          response: errorBody(
            'Cannot query field "metrics" on type "Query".',
            'GRAPHQL_VALIDATION_FAILED',
          ),
        ),
        metrics: true,
      );
      expect(e.unknownField, isTrue);
    });
  });

  group('UnraidClient.getMetrics', () {
    Map<String, dynamic> metrics({
      Object? cpu = 12.5,
      Object? total = 68719476736,
      Object? available = 42000000000,
      Object? percent = 38.9,
    }) => {
      'data': {
        'metrics': {
          'cpu': {'percentTotal': cpu},
          'memory': {
            'total': total,
            'available': available,
            'percentTotal': percent,
          },
        },
      },
    };

    test('sends the metrics document, CPU and memory only', () async {
      final adapter = CapturingHttpAdapter(response: metrics());
      await _client(adapter).getMetrics();
      final query = (adapter.lastBody as Map)['query'] as String;
      expect(query, contains('metrics {'));
      expect(query, isNot(contains('network')));
      expect(query, isNot(contains('temperature')));
    });

    test(
      'parses numbers, and memory in use is total minus available',
      () async {
        final m = await _client(
          CapturingHttpAdapter(response: metrics()),
        ).getMetrics();
        expect(m.cpuPercent, 12.5);
        expect(m.memoryPercent, 38.9);
        expect(m.memoryTotal, 68719476736);
        expect(m.memoryUsed, 68719476736 - 42000000000);
      },
    );

    test('BigInts that arrive as strings are read', () async {
      final m = await _client(
        CapturingHttpAdapter(
          response: metrics(
            total: '68719476736',
            available: '42000000000',
            cpu: '7',
            percent: '38.9',
          ),
        ),
      ).getMetrics();
      expect(m.cpuPercent, 7);
      expect(m.memoryUsed, 68719476736 - 42000000000);
      expect(m.memoryTotal, 68719476736);
    });

    test('a total of 0 gives no memory figure, not 0%', () async {
      final m = await _client(
        CapturingHttpAdapter(
          response: metrics(total: 0, available: 0, percent: 0),
        ),
      ).getMetrics();
      expect(m.memoryPercent, isNull);
      expect(m.memoryUsed, isNull);
      expect(m.memoryTotal, isNull);
      expect(m.cpuPercent, 12.5);
    });

    test('available above total gives no memory in use', () async {
      final m = await _client(
        CapturingHttpAdapter(response: metrics(total: 100, available: 200)),
      ).getMetrics();
      expect(m.memoryUsed, isNull);
      expect(m.memoryTotal, isNull);
    });

    for (final bad in [-1, 100.5, 250, 'NaN']) {
      test('a percentage of $bad is no figure', () async {
        final m = await _client(
          CapturingHttpAdapter(
            response: metrics(cpu: bad, percent: bad),
          ),
        ).getMetrics();
        expect(m.cpuPercent, isNull);
        expect(m.memoryPercent, isNull);
      });
    }

    test('missing blocks give an empty reading, never zeros', () async {
      final m = await _client(
        CapturingHttpAdapter(response: {'data': <String, dynamic>{}}),
      ).getMetrics();
      expect(m.cpuPercent, isNull);
      expect(m.memoryPercent, isNull);
      expect(m.memoryUsed, isNull);
      expect(m.memoryTotal, isNull);
    });
  });
}
