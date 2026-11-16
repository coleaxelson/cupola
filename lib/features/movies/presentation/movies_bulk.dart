import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/arr_bulk.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Radarr's words and what its editor takes: movies, a quality profile and
/// nothing else (`MovieEditorResource` has no `monitorNewItems` and no
/// metadata profile), so the Monitor sheet has one control and the Profile
/// sheet one row.
const radarrBulkKind = ArrBulkKind(
  service: ServiceKey.radarr,
  singular: 'movie',
  plural: 'movies',
  noneHint: 'Select a movie first',
);

/// The quality profiles one Radarr offers, read when the Profile sheet opens.
/// A failure reaches the sheet, which says who did not answer and offers
/// Retry.
final radarrProfilesProvider = FutureProvider.autoDispose
    .family<ArrProfileOptions, String>((ref, instanceId) async {
      final profiles = await ref
          .watch(radarrServiceForProvider(instanceId))
          .getQualityProfilesOrThrow();
      return (quality: arrQualityChoices(profiles), metadata: null);
    }, retry: noProviderRetry);

/// What Movies' wall can do to several movies at once: Search (one
/// `MoviesSearch` command for the list), Monitor, Profile and Remove (see
/// [arrBulk]).
MediaBulk<RadarrMovie> radarrBulk({
  required WidgetRef ref,
  required String instanceId,
  required String name,
  void Function(WidgetRef ref)? onChanged,
  bool dialogsOnRoot = true,
}) {
  RadarrService service() => ref.read(radarrServiceForProvider(instanceId));
  return arrBulk<RadarrMovie>(
    ref,
    ArrBulkAdapter<RadarrMovie>(
      kind: radarrBulkKind,
      instanceId: instanceId,
      name: name,
      idOf: (movie) => movie.id,
      nameOf: (movie) => movie.title,
      monitoredOf: (movie) => movie.monitored,
      qualityOf: (movie) => movie.qualityProfileId,
      // Radarr sends `sizeOnDisk` on every movie.
      sizeOf: (movie) => movie.sizeOnDisk,
      search: (ids) => service().searchMoviesInBulk(ids),
      update: (ids, edit) => service().updateMoviesInBulk(ids, edit),
      remove: (ids, {required deleteFiles, required addImportListExclusion}) =>
          service().removeMoviesInBulk(
            ids,
            deleteFiles: deleteFiles,
            addImportExclusion: addImportListExclusion,
          ),
      watchProfiles: (ref) => ref.watch(radarrProfilesProvider(instanceId)),
      retryProfiles: (ref) =>
          ref.invalidate(radarrProfilesProvider(instanceId)),
      onChanged: onChanged,
    ),
    dialogsOnRoot: dialogsOnRoot,
  );
}
