import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Lidarr library wall, with a failed fetch allowed to reach the wall.
///
/// See `moviesProvider`: off the swallowing `getArtists` a dark Lidarr read
/// "No items found".
///
/// The one read of the lens's library, as `moviesProvider` is Radarr's:
/// `lidarrKpiLibraryProvider` and `lidarrOverviewArtistsProvider` are names
/// for it.
final musicProvider = FutureProvider<List<LidarrArtist>>((ref) async {
  final service = ref.watch(lidarrServiceProvider);
  return service.getArtistsOrThrow();
}, retry: noProviderRetry);

/// [musicProvider] for one named connection, whatever the lens is on: the library
/// a second Lidarr holds. The lens's own id, and the empty one, read [musicProvider],
/// so a connection's library is downloaded once a session whichever surface
/// asks first. What Home's fold reads for a connection that is not the lens;
/// it used to download that library again every time Home was rebuilt.
final musicForProvider = FutureProvider.family<List<LidarrArtist>, String>((
  ref,
  instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id;
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(musicProvider.future);
  }
  return ref.watch(lidarrServiceForProvider(instanceId)).getArtistsOrThrow();
}, retry: noProviderRetry);

/// Every album the lens's Lidarr holds, for the wall's search to find in.
///
/// Read only while a search is open (nothing on the wall itself shows an
/// album), and let go when it closes, so an album that finished downloading
/// since is read again the next time. A failed read reaches the search, which
/// says so and still finds artists: [musicProvider] is what the wall is. Not
/// retried on its own, as every Lidarr read.
final musicAlbumsProvider = FutureProvider.autoDispose<List<LidarrAlbum>>((
  ref,
) async {
  final service = ref.watch(lidarrServiceProvider);
  return service.getAllAlbumsOrThrow();
}, retry: noProviderRetry);
