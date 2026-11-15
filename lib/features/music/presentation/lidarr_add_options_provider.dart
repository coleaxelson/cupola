import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/parallel_reads.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';

/// What one Lidarr offers a new artist: its root folders and their defaults,
/// its quality profiles and its metadata profiles, read when the add sheet
/// opens on it.
///
/// A failure reaches the sheet, which says who did not answer and offers
/// Retry; nothing retries on its own. The reads travel (see
/// `LidarrService.getQualityProfilesOrThrow`): a Lidarr that did not answer
/// must not read as a Lidarr with no folder.
final lidarrAddOptionsProvider = FutureProvider.autoDispose
    .family<LidarrAddOptions, String>((ref, instanceId) async {
      final service = ref.watch(lidarrServiceForProvider(instanceId));
      final (folders, profiles, metadata) = await readTogether3(
        service.getRootFolders(),
        service.getQualityProfilesOrThrow(),
        service.getMetadataProfiles(),
      );
      return LidarrAddOptions(
        folders: [
          for (final folder in folders) ?LidarrRootFolder.tryParse(folder),
        ],
        qualityProfiles: [
          for (final profile in profiles)
            if (profile['id'] is int)
              (
                id: profile['id'] as int,
                name: profile['name'] as String? ?? 'Profile',
              ),
        ],
        metadataProfiles: metadata,
      );
    }, retry: noProviderRetry);
