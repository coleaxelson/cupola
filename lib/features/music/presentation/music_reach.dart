import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The cover types an artist's picture is taken from, in order.
const musicArtistArt = ['poster', 'fanart', 'banner'];

/// The cover type an album's picture is.
const musicAlbumArt = ['cover'];

/// Where Lidarr's artwork is read from and with what key.
typedef MusicReach = ({String baseUrl, String apiKey});

/// The lens's connection at the address it is reached at now: where the
/// artwork of what the lens holds is fetched.
MusicReach watchMusicReach(WidgetRef ref) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
  final route = ref.watch(connectionRouteProvider(lens));
  final (baseUrl, apiKey, _) = ref.watch(
    currentSettingsProvider.select((s) => s.artworkKeyOf(lens, route)),
  );
  return (baseUrl: baseUrl, apiKey: apiKey);
}

/// The picture among [images] that [types] ask for, on [reach].
ImageSource musicArtOf(
  List<dynamic> images,
  List<String> types,
  MusicReach reach,
) => ImageUtils.extractPosterUrl(
  images,
  baseUrl: reach.baseUrl,
  apiKey: reach.apiKey,
  coverTypes: types,
);

/// What the Music wall's name for the connection reads inside a sentence
/// (`Lidarr`, `Lidarr 4K`).
String watchMusicName(WidgetRef ref) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr));
  final settings = ref.watch(currentSettingsProvider);
  return settings.connectionTitle(
    lens?.id ?? '',
    ServiceKey.lidarr,
    joiner: ' ',
  );
}
