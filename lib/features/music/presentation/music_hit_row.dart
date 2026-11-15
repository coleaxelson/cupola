import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/album_kind.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/domain/music_held.dart';
import 'package:cupola/features/music/presentation/music_add_flow.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_reach.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// One row of Lidarr's search: an artist or an album the catalog found, with
/// where it stands in the library and what to do about it. The Music wall's
/// Lidarr scope and Discover's Music section draw their rows with it, so a row
/// says and does the same in both.
///
/// Held by the library, the row says so (`In your library` for an artist, the
/// album's own state word for an album: one album, one word everywhere) and
/// opens the artist's page, on the album for an album. Not held, it carries
/// the plus that adds it through the sheet lot 1 built for artists and the
/// album's own; an album the library holds and left alone carries one that
/// monitors it and searches. Held is decided by MusicBrainz id against the
/// library ([MusicHeld]), the way Lidarr's own search does.
///
/// [MusicHitRow.sectioned] sits under a heading that says what it is (`Artists`,
/// `Albums`), so its line leaves the kind out; [MusicHitRow.mixed] sits among
/// rows of both, and its line leads with the kind (`Album · Jan Morgenstern ·
/// 2010`, `Artist · Group · Bury, England`).
class MusicHitRow extends ConsumerStatefulWidget {
  const MusicHitRow.sectioned({
    super.key,
    required this.hit,
    required this.held,
  }) : _mixed = false;

  const MusicHitRow.mixed({super.key, required this.hit, required this.held})
    : _mixed = true;

  final LidarrSearchHit hit;

  /// What the library holds, to tell the row held from not.
  final MusicHeld held;

  final bool _mixed;

  @override
  ConsumerState<MusicHitRow> createState() => _MusicHitRowState();
}

class _MusicHitRowState extends ConsumerState<MusicHitRow> {
  /// The album is being monitored: the plus is busy, and inert.
  var _monitoring = false;

  void _open(LidarrArtist artist, {LidarrAlbum? album}) {
    context.push(
      ServiceRoutes.lidarrArtist(artist.id, albumId: album?.id),
      extra: artist,
    );
  }

  Future<void> _monitor(LidarrAlbum album, String name) async {
    setState(() => _monitoring = true);
    try {
      await ref.read(lidarrServiceProvider).monitorAndSearchAlbum(album.id);
      if (!mounted) return;
      SnackBarHelper.success(context, '$name is looking for ${album.title}');
      ref.invalidate(musicAlbumsProvider);
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not monitor ${album.title} in $name.',
        detail: error,
      );
    } finally {
      if (mounted) setState(() => _monitoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = watchMusicName(ref);
    final reach = watchMusicReach(ref);
    return switch (widget.hit) {
      final LidarrArtistHit hit => _artist(hit, name, reach),
      final LidarrAlbumHit hit => _album(hit, name, reach),
    };
  }

  Widget _artist(LidarrArtistHit hit, String name, MusicReach reach) {
    final artist = hit.artist;
    final held = widget.held.artistOf(artist);
    final art = musicArtOf((held ?? artist).images, musicArtistArt, reach);
    final add = held == null
        ? () => addLidarrArtist(context, ref, artist)
        : null;
    final type = artist.artistType;
    return SearchRow.disc(
      key: ValueKey((
        'found-artist',
        artist.foreignArtistId,
        artist.artistName,
      )),
      name: artist.artistName,
      line: joinDisplayParts([
        if (widget._mixed) 'Artist',
        type,
        artist.disambiguation,
      ]),
      status: held == null ? null : _inLibrary,
      photo: art.url,
      photoHeaders: art.headers,
      spoken: widget._mixed
          ? joinDisplayParts([
              artist.artistName,
              type?.toLowerCase(),
              (held == null ? 'not in your library' : 'in your library'),
            ], separator: ', ')
          : null,
      hint: held == null
          ? 'Not in your library. Adds it to $name'
          : 'Opens their page',
      onTap: held == null ? add! : () => _open(held),
      action: held == null
          ? SearchRowAdd(
              label: 'Add ${artist.artistName} to $name',
              onTap: add!,
            )
          : null,
    );
  }

  Widget _album(LidarrAlbumHit hit, String name, MusicReach reach) {
    final album = hit.album;
    final heldAlbum = widget.held.albumOf(hit);
    final heldArtist = widget.held.artistOf(hit.artist);
    // A held album opens the artist the library keeps it under.
    final albumsArtist = heldAlbum == null
        ? null
        : widget.held.artistOfAlbum(heldAlbum);
    final queue = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsProvider),
    ).byAlbum;
    final state = heldAlbum == null
        ? null
        : albumState(heldAlbum, queue: queue, now: DateTime.now());
    final leftAlone = state?.word == albumUnmonitoredWord;
    final art = musicArtOf((heldAlbum ?? album).images, musicAlbumArt, reach);
    void add() => addLidarrAlbum(context, ref, hit, libraryArtist: heldArtist);
    final SearchRowAction? action = heldAlbum == null
        ? SearchRowAdd(
            label: 'Add ${album.title} by ${hit.artist.artistName} to $name',
            onTap: add,
          )
        : leftAlone
        ? SearchRowAdd(
            label: 'Monitor ${album.title} and search for it',
            busy: _monitoring,
            onTap: () => _monitor(heldAlbum, name),
          )
        : null;
    // The kind in a mixed list: what the catalog calls it, `Album` where it
    // calls it nothing.
    final kind = AlbumKind.of(album);
    final typed = album.albumType != null;
    return SearchRow.album(
      key: ValueKey(('found-album', album.foreignAlbumId)),
      title: album.title,
      meta: widget._mixed
          ? joinDisplayParts([
              typed ? kind.fact : 'Album',
              hit.artist.artistName,
              album.year,
            ])
          : joinDisplayParts([
              hit.artist.artistName,
              album.year,
              album.albumType,
            ]),
      status: state == null ? null : (label: state.word, tone: state.tone),
      statusHollow: state?.hollow ?? false,
      cover: art.url,
      coverHeaders: art.headers,
      spoken: widget._mixed
          ? joinDisplayParts([
              album.title,
              '${typed ? kind.noun : 'album'} by ${hit.artist.artistName}',
              album.year,
              state == null
                  ? 'not in your library'
                  : splitParts(state.word).join(', '),
            ], separator: ', ')
          : null,
      hint: heldAlbum == null
          ? 'Not in your library. Adds it to $name'
          : albumsArtist == null
          ? null
          : 'Opens ${albumsArtist.artistName}',
      onTap: heldAlbum != null
          ? (albumsArtist == null
                ? () {}
                : () => _open(albumsArtist, album: heldAlbum))
          : add,
      action: action,
    );
  }

  static final ({String label, StatusTone tone}) _inLibrary = (
    label: StateWord.inYourLibrary.label,
    tone: StateWord.inYourLibrary.tone!,
  );
}
