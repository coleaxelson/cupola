/// What Lidarr's artist editor does and does not say, and what the client
/// makes of it.
///
/// The editor (`PUT` and `DELETE /api/v1/artist/editor`) validates the whole
/// set before it saves any and names no artist in a refusal, so a result that
/// says which artist was refused can only come from asking one artist at a
/// time. These tests hold the client to that: one request when Lidarr takes
/// the set, one per artist when it refuses the set, and nothing reported that
/// Lidarr did not say.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_bulk.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// Lidarr, as far as the editor and the command queue go: it refuses a
/// request for the ids in [invalid] with a 400 that names a property and no
/// artist, as `ArtistEditorController` does, and a command for the ids in
/// [refusedCommands] with a message.
class _Lidarr implements HttpClientAdapter {
  _Lidarr({
    this.invalid = const {},
    this.refusedCommands = const {},
    this.statusForAll,
    this.dark = false,
  });

  /// An editor request that holds one of these is refused as a whole.
  final Set<int> invalid;
  final Set<int> refusedCommands;

  /// Every request answers with this status.
  final int? statusForAll;

  /// Nothing answers.
  final bool dark;

  /// `method path ids` of every request, in the order they arrived.
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];

  var _inFlight = 0;
  var widest = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = requestStream == null
        ? ''
        : utf8.decode((await requestStream.toList()).expand((c) => c).toList());
    final body = raw.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final ids = (body['artistIds'] as List?)?.cast<int>() ?? const <int>[];
    requests.add('${options.method} ${options.uri.path} $ids');
    bodies.add(body);

    _inFlight++;
    widest = widest < _inFlight ? _inFlight : widest;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _inFlight--;

    if (dark) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    }
    if (statusForAll != null) return _reply(statusForAll!, {'message': 'no'});
    if (options.uri.path.endsWith('/command')) {
      return refusedCommands.contains(body['artistId'])
          ? _reply(400, {'message': 'Artist ${body['artistId']} is busy'})
          : _reply(201, {'id': 1});
    }
    final refused = ids.where(invalid.contains).toList();
    if (refused.isNotEmpty) {
      return _reply(400, [
        {
          'propertyName': 'RootFolderPath',
          'errorMessage': 'The folder for ${refused.first} is not reachable',
        },
      ]);
    }
    return _reply(options.method == 'PUT' ? 202 : 200, <String, dynamic>{});
  }

  ResponseBody _reply(int status, Object body) => ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    },
  );
}

LidarrService _service(_Lidarr lidarr) {
  final client = ApiClient(baseUrl: 'https://lidarr.test', apiKey: 'k');
  client.dio.httpClientAdapter = lidarr;
  return LidarrService(client);
}

void main() {
  group('LidarrArtistEdit', () {
    test('sends only what was chosen', () {
      expect(const LidarrArtistEdit(monitorNewItems: 'none').fields, {
        'monitorNewItems': 'none',
      });
      expect(
        const LidarrArtistEdit(
          monitored: false,
          qualityProfileId: 2,
          metadataProfileId: 3,
        ).fields,
        {'monitored': false, 'qualityProfileId': 2, 'metadataProfileId': 3},
      );
    });

    test('an edit that sets nothing is empty', () {
      expect(const LidarrArtistEdit().isEmpty, isTrue);
      expect(const LidarrArtistEdit(monitored: false).isEmpty, isFalse);
    });

    test('an artist reads its metadata profile', () {
      final artist = LidarrArtist.fromJson({
        'id': 1,
        'artistName': 'Elbow',
        'qualityProfileId': 1,
        'metadataProfileId': 4,
      });
      expect(artist.metadataProfileId, 4);
      expect(
        LidarrArtist.fromJson({'id': 2}).metadataProfileId,
        isNull,
        reason: 'a record that does not say',
      );
    });
  });

  group('updateArtistsInBulk', () {
    test('is one editor request for the whole set, with only the fields '
        'chosen', () async {
      final lidarr = _Lidarr();

      final result = await _service(
        lidarr,
      ).updateArtistsInBulk([1, 2, 3], const LidarrArtistEdit(monitored: true));

      expect(lidarr.requests, ['PUT /api/v1/artist/editor [1, 2, 3]']);
      expect(lidarr.bodies.single, {
        'artistIds': [1, 2, 3],
        'monitored': true,
      });
      expect(result.done, [1, 2, 3]);
      expect(result.refused, isEmpty);
    });

    test('a refusal of the set is followed by one request per artist, and '
        'the artist refused is the one Lidarr refused', () async {
      final lidarr = _Lidarr(invalid: {2});

      final result = await _service(lidarr).updateArtistsInBulk([
        1,
        2,
        3,
      ], const LidarrArtistEdit(qualityProfileId: 9));

      // The set, which Lidarr refused without saving any of it, then each
      // artist through the same editor with its own id.
      expect(lidarr.requests.first, 'PUT /api/v1/artist/editor [1, 2, 3]');
      expect(lidarr.requests.skip(1).toList()..sort(), [
        'PUT /api/v1/artist/editor [1]',
        'PUT /api/v1/artist/editor [2]',
        'PUT /api/v1/artist/editor [3]',
      ]);
      for (final body in lidarr.bodies) {
        expect(body['qualityProfileId'], 9);
      }
      expect(result.done, [1, 3]);
      expect(result.refused.keys, [2]);
      expect(
        failureServiceMessage(result.refused[2]),
        'The folder for 2 is not reachable',
        reason: 'in Lidarr’s own words',
      );
    });

    test('an artist refused alone is that artist’s refusal, in one '
        'request', () async {
      final lidarr = _Lidarr(invalid: {5});

      final result = await _service(
        lidarr,
      ).updateArtistsInBulk([5], const LidarrArtistEdit(monitored: false));

      expect(lidarr.requests, hasLength(1));
      expect(result.done, isEmpty);
      expect(result.refused.keys, [5]);
    });

    test('a failure that is no artist’s is thrown, and nothing is asked '
        'artist by artist', () async {
      for (final status in [401, 403, 404, 500, 503]) {
        final lidarr = _Lidarr(statusForAll: status);
        await expectLater(
          _service(lidarr).updateArtistsInBulk([
            1,
            2,
          ], const LidarrArtistEdit(monitored: true)),
          throwsA(isA<DioException>()),
          reason: '$status',
        );
        expect(lidarr.requests, hasLength(1), reason: '$status');
      }
    });

    test('nothing answering is thrown, not reported as every artist '
        'refused', () async {
      final lidarr = _Lidarr(dark: true);

      await expectLater(
        _service(lidarr).updateArtistsInBulk([
          1,
          2,
          3,
        ], const LidarrArtistEdit(monitored: true)),
        throwsA(isA<DioException>()),
      );
      expect(lidarr.requests, hasLength(1));
    });

    test(
      'asks a few artists at a time when it has to ask one by one',
      () async {
        final lidarr = _Lidarr(invalid: {1});

        final result = await _service(lidarr).updateArtistsInBulk([
          for (var id = 1; id <= 12; id++) id,
        ], const LidarrArtistEdit(monitored: true));

        expect(result.done, hasLength(11));
        expect(result.refused.keys, [1]);
        expect(lidarr.widest, lessThanOrEqualTo(4));
        expect(lidarr.widest, greaterThan(1), reason: 'not one at a time');
      },
    );
  });

  group('removeArtistsInBulk', () {
    test('is one delete for the set, with the removal’s two choices', () async {
      final lidarr = _Lidarr();

      final result = await _service(lidarr).removeArtistsInBulk(
        [4, 7],
        deleteFiles: true,
        addImportListExclusion: true,
      );

      expect(lidarr.requests, ['DELETE /api/v1/artist/editor [4, 7]']);
      expect(lidarr.bodies.single, {
        'artistIds': [4, 7],
        'deleteFiles': true,
        'addImportListExclusion': true,
      });
      expect(result.done, [4, 7]);
    });

    test('keeps both choices off unless they are asked for', () async {
      final lidarr = _Lidarr();

      await _service(lidarr).removeArtistsInBulk([4]);

      expect(lidarr.bodies.single['deleteFiles'], isFalse);
      expect(lidarr.bodies.single['addImportListExclusion'], isFalse);
    });

    test('a refusal of the set is followed by one delete per artist, each '
        'with the same choices', () async {
      final lidarr = _Lidarr(invalid: {7});

      final result = await _service(
        lidarr,
      ).removeArtistsInBulk([4, 7], deleteFiles: true);

      expect(lidarr.requests.skip(1).toList()..sort(), [
        'DELETE /api/v1/artist/editor [4]',
        'DELETE /api/v1/artist/editor [7]',
      ]);
      expect(
        lidarr.bodies.skip(1).every((b) => b['deleteFiles'] == true),
        true,
      );
      expect(result.done, [4]);
      expect(result.refused.keys, [7]);
    });
  });

  group('searchArtistsInBulk', () {
    test('is one ArtistSearch command per artist, and says which Lidarr '
        'refused', () async {
      final lidarr = _Lidarr(refusedCommands: {2});

      final result = await _service(lidarr).searchArtistsInBulk([1, 2, 3]);

      expect(lidarr.requests, hasLength(3));
      expect(lidarr.bodies.map((b) => b['name']).toSet(), {'ArtistSearch'});
      expect(lidarr.bodies.map((b) => b['artistId']).toList()..sort(), [
        1,
        2,
        3,
      ]);
      expect(result.done, [1, 3]);
      expect(result.refused.keys, [2]);
      expect(failureServiceMessage(result.refused[2]), 'Artist 2 is busy');
    });

    test('a Lidarr that does not answer refuses every artist, each with '
        'its own failure', () async {
      final lidarr = _Lidarr(dark: true);

      final result = await _service(lidarr).searchArtistsInBulk([1, 2]);

      expect(result.done, isEmpty);
      expect(result.refused.keys, [1, 2]);
    });
  });
}
