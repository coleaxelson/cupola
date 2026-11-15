import 'package:flutter/foundation.dart';

/// What `PUT /api/v1/artist/editor` is asked to set on a set of artists.
///
/// Lidarr's `ArtistEditorResource` leaves a field it was not sent alone, so an
/// edit carries only what was chosen: an artist's other settings are never
/// written back from a copy that may be stale.
@immutable
class LidarrArtistEdit {
  const LidarrArtistEdit({
    this.monitored,
    this.monitorNewItems,
    this.qualityProfileId,
    this.metadataProfileId,
  });

  /// Whether Lidarr watches the artist; null leaves it as it is.
  final bool? monitored;

  /// What Lidarr does with albums it learns of later: `all`, `none` or `new`;
  /// null leaves it as it is.
  final String? monitorNewItems;

  final int? qualityProfileId;
  final int? metadataProfileId;

  /// Nothing is to change.
  bool get isEmpty =>
      monitored == null &&
      monitorNewItems == null &&
      qualityProfileId == null &&
      metadataProfileId == null;

  /// The fields of the request body, those that are set.
  Map<String, dynamic> get fields => {
    'monitored': ?monitored,
    'monitorNewItems': ?monitorNewItems,
    'qualityProfileId': ?qualityProfileId,
    'metadataProfileId': ?metadataProfileId,
  };
}

/// What Lidarr said of a set of artists a write was for: the ids it took and,
/// for each it refused, what it refused with.
///
/// Only what Lidarr reported. An artist is in [refused] because its own
/// request was turned down, and never because a request for several was.
@immutable
class LidarrBulkResult {
  const LidarrBulkResult({required this.done, this.refused = const {}});

  final List<int> done;

  /// The failure each refused artist's request ended in, by artist id.
  final Map<int, Object> refused;
}
