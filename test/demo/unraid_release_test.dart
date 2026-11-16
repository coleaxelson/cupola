import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The demo's Unraid answers `metrics` and `docker { containers }`, which the
/// Unraid API has only from Unraid 7.2.0 (API 4.25.3): the release it
/// declares has to be one that has them.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile);
    addTearDown(network.install());
  });

  Future<Map<String, dynamic>> graphql(String query) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        'POST',
        Uri.parse('${WorldHosts.unraid}/graphql'),
      );
      request.headers.set('x-api-key', worldKey('unraid'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'query': query}));
      final response = await request.close();
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  test(
    'declares a release that has the API it answers: 7.2.0 or later',
    () async {
      final metrics = await graphql(
        'query { metrics { cpu { percentTotal } } }',
      );
      expect((metrics['data'] as Map)['metrics'], isNotNull);

      final info = await graphql('query { info { os { release } } }');
      final release =
          (((info['data'] as Map)['info'] as Map)['os'] as Map)['release']
              as String;
      final parts = release.split('.').map(int.parse).toList();
      final since72 =
          parts[0] > 7 || (parts[0] == 7 && (parts[1] > 2 || parts[1] == 2));
      expect(since72, isTrue, reason: 'Unraid $release has no metrics');
      expect(release, '7.2.0');
    },
  );
}
