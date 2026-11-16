import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/world/profiles.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';

/// Seerr's problem reports once the world lives: one report filed, answered,
/// resolved or deleted reads the same on the title's page, in the list and in
/// the count, for the operator and for Anna, and each route answers in
/// Seerr's own shape and refusals.
void main() {
  late ProfileNetwork network;

  /// The operator (API key) or Anna (her saved session) calls Seerr.
  Future<(int, Object?)> send(
    String method,
    String path, {
    Object? json,
    bool asAnna = false,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${WorldHosts.seerr}$path'),
      );
      if (asAnna) {
        request.headers.set(
          'cookie',
          'connect.sid=${network.seerrSessionOf(WorldIds.seerr)}',
        );
      } else {
        request.headers.set('x-api-key', worldKey(WorldIds.seerr));
      }
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (response.statusCode, body.isEmpty ? null : jsonDecode(body));
    } finally {
      client.close();
    }
  }

  /// Starts the world of [profile], living unless [live] is false.
  void begin(ConfigProfile profile, {bool live = true}) {
    network = ProfileNetwork(profile);
    if (live) network.live();
    addTearDown(network.install());
  }

  // Both callers reach the one Seerr: the profile gives Anna a session and
  // the permission to report; the operator reads with the key.
  final reporter = Profiles.p2.withSeerrPermissions(
    SeerrPermission.request.value | SeerrPermission.createIssues.value,
  );

  const sintel = WorldTitles.sintel;

  Future<List<Map>> list(String query, {bool asAnna = false}) async {
    final (_, body) = await send('GET', '/api/v1/issue?$query', asAnna: asAnna);
    return [for (final i in (body as Map)['results'] as List) i as Map];
  }

  Future<List<Map>> onTitle(WorldTitle title, {bool asAnna = false}) async {
    final (_, body) = await send(
      'GET',
      '/api/v1/${title.isSeries ? 'tv' : 'movie'}/${title.tmdbId}',
      asAnna: asAnna,
    );
    return [
      for (final i in ((body as Map)['mediaInfo'] as Map)['issues'] as List)
        i as Map,
    ];
  }

  test('a report Anna files shows on the title, in her list and the '
      'count, and the operator sees it too', () async {
    begin(reporter);
    final (status, made) = await send(
      'POST',
      '/api/v1/issue',
      asAnna: true,
      json: {
        'issueType': 3,
        'message': 'Subtitles are late',
        'mediaId': sintel.tmdbId,
      },
    );
    expect(status, 201);
    made as Map;
    expect(made['issueType'], 3);
    expect(made['status'], 1);
    expect(made['problemSeason'], 0);
    expect((made['createdBy'] as Map)['id'], WorldSeerrUsers.anna.id);
    final first = (made['comments'] as List).single as Map;
    expect(first['message'], 'Subtitles are late');
    expect((first['user'] as Map)['id'], WorldSeerrUsers.anna.id);
    final id = made['id'];

    // Seerr's own filtered shape on the title: no comments, season or
    // episode.
    final shown = (await onTitle(sintel, asAnna: true)).single;
    expect(shown['id'], id);
    expect(shown.containsKey('comments'), isFalse);
    expect(shown.containsKey('problemEpisode'), isFalse);
    expect((await onTitle(sintel)).map((i) => i['id']), [id]);

    // Her list is her own; the operator's holds hers and the world's.
    expect((await list('filter=open', asAnna: true)).map((i) => i['id']), [
      id,
      1,
    ]);
    final operator = await list('filter=open&sort=added');
    expect(operator.map((i) => i['id']), [id, 1]);
    // The list does not join the authors of the replies.
    expect(
      (operator.first['comments'] as List).single,
      isNot(contains('user')),
    );

    final (_, count) = await send('GET', '/api/v1/issue/count');
    expect(count, containsPair('total', 2));
    expect(count, containsPair('subtitles', 1));
    expect(count, containsPair('open', 2));
  });

  test('a resolve shows on the title, the list and the count at once, and '
      'a reopen takes it back', () async {
    begin(reporter);
    final (_, made) = await send(
      'POST',
      '/api/v1/issue',
      asAnna: true,
      json: {'issueType': 1, 'message': 'Freezes', 'mediaId': sintel.tmdbId},
    );
    final id = (made as Map)['id'];

    final (resolved, _) = await send(
      'POST',
      '/api/v1/issue/$id/resolved',
      asAnna: true,
    );
    expect(resolved, 200);
    expect((await onTitle(sintel)).single['status'], 2);
    expect((await list('filter=resolved', asAnna: true)).map((i) => i['id']), [
      id,
    ]);
    expect((await list('filter=open')).map((i) => i['id']), [1]);
    final (_, count) = await send('GET', '/api/v1/issue/count');
    expect(count, containsPair('closed', 1));
    expect(count, containsPair('open', 1));

    await send('POST', '/api/v1/issue/$id/open');
    expect((await onTitle(sintel)).single['status'], 1);
  });

  test('a reply, an edit and a delete of it change the conversation', () async {
    begin(reporter);
    final (_, before) = await send('GET', '/api/v1/issue/1', asAnna: true);
    expect((before as Map)['comments'], hasLength(3));

    final (status, _) = await send(
      'POST',
      '/api/v1/issue/1/comment',
      json: {'message': 'Trying a re-encode'},
    );
    expect(status, 200);
    final (_, after) = await send('GET', '/api/v1/issue/1', asAnna: true);
    final comments = (after as Map)['comments'] as List;
    expect(comments, hasLength(4));
    final reply = comments.last as Map;
    expect((reply['user'] as Map)['id'], WorldSeerrUsers.admin.id);

    // Anna edits her own reply, not the operator's.
    final (edited, body) = await send(
      'PUT',
      '/api/v1/issueComment/3',
      asAnna: true,
      json: {'message': 'Living room TV, Jellyfin app'},
    );
    expect(edited, 200);
    expect((body as Map)['message'], 'Living room TV, Jellyfin app');
    final (refused, _) = await send(
      'PUT',
      '/api/v1/issueComment/${reply['id']}',
      asAnna: true,
      json: {'message': 'x'},
    );
    expect(refused, 401);

    final (deleted, _) = await send(
      'DELETE',
      '/api/v1/issueComment/${reply['id']}',
    );
    expect(deleted, 204);
    final (_, last) = await send('GET', '/api/v1/issue/1');
    expect((last as Map)['comments'], hasLength(3));
    expect(
      ((last['comments'] as List)[2] as Map)['message'],
      'Living room TV, Jellyfin app',
    );
    expect((await send('DELETE', '/api/v1/issueComment/999')).$1, 404);
  });

  test(
    'a delete takes the report off the title, the list and the count',
    () async {
      begin(reporter);
      final (_, made) = await send(
        'POST',
        '/api/v1/issue',
        asAnna: true,
        json: {'issueType': 4, 'message': 'Odd', 'mediaId': sintel.tmdbId},
      );
      final id = (made as Map)['id'];
      // Hers, with nobody else's reply: she may take it back.
      expect((await send('DELETE', '/api/v1/issue/$id', asAnna: true)).$1, 204);
      expect(await onTitle(sintel), isEmpty);
      expect((await list('filter=all')).map((i) => i['id']), [1]);
      expect((await send('GET', '/api/v1/issue/1')).$1, 200);
      expect((await send('GET', '/api/v1/issue/$id')).$1, 404);
      final (_, count) = await send('GET', '/api/v1/issue/count');
      expect(count, containsPair('total', 1));
    },
  );

  test(
    'a series report keeps its season and episode; a movie never does',
    () async {
      begin(reporter);
      const show = WorldTitles.cosmosLaundromat;
      final (status, made) = await send(
        'POST',
        '/api/v1/issue',
        json: {
          'issueType': 2,
          'message': 'No sound',
          'mediaId': show.tmdbId,
          'problemSeason': 1,
          'problemEpisode': 4,
        },
      );
      expect(status, 201);
      expect(made, containsPair('problemSeason', 1));
      expect(made, containsPair('problemEpisode', 4));
      final (_, movie) = await send(
        'POST',
        '/api/v1/issue',
        json: {
          'issueType': 1,
          'message': 'Grain',
          'mediaId': sintel.tmdbId,
          'problemSeason': 2,
        },
      );
      expect(movie, containsPair('problemSeason', 0));
    },
  );

  test('Seerr\'s refusals: the permission, somebody else\'s issue, a title '
      'it does not hold', () async {
    begin(reporter);
    // She holds CREATE_ISSUES only: one report of Anna's is hers to read, the
    // list is limited to her own, and the operator's reply is not hers to
    // delete.
    final (_, made) = await send(
      'POST',
      '/api/v1/issue',
      json: {'issueType': 1, 'message': 'Mine', 'mediaId': sintel.tmdbId},
    );
    final operatorsId = (made as Map)['id'];
    expect((await list('filter=all', asAnna: true)).map((i) => i['id']), [1]);
    expect(
      (await send('GET', '/api/v1/issue/$operatorsId', asAnna: true)).$1,
      403,
    );
    expect(
      (await send(
        'POST',
        '/api/v1/issue/$operatorsId/resolved',
        asAnna: true,
      )).$1,
      401,
    );
    expect(
      (await send('DELETE', '/api/v1/issue/1', asAnna: true)).$1,
      401,
      reason: 'issue 1 has three replies',
    );
    // Without the title on the server, Seerr's 404.
    final (status, body) = await send(
      'POST',
      '/api/v1/issue',
      json: {'issueType': 1, 'message': 'Lost', 'mediaId': 999999},
    );
    expect(status, 404);
    expect(body, containsPair('message', 'Media does not exist.'));
    // Nothing of it is kept in a world that does not live.
    expect((await send('POST', '/api/v1/issue', json: {})).$1, 400);
  });

  test('a requester without any issue permission reads no reports and is '
      'refused the route', () async {
    begin(Profiles.p2.withSeerrPermissions(SeerrPermission.request.value));
    expect(await onTitle(sintel, asAnna: true), isEmpty);
    expect(
      (await send(
        'POST',
        '/api/v1/issue',
        asAnna: true,
        json: {'issueType': 1, 'message': 'x', 'mediaId': sintel.tmdbId},
      )).$1,
      403,
    );
  });

  test('a world that does not live answers a report and forgets it', () async {
    begin(Profiles.p1, live: false);
    final (status, _) = await send(
      'POST',
      '/api/v1/issue',
      json: {'issueType': 1, 'message': 'x', 'mediaId': sintel.tmdbId},
    );
    expect(status, 201);
    expect((await list('filter=all')).map((i) => i['id']), [1]);
  });
}
