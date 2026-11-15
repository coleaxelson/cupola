import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/fakes/arr_fakes.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The shelf of made-up artists is the demo's alone. The profiles' Lidarr, which
/// every test and the testlab read, holds what it held before the shelf: the
/// world's own artist and its four albums, so a figure folded over it (the
/// stack card's albums, a count of artists) does not move when the demo's wall
/// is given something to scroll.
void main() {
  Future<List<Object?>> list(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as List<Object?>;
    } finally {
      client.close();
    }
  }

  const lidarr = '${WorldHosts.lidarr}/api/v1';

  test('a profile read as written has one artist and four albums', () async {
    final network = ProfileNetwork(Profiles.p1);
    addTearDown(network.install());

    expect(await list('$lidarr/artist'), hasLength(1));
    expect(await list('$lidarr/album'), hasLength(4));
  });

  test('the demo, once the world lives, has the shelf as well', () async {
    final network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());

    expect(await list('$lidarr/artist'), hasLength(LidarrFake.shelfCount + 1));
    expect(
      (await list('$lidarr/album')).length,
      greaterThan(4),
      reason: 'the shelf has albums',
    );
  });
}
