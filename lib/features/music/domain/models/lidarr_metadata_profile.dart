/// A Lidarr metadata profile: which kinds of release Lidarr keeps of an
/// artist (`GET /api/v1/metadataprofile`).
class LidarrMetadataProfile {
  const LidarrMetadataProfile({
    required this.id,
    required this.name,
    this.allowedPrimaryTypes = const [],
  });

  final int id;
  final String name;

  /// The names of the primary album types the profile allows, in Lidarr's
  /// order: `Album`, `EP`.
  final List<String> allowedPrimaryTypes;

  /// Null when the entry has no id: it cannot be chosen.
  static LidarrMetadataProfile? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) return null;
    return LidarrMetadataProfile(
      id: id,
      name: json['name'] as String? ?? 'Profile',
      allowedPrimaryTypes: [
        for (final entry in (json['primaryAlbumTypes'] as List? ?? const []))
          if (entry is Map && entry['allowed'] == true)
            if ((entry['albumType'] as Map?)?['name'] case final String name)
              name,
      ],
    );
  }

  /// What the profile keeps, in words: `Albums and EPs`. Null when it allows
  /// no primary type (or Lidarr did not list them): there is nothing true to
  /// say under its name.
  String? get typesLine {
    final plural = [for (final name in allowedPrimaryTypes) _plural(name)];
    return switch (plural.length) {
      0 => null,
      1 => plural.single,
      _ => '${plural.take(plural.length - 1).join(', ')} and ${plural.last}',
    };
  }

  /// `Album` is `Albums`, `EP` is `EPs`; `Other` has no plural to speak.
  static String _plural(String name) =>
      name == 'Other' ? name : [name, 's'].join();
}
