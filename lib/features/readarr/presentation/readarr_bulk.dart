import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/parallel_reads.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/arr_bulk.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Readarr's words and what its editor takes: authors, the books Readarr looks
/// for of them, a quality and a metadata profile, and `monitorNewItems`
/// (`Monitor new books`).
const readarrBulkKind = ArrBulkKind(
  service: ServiceKey.readarr,
  singular: 'author',
  plural: 'authors',
  noneHint: 'Select an author first',
  works: 'books',
  newItemsHeading: 'Monitor new books',
  hasMetadataProfile: true,
);

/// The quality and metadata profiles one Readarr offers, read when the Profile
/// sheet opens: both are Readarr's own database, never the metadata host that
/// no longer answers.
final readarrProfilesProvider = FutureProvider.autoDispose
    .family<ArrProfileOptions, String>((ref, instanceId) async {
      final service = ref.watch(readarrServiceForProvider(instanceId));
      final (quality, metadata) = await readTogether(
        service.getQualityProfilesOrThrow(),
        service.getMetadataProfilesOrThrow(),
      );
      return (
        quality: arrQualityChoices(quality),
        metadata: [
          for (final profile in metadata)
            (id: profile.id, name: profile.name, detail: null),
        ],
      );
    }, retry: noProviderRetry);

/// What the Authors wall can do to several authors at once: Search (one
/// `AuthorSearch` command each), Monitor, Profile and Remove (see
/// [arrBulk]).
MediaBulk<ReadarrAuthor> readarrBulk({
  required WidgetRef ref,
  required String instanceId,
  required String name,
  void Function(WidgetRef ref)? onChanged,
  bool dialogsOnRoot = true,
}) {
  ReadarrService service() => ref.read(readarrServiceForProvider(instanceId));
  return arrBulk<ReadarrAuthor>(
    ref,
    ArrBulkAdapter<ReadarrAuthor>(
      kind: readarrBulkKind,
      instanceId: instanceId,
      name: name,
      idOf: (author) => author.id,
      nameOf: (author) => author.authorName,
      monitoredOf: (author) => author.monitored,
      qualityOf: (author) => author.qualityProfileId,
      metadataOf: (author) => author.metadataProfileId,
      newItemsOf: (author) => author.monitorNewItems,
      sizeOf: (author) => author.hasStatistics ? author.sizeOnDisk : null,
      search: (ids) => service().searchAuthorsInBulk(ids),
      update: (ids, edit) => service().updateAuthorsInBulk(ids, edit),
      remove: (ids, {required deleteFiles, required addImportListExclusion}) =>
          service().removeAuthorsInBulk(
            ids,
            deleteFiles: deleteFiles,
            addImportListExclusion: addImportListExclusion,
          ),
      watchProfiles: (ref) => ref.watch(readarrProfilesProvider(instanceId)),
      retryProfiles: (ref) =>
          ref.invalidate(readarrProfilesProvider(instanceId)),
      onChanged: onChanged,
    ),
    dialogsOnRoot: dialogsOnRoot,
  );
}
