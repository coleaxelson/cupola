/// Which of an artist's albums Lidarr looks for once the artist is added:
/// Lidarr's `addOptions.monitor` (its `MonitorTypes`).
enum LidarrMonitor {
  all,
  future,
  missing,
  existing,
  first,
  latest,
  none;

  /// The string Lidarr expects.
  String get wireValue => name;

  /// The option Lidarr's root folder names as its default
  /// (`defaultMonitorOption`), or null for a word this client does not know:
  /// the caller then keeps its own default rather than guessing.
  static LidarrMonitor? fromWire(String? value) {
    for (final monitor in values) {
      if (monitor.name == value) return monitor;
    }
    return null;
  }

  /// Lidarr's own name for it, in the app's case.
  String get label => switch (this) {
    LidarrMonitor.all => 'All albums',
    LidarrMonitor.future => 'Future albums',
    LidarrMonitor.missing => 'Missing albums',
    LidarrMonitor.existing => 'Existing albums',
    LidarrMonitor.first => 'First album',
    LidarrMonitor.latest => 'Latest album',
    LidarrMonitor.none => 'None',
  };

  /// What choosing it means, under the label.
  String get meaning => switch (this) {
    LidarrMonitor.all => 'Every album, out and to come',
    LidarrMonitor.future => 'Only albums not out yet',
    LidarrMonitor.missing => 'Albums without files, and those not out yet',
    LidarrMonitor.existing => 'Albums with files, and those not out yet',
    LidarrMonitor.first => 'The first album alone',
    LidarrMonitor.latest => 'The latest album alone',
    LidarrMonitor.none => 'Lists the artist and looks for nothing',
  };
}
