import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fake_api_client.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('lidarrServiceProvider', () {
    test('throws when Lidarr is not configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      expect(() => container.read(lidarrServiceProvider), throwsException);
    });

    test('returns a service when Lidarr is configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              lidarrUrl: 'https://lidarr.example.com',
              lidarrApiKey: 'key',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(lidarrServiceProvider), isA<LidarrService>());
    });
  });

  group('LidarrService', () {
    late FakeApiClient client;
    late LidarrService service;

    setUp(() {
      client = FakeApiClient();
      service = LidarrService(client);
    });

    test('uses the Lidarr API config', () {
      expect(service.config.apiVersion, 'v1');
      expect(service.config.sortKey, 'releaseDate');
    });

    test('getArtists fetches and maps artists', () async {
      client.getResponseData = [
        _artistJson(id: 1, artistName: 'The National'),
        _artistJson(id: 2, artistName: 'Mogwai'),
      ];

      final artists = await service.getArtists();

      expect(client.lastGetPath, '/api/v1/artist');
      expect(artists, hasLength(2));
      expect(artists.first.artistName, 'The National');
      expect(artists.last.id, 2);
    });

    test('getArtists returns empty list on error', () async {
      client.getException = Exception('boom');

      final artists = await service.getArtists();

      expect(artists, isEmpty);
    });

    test('getArtistById returns a typed artist on success', () async {
      client.getResponseData = _artistJson(id: 5, artistName: 'Band');

      final artist = await service.getArtistById(5);

      expect(client.lastGetPath, '/api/v1/artist/5');
      expect(artist?.id, 5);
      expect(artist?.artistName, 'Band');
    });

    test('getArtistById returns null on error', () async {
      client.getException = Exception('boom');

      final artist = await service.getArtistById(5);

      expect(artist, isNull);
    });

    test('getAlbums fetches albums for the artist', () async {
      client.getResponseData = [
        _albumJson(id: 10, title: 'Album 1', monitored: true),
        _albumJson(id: 11, title: 'Album 2', monitored: false),
      ];

      final albums = await service.getAlbums(7);

      expect(client.lastGetPath, '/api/v1/album');
      expect(client.lastGetQueryParameters, {'artistId': 7});
      expect(albums, hasLength(2));
      expect(albums.first.title, 'Album 1');
      expect(albums.last.monitored, isFalse);
    });

    test('getTracks fetches tracks for the album', () async {
      client.getResponseData = [
        _trackJson(id: 20, title: 'Track 1', duration: 180000),
      ];

      final tracks = await service.getTracks(10);

      expect(client.lastGetPath, '/api/v1/track');
      expect(client.lastGetQueryParameters, {'albumId': 10});
      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Track 1');
      expect(tracks.single.duration, 180000);
    });

    test('searchArtist posts the ArtistSearch command', () async {
      await service.searchArtist(1);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {'name': 'ArtistSearch', 'artistId': 1});
    });

    test('searchAlbums posts the AlbumSearch command', () async {
      await service.searchAlbums([10, 11]);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {
        'name': 'AlbumSearch',
        'albumIds': [10, 11],
      });
    });

    test('getQueue asks for the artist and the album it will print', () async {
      client.getResponseData = const [];

      await service.getQueue();

      expect(client.lastGetPath, '/api/v1/queue');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    test('getHistoryPage asks for the artist and the album', () async {
      client.getResponseData = const {'records': []};

      await service.getHistoryPage();

      expect(client.lastGetPath, '/api/v1/history');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    // The embeds hang off the **page** primitive so the record-only spelling
    // inherits them; hung off `getHistory` instead, every caller that reaches
    // for the envelope's total, which is every caller that prints a figure,
    // would get records with no `album` to fold on.
    test('getHistory inherits the embeds through the page primitive', () async {
      client.getResponseData = const {'records': []};

      await service.getHistory();

      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    test('a caller may still add its own history parameters', () async {
      client.getResponseData = const {'records': []};

      await service.getHistoryPage(
        queryParameters: const {
          'sortKey': 'date',
          'sortDirection': 'ascending',
        },
      );

      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['sortKey'], 'date');
      expect(client.lastGetQueryParameters?['sortDirection'], 'ascending');
    });

    // The backlog clause on the Lidarr Overview counts distinct
    // `arrArtistName(row)` over the wanted page to say "across 6 artists", and
    // `artist` only rides a `wanted/missing` record when the request asks for
    // it. Without this the set is always empty on a real server and the clause
    // is dropped every time: honest, but a promise the code could never keep.
    test('getMissingPage asks for the artist the backlog counts', () async {
      client.getResponseData = const {'records': [], 'totalRecords': 0};

      await service.getMissingPage();

      expect(client.lastGetPath, '/api/v1/wanted/missing');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
    });

    test('getCutoffPage asks for it too', () async {
      client.getResponseData = const {'records': [], 'totalRecords': 0};

      await service.getCutoffPage();

      expect(client.lastGetPath, '/api/v1/wanted/cutoff');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
    });

    // Activity's Wanted tab reads the walks, not the pages, and its music rows
    // print `arrArtistName` under the title.
    test('the wanted walks ask for the artist as well', () async {
      client.getResponseData = const {'records': [], 'totalRecords': 0};

      await service.getAllMissing();
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);

      await service.getAllCutoff();
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
    });

    test('the wanted walk with its account asks for the artist, and a caller '
        'may leave it out', () async {
      client.getResponseData = const {'records': [], 'totalRecords': 0};

      await service.getAllMissingPage();
      expect(client.lastGetPath, '/api/v1/wanted/missing');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);

      // The Wanted chip reads ids alone.
      await service.getAllMissingPage(
        queryParameters: const {'includeArtist': false},
      );
      expect(client.lastGetQueryParameters?['includeArtist'], isFalse);
    });

    test('the wanted walk says when it stopped before the end', () async {
      // Fifty pages of 250, and the server still names more.
      client.getResponseData = {
        'records': [
          for (var id = 0; id < 250; id++) {'id': id, 'artistId': id % 7},
        ],
        'totalRecords': 30000,
      };

      final page = await service.getAllMissingPage();

      expect(page.cutShort, isTrue);
      expect(page.total, 30000);
      expect(page.records, hasLength(12500));
    });

    test('the wanted walk that reaches the end is whole', () async {
      client.getResponseData = const {
        'records': [
          {'id': 1, 'artistId': 4},
        ],
        'totalRecords': 1,
      };

      final page = await service.getAllMissingPage();

      expect(page.cutShort, isFalse);
    });

    test('a caller may still add its own wanted parameters', () async {
      client.getResponseData = const {'records': [], 'totalRecords': 0};

      await service.getMissingPage(
        queryParameters: const {'sortDirection': 'ascending'},
      );

      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['sortDirection'], 'ascending');
    });

    test('getReleases passes artistId query params', () async {
      client.getResponseData = [
        {'title': 'Artist Release'},
      ];

      final releases = await service.getReleases(artistId: 1);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(releases, hasLength(1));
    });

    test('getReleases passes albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(albumId: 10);

      expect(client.lastGetQueryParameters, {'albumId': 10});
    });

    test('getReleases passes both artistId and albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(artistId: 1, albumId: 10);

      expect(client.lastGetQueryParameters, {'artistId': 1, 'albumId': 10});
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.getReleases(artistId: 1, cancelToken: cancelToken);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('grabRelease posts the release payload', () async {
      await service.grabRelease(guid: 'guid-123', indexerId: 9);

      expect(client.lastPostPath, '/api/v1/release');
      expect(client.lastPostData, {'guid': 'guid-123', 'indexerId': 9});
    });

    test('search is not asked for an empty term', () async {
      expect(await service.search('  '), isEmpty);
      expect(client.getCallCount, 0);
    });

    test(
      'search sends the term as typed and reads artists and albums',
      () async {
        client.getResponseData = [
          {
            'id': 1,
            'foreignId': 'mb-artist',
            'artist': _artistJson(id: 0, artistName: 'Elbow'),
            'album': null,
          },
          {
            'id': 2,
            'foreignId': 'mb-album',
            'artist': null,
            'album': {
              ..._albumJson(id: 0, title: 'Elephant', monitored: false),
              'foreignAlbumId': 'mb-album',
              'albumType': 'Album',
              'releaseDate': '2003-04-14T00:00:00Z',
              'artist': {
                ..._artistJson(id: 0, artistName: 'The White Stripes'),
                'foreignArtistId': 'mb-stripes',
              },
            },
          },
        ];

        final hits = await service.search('el & friends');

        expect(client.lastGetPath, '/api/v1/search');
        expect(client.lastGetQueryParameters, {'term': 'el & friends'});
        expect(hits, hasLength(2));
        expect((hits.first as LidarrArtistHit).artist.artistName, 'Elbow');
        final album = hits.last as LidarrAlbumHit;
        expect(album.album.title, 'Elephant');
        expect(album.album.albumType, 'Album');
        expect(album.album.year, '2003');
        expect(album.artist.foreignArtistId, 'mb-stripes');
        expect(album.raw['foreignAlbumId'], 'mb-album');
      },
    );

    test('search skips a row that is neither an artist nor an album', () async {
      client.getResponseData = [
        {'id': 1},
        {'id': 2, 'artist': _artistJson(id: 5, artistName: 'Mogwai')},
      ];

      final hits = await service.search('mog');

      expect(hits.single, isA<LidarrArtistHit>());
    });

    test('search forwards the cancel token', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.search('el', cancelToken: cancelToken);

      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('search lets a failure reach the caller, never an empty list', () {
      client.getException = Exception('boom');

      expect(service.search('el'), throwsException);
    });

    group('when the catalog did not answer', () {
      DioException failure(int status, Object? body) => DioException(
        requestOptions: RequestOptions(path: '/api/v1/search'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v1/search'),
          statusCode: status,
          data: body,
        ),
      );

      test('a 503 that names LidarrAPI is the catalog, not Lidarr', () {
        client.getException = failure(503, {
          'message':
              "Search for 'elbo' failed. Unable to communicate with LidarrAPI.",
        });

        expect(
          service.search('elbo'),
          throwsA(
            isA<LidarrCatalogUnavailable>().having(
              (e) => e.message,
              'message',
              contains('LidarrAPI'),
            ),
          ),
        );
      });

      test('a 503 with no word of it is Lidarr not answering', () {
        client.getException = failure(503, 'Service Unavailable');

        expect(service.search('elbo'), throwsA(isA<DioException>()));
      });

      test('a 500 naming it is an ordinary failure', () {
        client.getException = failure(500, {'message': 'LidarrAPI exploded'});

        expect(service.search('elbo'), throwsA(isA<DioException>()));
      });
    });

    test('setAlbumsMonitored puts the ids and the state', () async {
      await service.setAlbumsMonitored([4, 5], true);

      expect(client.lastPutPath, '/api/v1/album/monitor');
      expect(client.lastPutData, {
        'albumIds': [4, 5],
        'monitored': true,
      });
    });

    test('monitorAndSearchAlbum monitors, then searches', () async {
      await service.monitorAndSearchAlbum(7);

      expect(client.lastPutData, {
        'albumIds': [7],
        'monitored': true,
      });
      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {
        'name': 'AlbumSearch',
        'albumIds': [7],
      });
    });

    test('monitorAndSearchAlbum does not search an album it could not '
        'monitor', () async {
      client.putException = Exception('refused');

      await expectLater(service.monitorAndSearchAlbum(7), throwsException);

      expect(client.postCallCount, 0);
    });

    group('addAlbum', () {
      final raw = {
        ..._albumJson(id: 0, title: 'Elephant', monitored: false),
        'foreignAlbumId': 'mb-album',
        'albumType': 'Album',
        'artist': {
          ..._artistJson(id: 0, artistName: 'The White Stripes'),
          'foreignArtistId': 'mb-stripes',
        },
      };
      final hit = LidarrAlbumHit(
        album: LidarrAlbum.fromJson(raw),
        artist: LidarrArtist.fromJson(
          (raw['artist'] as Map).cast<String, dynamic>(),
        ),
        raw: raw,
      );
      const setup = LidarrNewArtistSetup(
        rootFolderPath: '/music',
        qualityProfileId: 3,
        metadataProfileId: 2,
      );

      test('an artist the library lacks comes in with the album, as the '
          'front end posts it', () async {
        client.postResponseData = {
          'id': 40,
          'artist': {
            ..._artistJson(id: 9, artistName: 'The White Stripes'),
            'foreignArtistId': 'mb-stripes',
          },
        };

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: true,
          newArtist: setup,
        );

        expect(client.lastPostPath, '/api/v1/album');
        final body = client.lastPostData as Map;
        expect(body['monitored'], isTrue);
        expect(body['addOptions'], {'searchForNewAlbum': true});
        expect(body['foreignAlbumId'], 'mb-album');
        final posted = body['artist'] as Map;
        expect(posted['foreignArtistId'], 'mb-stripes');
        expect(posted['rootFolderPath'], '/music');
        expect(posted['qualityProfileId'], 3);
        expect(posted['metadataProfileId'], 2);
        expect(posted['monitored'], isTrue);
        expect(posted['monitorNewItems'], 'none');
        // Only this album is monitored, whatever the profile: Lidarr sets every
        // album unmonitored under `none`, and a non-empty `albumsToMonitor`
        // monitors exactly those.
        expect(posted['addOptions'], {
          'monitor': 'none',
          'albumsToMonitor': ['mb-album'],
          'searchForMissingAlbums': false,
        });
        expect(artist!.id, 9);
        // The search's own row is not changed by the post.
        expect(raw['monitored'], isFalse);
      });

      test('an artist the library holds goes with the album as the library '
          'holds them', () async {
        client.getResponseData = {
          ..._artistJson(id: 7, artistName: 'The White Stripes'),
          'path': '/music/The White Stripes',
          'qualityProfileId': 1,
          'metadataProfileId': 1,
        };
        client.postResponseData = {
          'id': 40,
          'artist': _artistJson(id: 7, artistName: 'The White Stripes'),
        };

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: false,
          libraryArtistId: 7,
        );

        expect(client.lastGetPath, '/api/v1/artist/7');
        final body = client.lastPostData as Map;
        expect(body['addOptions'], {'searchForNewAlbum': false});
        expect((body['artist'] as Map)['path'], '/music/The White Stripes');
        expect((body['artist'] as Map).containsKey('addOptions'), isFalse);
        expect(artist!.id, 7);
      });

      test('an answer without the artist asks Lidarr for them by MusicBrainz '
          'id', () async {
        client.postResponseData = {'id': 40};
        client.getResponseData = [
          _artistJson(id: 12, artistName: 'The White Stripes'),
        ];

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: true,
          newArtist: setup,
        );

        expect(client.lastGetPath, '/api/v1/artist');
        expect(client.lastGetQueryParameters, {'mbId': 'mb-stripes'});
        expect(artist!.id, 12);
      });

      test('an album that was added is added, though the artist cannot be '
          'read after: no artist, and no throw', () async {
        client.postResponseData = {'id': 40};
        client.getException = Exception('Lidarr went quiet');

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: true,
          newArtist: setup,
        );

        expect(client.postCallCount, 1);
        expect(artist, isNull);
      });

      test('an answer and a lookup with no artist id add the album all the '
          'same', () async {
        client.postResponseData = {'id': 40};
        client.getResponseData = const [];

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: true,
          newArtist: setup,
        );

        expect(artist, isNull);
      });

      test('an artist the library holds is the answer when the post says '
          'nothing of them', () async {
        client.getResponseData = {
          ..._artistJson(id: 7, artistName: 'The White Stripes'),
        };
        client.postResponseData = {'id': 40};

        final artist = await service.addAlbum(
          hit,
          searchForNewAlbum: true,
          libraryArtistId: 7,
        );

        expect(artist!.id, 7);
      });

      test('a refusal reaches the caller', () {
        client.postException = Exception('This album has already been added');

        expect(
          service.addAlbum(hit, searchForNewAlbum: true, newArtist: setup),
          throwsException,
        );
      });
    });

    test('getQualityProfiles returns mapped profiles', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'Lossless'},
      ];

      final profiles = await service.getQualityProfiles();

      expect(client.lastGetPath, '/api/v1/qualityprofile');
      expect(profiles, [
        {'id': 1, 'name': 'Lossless'},
      ]);
    });

    test('updateArtistProfile fetches then updates the artist', () async {
      client.getResponseData = _artistJson(
        id: 3,
        artistName: 'Artist',
        qualityProfileId: 1,
      );

      await service.updateArtistProfile(3, 7);

      expect(client.lastGetPath, '/api/v1/artist/3');
      expect(client.lastPutPath, '/api/v1/artist/3');
      expect(client.lastPutData['qualityProfileId'], 7);
      expect(client.lastPutData['artistName'], 'Artist');
    });

    test('getQualityProfilesOrThrow lets a failed read reach the caller', () {
      client.getException = Exception('boom');

      expect(service.getQualityProfilesOrThrow(), throwsException);
      // The degrading read keeps answering `[]`: the add sheet is the one
      // reader that must tell a dark Lidarr from one with no profile.
      expect(service.getQualityProfiles(), completion(isEmpty));
    });

    test('getMetadataProfiles reads the types each profile allows', () async {
      client.getResponseData = [
        {
          'id': 1,
          'name': 'Standard',
          'primaryAlbumTypes': [
            {
              'albumType': {'id': 2, 'name': 'Album'},
              'allowed': true,
            },
            {
              'albumType': {'id': 4, 'name': 'EP'},
              'allowed': true,
            },
            {
              'albumType': {'id': 1, 'name': 'Single'},
              'allowed': false,
            },
          ],
        },
        {'id': 2, 'name': 'None'},
        {'name': 'No id'},
      ];

      final profiles = await service.getMetadataProfiles();

      expect(client.lastGetPath, '/api/v1/metadataprofile');
      // An entry without an id cannot be chosen, so it is not offered.
      expect(profiles.map((p) => p.name), ['Standard', 'None']);
      expect(profiles.first.allowedPrimaryTypes, ['Album', 'EP']);
      expect(profiles.first.typesLine, 'Albums and EPs');
      expect(profiles.last.typesLine, isNull);
    });

    test('getMetadataProfiles throws when Lidarr does not answer', () {
      client.getException = Exception('boom');

      expect(service.getMetadataProfiles(), throwsException);
    });

    test('getRootFolders carries the defaults a new artist is given', () async {
      client.getResponseData = [
        {
          'id': 1,
          'path': '/music',
          'freeSpace': 2100000000000,
          'defaultQualityProfileId': 2,
          'defaultMetadataProfileId': 1,
          'defaultMonitorOption': 'future',
          'defaultNewItemMonitorOption': 'none',
        },
      ];

      final folders = await service.getRootFolders();

      expect(client.lastGetPath, '/api/v1/rootfolder');
      expect(folders.single['defaultMonitorOption'], 'future');
      expect(folders.single['defaultNewItemMonitorOption'], 'none');
    });

    test('deleteArtist sends default delete params', () async {
      await service.deleteArtist(1);

      expect(client.lastDeletePath, '/api/v1/artist/1');
      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': false,
        'addImportListExclusion': false,
      });
    });

    test('deleteArtist sends custom delete params', () async {
      await service.deleteArtist(
        1,
        deleteFiles: true,
        addImportListExclusion: true,
      );

      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': true,
        'addImportListExclusion': true,
      });
    });
  });

  group('LidarrService.addArtist', () {
    late CapturingHttpAdapter adapter;
    late LidarrService service;

    setUp(() {
      adapter = CapturingHttpAdapter(
        response: {
          'id': 12,
          'artistName': 'Elbow',
          'foreignArtistId': 'mbid-elbow',
          'status': 'continuing',
          'monitored': true,
          'images': const [],
        },
      );
      final client = ApiClient(baseUrl: 'https://lidarr.test', apiKey: 'k');
      client.dio.httpClientAdapter = adapter;
      service = LidarrService(client);
    });

    LidarrArtist lookupRow() => LidarrArtist.fromJson({
      'artistName': 'Elbow',
      'foreignArtistId': 'mbid-elbow',
      'status': 'continuing',
      'artistType': 'Group',
      'disambiguation': 'Bury, England',
      'overview': 'English rock band.',
      'images': [
        {'coverType': 'poster', 'remoteUrl': 'https://img.example/elbow.jpg'},
      ],
      'links': [
        {'name': 'allmusic', 'url': 'https://allmusic.example/elbow'},
      ],
    });

    test('posts the lookup row\'s identity with what was chosen', () async {
      final added = await service.addArtist(
        lookupRow(),
        qualityProfileId: 2,
        metadataProfileId: 3,
        rootFolderPath: '/music',
        monitor: 'future',
        monitorNewItems: 'all',
        searchForMissingAlbums: true,
      );

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastUri!.path, '/api/v1/artist');
      expect(adapter.lastBody, {
        'artistName': 'Elbow',
        'foreignArtistId': 'mbid-elbow',
        'images': [
          {'coverType': 'poster', 'remoteUrl': 'https://img.example/elbow.jpg'},
        ],
        'overview': 'English rock band.',
        'artistType': 'Group',
        'disambiguation': 'Bury, England',
        'links': [
          {'name': 'allmusic', 'url': 'https://allmusic.example/elbow'},
        ],
        'qualityProfileId': 2,
        'metadataProfileId': 3,
        'rootFolderPath': '/music',
        'monitored': true,
        'monitorNewItems': 'all',
        'addOptions': {'monitor': 'future', 'searchForMissingAlbums': true},
      });
      // Lidarr's answer is the artist as it now holds it.
      expect(added.id, 12);
      expect(added.artistName, 'Elbow');
    });

    test(
      'Monitor None adds the artist unmonitored and asks for no search',
      () async {
        await service.addArtist(
          lookupRow(),
          qualityProfileId: 1,
          metadataProfileId: 1,
          rootFolderPath: '/music',
          monitor: 'none',
          monitorNewItems: 'none',
          searchForMissingAlbums: false,
        );

        final body = adapter.lastBody as Map;
        expect(body['monitored'], isFalse);
        expect(body['monitorNewItems'], 'none');
        expect(body['addOptions'], {
          'monitor': 'none',
          'searchForMissingAlbums': false,
        });
      },
    );

    test('leaves out what the lookup did not carry', () async {
      await service.addArtist(
        LidarrArtist.fromJson({
          'artistName': 'Bare',
          'foreignArtistId': 'mbid-bare',
        }),
        qualityProfileId: 1,
        metadataProfileId: 1,
        rootFolderPath: '/music',
        monitor: 'all',
        monitorNewItems: 'all',
        searchForMissingAlbums: true,
      );

      final body = adapter.lastBody as Map;
      expect(
        body.keys,
        isNot(
          anyOf(
            contains('overview'),
            contains('artistType'),
            contains('disambiguation'),
            contains('links'),
          ),
        ),
      );
    });

    test('throws when Lidarr refuses, rather than reporting an add', () async {
      adapter
        ..statusCode = 400
        ..response = [
          {'errorMessage': 'This artist has already been added'},
        ];

      await expectLater(
        service.addArtist(
          lookupRow(),
          qualityProfileId: 1,
          metadataProfileId: 1,
          rootFolderPath: '/music',
          monitor: 'all',
          monitorNewItems: 'all',
          searchForMissingAlbums: true,
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('throws when the answer is not an artist', () async {
      adapter.response = const <Object?>[];

      await expectLater(
        service.addArtist(
          lookupRow(),
          qualityProfileId: 1,
          metadataProfileId: 1,
          rootFolderPath: '/music',
          monitor: 'all',
          monitorNewItems: 'all',
          searchForMissingAlbums: true,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, dynamic> _artistJson({
  required int id,
  required String artistName,
  String status = 'active',
  bool monitored = true,
  int? qualityProfileId,
}) {
  return {
    'id': id,
    'artistName': artistName,
    'status': status,
    'monitored': monitored,
    'images': const [],
    'genres': const [],
    'qualityProfileId': ?qualityProfileId,
  };
}

Map<String, dynamic> _albumJson({
  required int id,
  required String title,
  required bool monitored,
}) {
  return {'id': id, 'title': title, 'monitored': monitored, 'images': const []};
}

Map<String, dynamic> _trackJson({
  required int id,
  required String title,
  required int duration,
}) {
  return {'id': id, 'title': title, 'hasFile': true, 'duration': duration};
}
