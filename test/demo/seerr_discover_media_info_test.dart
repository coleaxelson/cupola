import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The demo's Seerr answers Discover's lists as Seerr does: each title
/// carries the `mediaInfo` the server holds of it, so `Hide what I have` has
/// something to hide and the posters have a state to wear.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile);
    addTearDown(network.install());
  });

  Future<Map<String, dynamic>> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('${WorldHosts.seerr}$path'),
      );
      request.headers.set('x-api-key', worldKey(WorldIds.seerr));
      final response = await request.close();
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// The titles of [path]'s results, each with the status the list gives it
  /// and the one the title's own page gives.
  Future<List<({String name, int? listed, int? held})>> statuses(
    String path,
  ) async {
    final page = await get(path);
    return [
      for (final raw in page['results'] as List)
        if ((raw as Map)['mediaType'] != 'person')
          (
            name: (raw['title'] ?? raw['name']) as String,
            listed: (raw['mediaInfo'] as Map?)?['status'] as int?,
            held:
                ((await get(
                          '/api/v1/${raw['mediaType']}/${raw['id']}',
                        ))['mediaInfo']
                        as Map?)?['status']
                    as int?,
          ),
    ];
  }

  for (final path in const [
    '/api/v1/discover/trending',
    '/api/v1/discover/movies',
    '/api/v1/discover/movies/upcoming',
    '/api/v1/discover/tv',
    '/api/v1/discover/tv/upcoming',
    '/api/v1/search?query=e',
  ]) {
    test('$path lists each title with the state the server holds', () async {
      final titles = await statuses(path);
      expect(titles, isNotEmpty);
      for (final title in titles) {
        expect(title.listed, title.held, reason: title.name);
      }
    });
  }

  test('what the server has is there to hide, and what it lacks is not', () {
    return statuses('/api/v1/discover/movies').then((titles) {
      expect(
        titles.where((t) => t.listed == 5 || t.listed == 4),
        isNotEmpty,
        reason: 'some movie is on the server',
      );
      expect(
        titles.where((t) => t.listed != 5 && t.listed != 4),
        isNotEmpty,
        reason: 'some movie is only asked for or unknown',
      );
    });
  });
}
