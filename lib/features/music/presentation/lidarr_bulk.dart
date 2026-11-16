import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/arr_bulk.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Lidarr's words and what its editor takes: artists and the albums Lidarr
/// looks for of them, a metadata profile beside the quality profile, and
/// `Monitor new albums`.
const lidarrBulkKind = ArrBulkKind(
  service: ServiceKey.lidarr,
  singular: 'artist',
  plural: 'artists',
  noneHint: 'Select an artist first',
  works: 'albums',
  newItemsHeading: 'Monitor new albums',
  hasMetadataProfile: true,
);

/// What Lidarr's wall can do to several artists at once: search, monitor, set
/// the profiles, remove. The selection bar's four actions, each asking what it
/// needs before it runs (see [arrBulk]).
///
/// [name] is the connection as a sentence says it (`Lidarr`, `Lidarr 4K`);
/// [instanceId] the connection the wall reads (empty for the lens's). The
/// actions read their service through [ref] when they run, so a wall that
/// outlives a connection change writes where it is looking.
MediaBulk<LidarrArtist> lidarrBulk({
  required WidgetRef ref,
  required String instanceId,
  required String name,
  void Function(WidgetRef ref)? onChanged,
  bool dialogsOnRoot = true,
}) {
  LidarrService service() => ref.read(lidarrServiceForProvider(instanceId));
  return arrBulk<LidarrArtist>(
    ref,
    ArrBulkAdapter<LidarrArtist>(
      kind: lidarrBulkKind,
      instanceId: instanceId,
      name: name,
      idOf: (artist) => artist.id,
      nameOf: (artist) => artist.artistName,
      monitoredOf: (artist) => artist.monitored,
      qualityOf: (artist) => artist.qualityProfileId,
      metadataOf: (artist) => artist.metadataProfileId,
      newItemsOf: (artist) => artist.monitorNewItems,
      // Where Lidarr did not send statistics the size is not known, and the
      // removal prints no figure.
      sizeOf: (artist) => artist.statistics == null ? null : artist.sizeOnDisk,
      search: (ids) => service().searchArtistsInBulk(ids),
      update: (ids, edit) => service().updateArtistsInBulk(ids, edit),
      remove: (ids, {required deleteFiles, required addImportListExclusion}) =>
          service().removeArtistsInBulk(
            ids,
            deleteFiles: deleteFiles,
            addImportListExclusion: addImportListExclusion,
          ),
      watchProfiles: (ref) => ref
          .watch(lidarrAddOptionsProvider(instanceId))
          .whenDataKept(
            (options) => (
              quality: [
                for (final profile in options.qualityProfiles)
                  (id: profile.id, name: profile.name, detail: null),
              ],
              metadata: [
                for (final profile in options.metadataProfiles)
                  (
                    id: profile.id,
                    name: profile.name,
                    detail: profile.typesLine,
                  ),
              ],
            ),
          ),
      retryProfiles: (ref) =>
          ref.invalidate(lidarrAddOptionsProvider(instanceId)),
      onChanged: onChanged,
    ),
    dialogsOnRoot: dialogsOnRoot,
  );
}

/// The artists a sheet is for, as it names them under its title.
String lidarrBulkNames(List<LidarrArtist> artists) =>
    arrBulkNames([for (final artist in artists) artist.artistName]);

/// One refusal as a sentence, in Lidarr's own words when it gave any.
String lidarrRefusalLine(String artist, Object error, String name) =>
    arrRefusalLine(artist, error, ServiceKey.lidarr, name);

/// What the Monitor sheet starts on for [artists].
bool lidarrBulkStartMonitored(List<LidarrArtist> artists) =>
    arrBulkStartMonitored([for (final artist in artists) artist.monitored]);

/// The albums-to-come setting the Monitor sheet starts on for [artists].
String? lidarrBulkStartNewItems(List<LidarrArtist> artists) =>
    arrBulkStartNewItems([
      for (final artist in artists) artist.monitorNewItems,
    ]);

/// The profile every artist of [artists] has, by [of], or null.
int? lidarrBulkSharedProfile(
  List<LidarrArtist> artists,
  int? Function(LidarrArtist artist) of,
) => arrBulkSharedProfile([for (final artist in artists) of(artist)]);

/// The Monitor sheet's body for [artists]: see [ArrBulkMonitorSheet].
class LidarrBulkMonitorSheet extends StatelessWidget {
  const LidarrBulkMonitorSheet({super.key, required this.artists});

  final List<LidarrArtist> artists;

  @override
  Widget build(BuildContext context) => ArrBulkMonitorSheet(
    kind: lidarrBulkKind,
    count: artists.length,
    startMonitored: lidarrBulkStartMonitored(artists),
    startNewItems: lidarrBulkStartNewItems(artists),
  );
}

/// The Profile sheet's body for [artists], over the profiles of the Lidarr
/// [instanceId]: see [ArrBulkProfileSheet].
class LidarrBulkProfileSheet extends ConsumerWidget {
  const LidarrBulkProfileSheet({
    super.key,
    required this.artists,
    required this.instanceId,
  });

  final List<LidarrArtist> artists;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ArrBulkProfileSheet(
    kind: lidarrBulkKind,
    count: artists.length,
    sharedQuality: lidarrBulkSharedProfile(
      artists,
      (artist) => artist.qualityProfileId,
    ),
    sharedMetadata: lidarrBulkSharedProfile(
      artists,
      (artist) => artist.metadataProfileId,
    ),
    options: ref
        .watch(lidarrAddOptionsProvider(instanceId))
        .whenDataKept(
          (options) => (
            quality: [
              for (final profile in options.qualityProfiles)
                (id: profile.id, name: profile.name, detail: null),
            ],
            metadata: [
              for (final profile in options.metadataProfiles)
                (id: profile.id, name: profile.name, detail: profile.typesLine),
            ],
          ),
        ),
    instanceId: instanceId,
    onRetry: () => ref.invalidate(lidarrAddOptionsProvider(instanceId)),
  );
}
