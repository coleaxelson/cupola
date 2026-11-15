import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_catalog_unavailable.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final lidarrServiceProvider = _lidarr.lens;

final lidarrServiceForProvider = _lidarr.forConnection;

final _lidarr = ConnectionProviders<LidarrService>.apiClient(
  ServiceKey.lidarr,
  create: LidarrService.new,
);

/// Service for interacting with Lidarr API.
///
/// Provides artist-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class LidarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.lidarr;

  LidarrService(this.client);

  /// Asks for the artist and the album with every queue record.
  ///
  /// A Lidarr queue record on its own carries `artistId`/`albumId` and the raw
  /// release name, nothing else, so a row built from it could only print
  /// `Cindy.Lee-Diamond.Jubilee-WEB-2024-XYZ`. The embeds are what turn that
  /// into `Import failed · Cindy Lee: Diamond Jubilee`, and they only ride
  /// along when the request asks for them, exactly as Radarr must ask for
  /// `includeMovie` and Readarr for `includeBook`/`includeAuthor`. On the page
  /// primitive, which `getQueue` delegates to, so a count and its rows both
  /// carry them.
  @override
  Future<ArrRecordPage> getQueuePage({Map<String, dynamic>? queryParameters}) {
    return super.getQueuePage(
      queryParameters: {
        'includeArtist': true,
        'includeAlbum': true,
        ...?queryParameters,
      },
    );
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates here, so both spellings pick the parameters up,
  /// but only this way round; `base_arr_service.dart` warns about precisely
  /// this. Lidarr needs it more than its siblings do, because its history is
  /// written **per track file**: the Overview's "today" section folds a page
  /// back down to one row per album, and the key it folds on is
  /// `record['album']['id']`. Without `includeAlbum` that object is absent,
  /// every track of one import lands in a group of its own, and a fourteen-track
  /// album fills the three-row cap three times over, each row titled with the
  /// raw `sourceTitle`, because `includeArtist` is what supplies the other half
  /// of `Artist: Album`. The fold and the titles are both promises this one
  /// request keeps.
  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {
        'includeArtist': true,
        'includeAlbum': true,
        ...?queryParameters,
      },
    );
  }

  /// The same embed on the wanted endpoints, and on the **page** primitive for
  /// the same reason history is.
  ///
  /// A Lidarr `wanted/missing` record is an album: id, title, release date,
  /// `artistId`. The artist object rides only when the request asks, and the
  /// Overview's backlog line counts distinct `arrArtistName(row)` to say
  /// "across 6 artists", a clause that, unasked, computed an empty set on
  /// every real server and was therefore dropped every single time. It dropped
  /// rather than lied, which is why nobody saw it; it was still a promise the
  /// request could never keep.
  @override
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getMissingPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {'includeArtist': true, ...?queryParameters},
    );
  }

  /// As [getMissingPage]. Cutoff rows print the same `Artist: Album` line.
  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getCutoffPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {'includeArtist': true, ...?queryParameters},
    );
  }

  /// The walks need their own override: they go through `_fetchAllPages`, not
  /// through the page primitives, and they are what Activity's Wanted tab
  /// reads, where a music row's secondary line *is* `arrArtistName`.
  @override
  Future<List<dynamic>> getAllMissing({Map<String, dynamic>? queryParameters}) {
    return super.getAllMissing(
      queryParameters: {'includeArtist': true, ...?queryParameters},
    );
  }

  @override
  Future<List<dynamic>> getAllCutoff({Map<String, dynamic>? queryParameters}) {
    return super.getAllCutoff(
      queryParameters: {'includeArtist': true, ...?queryParameters},
    );
  }

  /// Fetches all artists from Lidarr, answering `[]` when it cannot be read.
  ///
  /// The degrading read, for joins that can go on without the library (the
  /// queue's album lookup). The wall and every *figure* use [getArtistsOrThrow].
  Future<List<LidarrArtist>> getArtists() async {
    return fetchAllItems('artist', LidarrArtist.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// See [fetchAllItemsOrThrow]. Off the swallowing read a dark Lidarr printed
  /// `Artists 0 · Albums 0 · Tracks 0/0 · Missing 0`, which is a library that
  /// exists and is empty: the opposite of what happened.
  Future<List<LidarrArtist>> getArtistsOrThrow() async {
    return fetchAllItemsOrThrow('artist', LidarrArtist.fromJson);
  }

  /// Fetches a single artist by ID, returning a typed model.
  Future<LidarrArtist?> getArtistById(int artistId) async {
    return fetchItem('artist', artistId, LidarrArtist.fromJson);
  }

  /// One artist, letting a failure reach the caller: the artist's page says
  /// why it could not read the record rather than that there is none.
  Future<LidarrArtist> getArtistOrThrow(int artistId) =>
      fetchItemOrThrow('artist', artistId, LidarrArtist.fromJson);

  /// Fetches all albums for an artist.
  ///
  /// Artist-scoped, and that is the whole of what Lidarr answers here today.
  /// Decision 24 merges Artists and Albums into one segmented tab, which
  /// is what freed Lidarr's sixth tab for History, and the Albums
  /// segment needs a library-wide list that carries each album's artist. What
  /// it would take, precisely:
  ///
  /// - the library-wide list with the artist on each record: what
  ///   [getAllAlbumsOrThrow] asks for, plus `includeArtist=true`.
  /// - `LidarrAlbum` gains `artistName`, `albumType` and the quality profile.
  ///   Its entire field list today is id, foreignAlbumId, title,
  ///   releaseDate, monitored, images and statistics, so the drawn album
  ///   table has no column to fill beyond the title: the list arriving
  ///   would not be enough on its own.
  /// - a segment slot on `MediaBrowseScaffold`, which has none: its only
  ///   injectable widget is `kpiPeek`. That is a shared change in
  ///   `lib/core/widgets/`, outside this feature.
  ///
  /// None of it is added speculatively here: an unused client method is the
  /// same defect as Prowlarr's `getStatus()`, which this pass deleted.
  Future<List<LidarrAlbum>> getAlbums(int artistId) async {
    return fetchListItems('album', {
      'artistId': artistId,
    }, LidarrAlbum.fromJson);
  }

  /// Every album in the library: the same `GET /api/v1/album` with no
  /// `artistId`, which Lidarr answers with the whole list. With a failed
  /// fetch allowed to reach the caller, because what reads it counts.
  ///
  /// Read for one thing only, the stack card of a Lidarr with a second
  /// connection: two Lidarr usually hold the same albums, and their album
  /// counts added are a count of copies. Each album's `foreignAlbumId` is
  /// what lets the card count one both hold once.
  Future<List<LidarrAlbum>> getAllAlbumsOrThrow() async {
    return fetchAllItemsOrThrow('album', LidarrAlbum.fromJson);
  }

  /// Fetches all tracks for an album.
  Future<List<LidarrTrack>> getTracks(int albumId) async {
    return fetchListItems('track', {'albumId': albumId}, LidarrTrack.fromJson);
  }

  /// Triggers an automatic search for an artist.
  Future<void> searchArtist(int artistId) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'ArtistSearch', 'artistId': artistId},
    );
  }

  /// Triggers an automatic search for albums.
  Future<void> searchAlbums(List<int> albumIds) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'AlbumSearch', 'albumIds': albumIds},
    );
  }

  /// Fetches releases for interactive search.
  Future<List<dynamic>> getReleases({
    int? artistId,
    int? albumId,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final params = <String, dynamic>{};
    if (artistId != null) params['artistId'] = artistId;
    if (albumId != null) params['albumId'] = albumId;

    return fetchReleases(
      params,
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout,
    );
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Adds [lookupRow] (an `artist/lookup` row) to this Lidarr's library.
  ///
  /// The row is posted back as the identity Lidarr builds the artist from: its
  /// MusicBrainz id ([LidarrArtist.foreignArtistId]) is what Lidarr keys the
  /// new entry on, the name and the artwork let it show the artist before its
  /// first metadata refresh, and what the lookup carried about who they are
  /// (type, disambiguation, overview, links) rides along. What the person
  /// chose goes beside it: where the artist is filed ([rootFolderPath]), the
  /// two profiles, and what Lidarr looks for.
  ///
  /// [monitor] is Lidarr's `MonitorTypes` (`all`, `future`, `missing`,
  /// `existing`, `first`, `latest`, `none`; see `LidarrMonitor`). The artist is
  /// monitored unless it is `none`, and [monitorNewItems] (`all` or `none`)
  /// says whether the albums Lidarr learns of later are monitored too.
  /// `addOptions.searchForMissingAlbums` is the half that makes this an add
  /// rather than a bookmark: without it nothing is looked for until a search
  /// is asked.
  ///
  /// Lidarr answers with the new artist, whose albums it has not read yet:
  /// they arrive a moment later.
  ///
  /// Throws on failure rather than degrading. Lidarr answers 400 for an artist
  /// it already holds, and a caller that cannot tell that from a success would
  /// report an add that never happened.
  Future<LidarrArtist> addArtist(
    LidarrArtist lookupRow, {
    required int qualityProfileId,
    required int metadataProfileId,
    required String rootFolderPath,
    required String monitor,
    required String monitorNewItems,
    required bool searchForMissingAlbums,
  }) async {
    final response = await client.post(
      '/api/v1/artist',
      data: {
        'artistName': lookupRow.artistName,
        // Lidarr keys the new entry on this, not on the name.
        'foreignArtistId': lookupRow.foreignArtistId,
        // Posted back so the artist has artwork before the first refresh.
        'images': lookupRow.images,
        'overview': ?lookupRow.overview,
        'artistType': ?lookupRow.artistType,
        'disambiguation': ?lookupRow.disambiguation,
        'links': ?lookupRow.links,
        'qualityProfileId': qualityProfileId,
        'metadataProfileId': metadataProfileId,
        'rootFolderPath': rootFolderPath,
        'monitored': monitor != 'none',
        'monitorNewItems': monitorNewItems,
        'addOptions': {
          'monitor': monitor,
          'searchForMissingAlbums': searchForMissingAlbums,
        },
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Lidarr answered without an artist');
    }
    return LidarrArtist.fromJson(data.cast<String, dynamic>());
  }

  /// Lidarr's search: artists and albums together, from its online catalog
  /// (`GET /api/v1/search?term=`), each row with the artist it is about.
  ///
  /// Throws rather than degrading, so a search that failed is never "found
  /// nothing". A catalog that did not answer while Lidarr did is its own
  /// failure, [LidarrCatalogUnavailable]: the library still works and the
  /// person is told so. [cancelToken] aborts the request once the search that
  /// asked for it has been superseded.
  Future<List<LidarrSearchHit>> search(
    String term, {
    CancelToken? cancelToken,
  }) async {
    if (term.trim().isEmpty) return const [];
    final Response response;
    try {
      response = await client.get(
        '/api/v1/search',
        queryParameters: {'term': term},
        cancelToken: cancelToken,
      );
    } catch (error) {
      throw LidarrCatalogUnavailable.of(error) ?? error;
    }
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Lidarr answered without search results');
    }
    return [
      for (final row in data.whereType<Map>())
        ?LidarrSearchHit.tryParse(row.cast<String, dynamic>()),
    ];
  }

  /// Sets whether Lidarr monitors [albumIds] (`PUT /api/v1/album/monitor`).
  /// Throws on failure.
  Future<void> setAlbumsMonitored(List<int> albumIds, bool monitored) async {
    await client.put(
      '/api/v1/album/monitor',
      data: {'albumIds': albumIds, 'monitored': monitored},
    );
  }

  /// Monitors [albumId] and has Lidarr look for it: the two halves of "get
  /// this album" on an album the library holds and was told to leave alone.
  /// Throws on failure, and the search is not started when the monitor was not
  /// written.
  Future<void> monitorAndSearchAlbum(int albumId) async {
    await setAlbumsMonitored([albumId], true);
    await searchAlbums([albumId]);
  }

  /// Adds [hit]'s album (`POST /api/v1/album`), the way Lidarr's own front
  /// end does: the album as the search described it, monitored, with
  /// `addOptions.searchForNewAlbum`, and its artist inside.
  ///
  /// Where Lidarr does not hold the artist ([newArtist]), the artist is added
  /// with it, under the folder and profiles chosen, and only this album is
  /// monitored: `addOptions.monitor` is `none` and `albumsToMonitor` names the
  /// album by its MusicBrainz id. Lidarr's `AlbumMonitoredService` sets every
  /// album unmonitored under `none` and, when `albumsToMonitor` is not empty,
  /// monitors exactly those and no other, whatever the metadata profile. The
  /// rest of the artist's discography arrives unmonitored.
  ///
  /// Where it does ([libraryArtistId]), the artist goes with it as the library
  /// holds it (read here, whole: its path and profiles are what Lidarr
  /// validates the album against) and Lidarr adds the album under them. That is
  /// the case of an album the artist's metadata profile leaves out.
  ///
  /// Answers the artist the album is under now, as the library holds them,
  /// or null when the post succeeded and the artist could not be read after:
  /// the album is added all the same, and a caller never reports a write that
  /// went through as one that did not. Throws only when the post itself failed:
  /// Lidarr answers 400 with its reason.
  Future<LidarrArtist?> addAlbum(
    LidarrAlbumHit hit, {
    required bool searchForNewAlbum,
    int? libraryArtistId,
    LidarrNewArtistSetup? newArtist,
  }) async {
    assert(
      (libraryArtistId == null) != (newArtist == null),
      'the artist is in the library, or it is added with the album',
    );
    final body = Map<String, dynamic>.of(hit.raw);
    LidarrArtist? held;
    if (libraryArtistId != null) {
      final record = await client.get('/api/v1/artist/$libraryArtistId');
      if (record.data is! Map) {
        throw const FormatException('Lidarr answered without the artist');
      }
      final json = (record.data as Map).cast<String, dynamic>();
      body['artist'] = json;
      held = LidarrArtist.fromJson(json);
    } else {
      final setup = newArtist!;
      body['artist'] = {
        ...?(body['artist'] as Map?)?.cast<String, dynamic>(),
        'monitored': true,
        'monitorNewItems': setup.monitorNewItems,
        'qualityProfileId': setup.qualityProfileId,
        'metadataProfileId': setup.metadataProfileId,
        'rootFolderPath': setup.rootFolderPath,
        'addOptions': {
          'monitor': 'none',
          'albumsToMonitor': [hit.album.foreignAlbumId],
          'searchForMissingAlbums': false,
        },
        'tags': const <int>[],
      };
    }
    body
      ..['monitored'] = true
      ..['addOptions'] = {'searchForNewAlbum': searchForNewAlbum};

    final response = await client.post('/api/v1/album', data: body);
    // The album is added. What follows only finds the artist to open, and
    // nothing in it may read as a refusal.
    try {
      final data = response.data;
      if (data is Map && data['artist'] is Map) {
        final artist = LidarrArtist.fromJson(
          (data['artist'] as Map).cast<String, dynamic>(),
        );
        if (artist.id > 0) return artist;
      }
      if (held != null) return held;
      // The answer did not carry the artist as the library holds it: ask for
      // it by its MusicBrainz id.
      final byId = await client.get(
        '/api/v1/artist',
        queryParameters: {'mbId': hit.artist.foreignArtistId},
      );
      final found = byId.data;
      if (found is List && found.firstOrNull is Map) {
        final artist = LidarrArtist.fromJson(
          (found.first as Map).cast<String, dynamic>(),
        );
        if (artist.id > 0) return artist;
      }
    } catch (_) {
      // Added all the same.
    }
    return null;
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// The quality profiles, with a failed read allowed to reach the caller.
  ///
  /// [getQualityProfiles] answers `[]` when it cannot read, which on the add
  /// sheet would say "no quality profile configured" of a Lidarr that did not
  /// answer. Read beside [getRootFolders], which already travels.
  Future<List<Map<String, dynamic>>> getQualityProfilesOrThrow() async {
    final response = await client.get('/api/v1/qualityprofile');
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Lidarr answered without its profiles');
    }
    return data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// This Lidarr's metadata profiles: which kinds of release it keeps of an
  /// artist. A failure travels, as [getRootFolders]'s does.
  Future<List<LidarrMetadataProfile>> getMetadataProfiles() async {
    final response = await client.get('/api/v1/metadataprofile');
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Lidarr answered without its profiles');
    }
    return [
      for (final entry in data.whereType<Map>())
        ?LidarrMetadataProfile.tryParse(entry.cast<String, dynamic>()),
    ];
  }

  /// Fetches the root folders configured on this Lidarr.
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    return fetchRootFolders();
  }

  /// Updates an artist's quality profile.
  Future<void> updateArtistProfile(int artistId, int qualityProfileId) async {
    await updateItemProfile('artist', artistId, qualityProfileId);
  }

  /// Updates an artist's monitored state.
  Future<void> updateArtistMonitored(int artistId, bool monitored) async {
    await updateItemMonitored('artist', artistId, monitored);
  }

  /// Sets whether Lidarr monitors the albums it learns of for an artist:
  /// `all` or `none`, or `new` (only those released from now on).
  Future<void> updateArtistMonitorNewItems(int artistId, String value) =>
      updateItemFields('artist', artistId, {'monitorNewItems': value});

  /// Deletes an artist from Lidarr.
  Future<void> deleteArtist(
    int artistId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v1/artist/$artistId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
  }
}
