class LidarrAlbum {
  final int id;

  /// MusicBrainz's release group id: the album's identity across every
  /// Lidarr, where [id] is only this server's. Empty when Lidarr sent none.
  final String foreignAlbumId;

  final String title;

  /// The library artist the album belongs to: 0 for an album Lidarr does not
  /// hold (a search result), where only the nested artist says whose it is.
  final int artistId;

  /// What kind of release it is, as MusicBrainz names it: `Album`, `EP`,
  /// `Single`. Null when Lidarr did not say.
  final String? albumType;

  /// MusicBrainz's secondary types, as Lidarr names them (`AlbumResource.
  /// SecondaryTypes`, a list of strings): `Live`, `Compilation`, `Soundtrack`,
  /// `Studio`... Empty for a plain release.
  final List<String> secondaryTypes;

  final String? releaseDate;
  final bool monitored;
  final List<dynamic> images;
  final Map<String, dynamic>? statistics;

  /// The album's length in milliseconds, as Lidarr adds up its tracks; 0
  /// when it does not say.
  final int duration;

  const LidarrAlbum({
    required this.id,
    this.foreignAlbumId = '',
    required this.title,
    this.artistId = 0,
    this.albumType,
    this.secondaryTypes = const [],
    this.releaseDate,
    required this.monitored,
    required this.images,
    this.statistics,
    this.duration = 0,
  });

  String get year {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }

    return '';
  }

  int get trackCount => (statistics?['totalTrackCount'] as num?)?.toInt() ?? 0;

  int get trackFileCount =>
      (statistics?['trackFileCount'] as num?)?.toInt() ?? 0;

  double get completionPercent =>
      trackCount > 0 ? trackFileCount / trackCount : 0.0;

  factory LidarrAlbum.fromJson(Map<String, dynamic> json) {
    final rawStatistics = json['statistics'];

    return LidarrAlbum(
      id: (json['id'] as num?)?.toInt() ?? 0,
      foreignAlbumId: (json['foreignAlbumId'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Unknown album',
      artistId: (json['artistId'] as num?)?.toInt() ?? 0,
      albumType: (json['albumType'] as String?)?.trim().isNotEmpty == true
          ? (json['albumType'] as String).trim()
          : null,
      secondaryTypes: _namesOf(json['secondaryTypes']),
      releaseDate: json['releaseDate'] as String?,
      monitored: json['monitored'] as bool? ?? false,
      images: json['images'] as List<dynamic>? ?? const [],
      statistics: rawStatistics is Map<String, dynamic> ? rawStatistics : null,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The names in a list Lidarr sends as strings; a record with a `name` is read
/// the same, and anything else is left out.
List<String> _namesOf(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty)
        item.trim()
      else if (item is Map && item['name'] is String)
        (item['name'] as String).trim(),
];
