import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/arr_bulk.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Sonarr's words and what its editor takes: series, a quality profile, and
/// `monitorNewItems` (`Monitor new seasons`). No metadata profile.
const sonarrBulkKind = ArrBulkKind(
  service: ServiceKey.sonarr,
  singular: 'series',
  plural: 'series',
  noneHint: 'Select a series first',
  newItemsHeading: 'Monitor new seasons',
);

/// The quality profiles one Sonarr offers, read when the Profile sheet opens.
final sonarrProfilesProvider = FutureProvider.autoDispose
    .family<ArrProfileOptions, String>((ref, instanceId) async {
      final profiles = await ref
          .watch(sonarrServiceForProvider(instanceId))
          .getQualityProfilesOrThrow();
      return (quality: arrQualityChoices(profiles), metadata: null);
    }, retry: noProviderRetry);

/// What the series wall can do to several series at once: Search (one
/// `SeriesSearch` command each), Monitor, Profile and Remove (see [arrBulk]).
MediaBulk<SonarrSeries> sonarrBulk({
  required WidgetRef ref,
  required String instanceId,
  required String name,
  void Function(WidgetRef ref)? onChanged,
  bool dialogsOnRoot = true,
}) {
  SonarrService service() => ref.read(sonarrServiceForProvider(instanceId));
  return arrBulk<SonarrSeries>(
    ref,
    ArrBulkAdapter<SonarrSeries>(
      kind: sonarrBulkKind,
      instanceId: instanceId,
      name: name,
      idOf: (series) => series.id,
      nameOf: (series) => series.title,
      monitoredOf: (series) => series.monitored,
      qualityOf: (series) => series.qualityProfileId,
      newItemsOf: (series) => series.monitorNewItems,
      // A freshly added series has no `statistics`, which is a zero on disk:
      // it has no files yet (see `SonarrSeries.sizeOnDisk`).
      sizeOf: (series) => series.sizeOnDisk,
      search: (ids) => service().searchSeriesInBulk(ids),
      update: (ids, edit) => service().updateSeriesInBulk(ids, edit),
      remove: (ids, {required deleteFiles, required addImportListExclusion}) =>
          service().removeSeriesInBulk(
            ids,
            deleteFiles: deleteFiles,
            addImportListExclusion: addImportListExclusion,
          ),
      watchProfiles: (ref) => ref.watch(sonarrProfilesProvider(instanceId)),
      retryProfiles: (ref) =>
          ref.invalidate(sonarrProfilesProvider(instanceId)),
      onChanged: onChanged,
    ),
    dialogsOnRoot: dialogsOnRoot,
  );
}
