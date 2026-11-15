import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_album_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The connection's name inside a sentence (`Lidarr`, `Lidarr 4K`).
String _nameOf(WidgetRef ref, ServiceInstance connection) => ref
    .read(currentSettingsProvider)
    .connectionTitle(connection.id, connection.service, joiner: ' ');

/// What the library is read again for once Lidarr holds something new: the
/// wall, and the albums its search finds in.
void _readLibraryAgain(WidgetRef ref, ServiceInstance connection) {
  ref
    ..invalidate(musicProvider)
    ..invalidate(musicForProvider(connection.id))
    ..invalidate(musicAlbumsProvider);
}

/// Opens the artist Lidarr has just taken, waiting for it to read the albums.
/// Nothing opens when there is no artist to open: a write that went through
/// and left no artist to read is added all the same.
void _openAdded(
  BuildContext context,
  WidgetRef ref,
  ServiceInstance connection,
  LidarrArtist? artist,
) {
  if (artist == null || artist.id <= 0) return;
  final lens = ref.read(activeInstanceProvider(ServiceKey.lidarr));
  unawaited(
    context.push(
      ServiceRoutes.lidarrArtist(
        artist.id,
        instanceId: connection.id == lens?.id ? null : connection.id,
        justAdded: true,
      ),
      extra: artist,
    ),
  );
}

/// Adds [lookupRow], an artist the search found and no Lidarr holds, through
/// the add sheet; then says so, reads the library again and opens the new
/// artist's page, which waits for Lidarr to read the albums.
Future<void> addLidarrArtist(
  BuildContext context,
  WidgetRef ref,
  LidarrArtist lookupRow,
) async {
  final settings = ref.read(currentSettingsProvider);
  final lens = ref.read(activeInstanceProvider(ServiceKey.lidarr));
  // The pills read the connection as a chip does, every sentence as a
  // sentence does.
  String name(ServiceInstance connection) =>
      settings.connectionTitle(connection.id, connection.service);
  String sentenceName(ServiceInstance connection) => _nameOf(ref, connection);
  final connections = settings.configuredInstancesOf(ServiceKey.lidarr);
  if (connections.isEmpty) return;
  final added = await showLidarrAddArtistSheet(
    context,
    artist: lookupRow,
    connections: connections,
    name: name,
    sentenceName: sentenceName,
    initial: lens,
  );
  if (added == null || !context.mounted) return;
  SnackBarHelper.success(
    context,
    '${added.artist.artistName} added to ${sentenceName(added.connection)}',
  );
  // The library now holds the artist: the rows of the search that were not
  // in it are read against the new one.
  _readLibraryAgain(ref, added.connection);
  if (!context.mounted) return;
  _openAdded(context, ref, added.connection, added.artist);
}

/// Adds the album [hit] found, and its artist with it when the library has not
/// got them ([libraryArtist] null), through the sheet; then says so, reads the
/// library again and opens the artist's page, which waits for Lidarr to read
/// the albums.
Future<void> addLidarrAlbum(
  BuildContext context,
  WidgetRef ref,
  LidarrAlbumHit hit, {
  LidarrArtist? libraryArtist,
}) async {
  final lens = ref.read(activeInstanceProvider(ServiceKey.lidarr));
  if (lens == null) return;
  final added = await showLidarrAddAlbumSheet(
    context,
    hit: hit,
    connection: lens,
    connectionName: _nameOf(ref, lens),
    libraryArtist: libraryArtist,
  );
  if (added == null || !context.mounted) return;
  SnackBarHelper.success(
    context,
    '${hit.album.title} added to ${_nameOf(ref, added.connection)}',
  );
  _readLibraryAgain(ref, added.connection);
  if (!context.mounted) return;
  _openAdded(context, ref, added.connection, added.artist);
}
