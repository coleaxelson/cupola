import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/music/domain/more_from_your_artists.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Whether there is a music source to ask: the operator's, and set up. Today
/// that is Lidarr alone; Discover's music (its shelf and the section of its
/// search) reads this and never names the service where it can avoid it, so
/// that another source joins by joining here.
///
/// The requester has none: Lidarr is the operator's, and her Discover finds
/// movies, series and people.
final hasMusicSourceProvider = Provider<bool>((ref) {
  if (ref.watch(audienceProvider) != Audience.operator) return false;
  return ref.watch(
    currentSettingsProvider.select(
      (s) => s.isServiceConfigured(ServiceKey.lidarr),
    ),
  );
});

/// What `More from your artists` shows: the albums Lidarr knows from the
/// library's artists that are out, not monitored and have no file.
///
/// Built from the two reads the Music wall already holds, its artists
/// ([musicProvider]) and every album ([musicAlbumsProvider], one read of
/// `/api/v1/album`, mapped off the main thread), so the albums are downloaded
/// once whichever surface asks first and every write that reads the library
/// again (an add, a monitor) moves the shelf too. Only the albums that stay are
/// kept: a library of thousands leaves a shelf of a few.
///
/// Empty without a music source; a failed read reaches the shelf, which says
/// nothing (an optional shelf is never a failure line). Not retried on its own,
/// as every Lidarr read.
final moreFromYourArtistsProvider =
    FutureProvider.autoDispose<MoreFromYourArtists>((ref) async {
      if (!ref.watch(hasMusicSourceProvider)) {
        return const MoreFromYourArtists.none();
      }
      final (artists, albums) = await (
        ref.watch(musicProvider.future),
        ref.watch(musicAlbumsProvider.future),
      ).wait;
      return MoreFromYourArtists.of(
        albums: albums,
        artists: artists,
        now: DateTime.now(),
      );
    }, retry: noProviderRetry);
