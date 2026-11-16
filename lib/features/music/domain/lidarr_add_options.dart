import 'package:cupola/features/music/domain/lidarr_monitor.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';

/// A quality profile as the add sheet offers it.
typedef LidarrProfileOption = ({int id, String name});

/// A root folder of one Lidarr and the defaults it carries
/// (`GET /api/v1/rootfolder`): what a new artist filed under it is given
/// unless the person says otherwise.
class LidarrRootFolder {
  const LidarrRootFolder({
    required this.path,
    this.freeSpace,
    this.defaultQualityProfileId,
    this.defaultMetadataProfileId,
    this.defaultMonitor,
    this.defaultNewItemMonitor,
  });

  final String path;

  /// Bytes free under it, where Lidarr said.
  final int? freeSpace;

  /// Null when Lidarr named none (it sends 0 for "no default").
  final int? defaultQualityProfileId;
  final int? defaultMetadataProfileId;

  /// `defaultMonitorOption`, when it is one this client knows.
  final LidarrMonitor? defaultMonitor;

  /// `defaultNewItemMonitorOption`: `all`, `none` or `new`.
  final String? defaultNewItemMonitor;

  /// Null for an entry with no path: there is nowhere to file under it.
  static LidarrRootFolder? tryParse(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    int? profile(Object? value) => value is int && value > 0 ? value : null;
    final newItems = json['defaultNewItemMonitorOption'];
    return LidarrRootFolder(
      path: path,
      freeSpace: (json['freeSpace'] as num?)?.toInt(),
      defaultQualityProfileId: profile(json['defaultQualityProfileId']),
      defaultMetadataProfileId: profile(json['defaultMetadataProfileId']),
      defaultMonitor: LidarrMonitor.fromWire(
        json['defaultMonitorOption'] as String?,
      ),
      defaultNewItemMonitor: switch (newItems) {
        'all' || 'none' || 'new' => newItems as String,
        _ => null,
      },
    );
  }
}

/// What one Lidarr offers a new artist: its root folders with their defaults,
/// its quality profiles and its metadata profiles.
class LidarrAddOptions {
  const LidarrAddOptions({
    required this.folders,
    required this.qualityProfiles,
    required this.metadataProfiles,
  });

  final List<LidarrRootFolder> folders;
  final List<LidarrProfileOption> qualityProfiles;
  final List<LidarrMetadataProfile> metadataProfiles;

  /// Whether there is something to post: a folder and both profiles. A Lidarr
  /// without one has nothing honest to add under.
  String? get missing {
    if (folders.isEmpty) return 'root folder';
    if (qualityProfiles.isEmpty) return 'quality profile';
    if (metadataProfiles.isEmpty) return 'metadata profile';
    return null;
  }
}

/// Where and how an artist that comes in with an album is filed: what
/// `POST /api/v1/album` needs of an artist Lidarr does not hold yet.
class LidarrNewArtistSetup {
  const LidarrNewArtistSetup({
    required this.rootFolderPath,
    required this.qualityProfileId,
    required this.metadataProfileId,
    this.monitorNewItems = 'none',
  });

  final String rootFolderPath;
  final int qualityProfileId;
  final int metadataProfileId;

  /// Whether the albums Lidarr learns of later are monitored: not for an
  /// artist added for one album.
  final String monitorNewItems;
}
