import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_search_hit.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/lidarr_add_parts.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// What the sheet resolves to when an album was added: the connection it went
/// to and the artist the album is under now, as that Lidarr holds them, or
/// null when the album was added and the artist could not be read after (the
/// add stands, and there is nothing to open).
typedef LidarrAddedAlbum = ({ServiceInstance connection, LidarrArtist? artist});

/// Opens [LidarrAddAlbumSheet] for [hit], an album Lidarr's search found.
///
/// [libraryArtist] is the artist when the library already holds them. Resolves
/// to what was added, null when the sheet closed without adding.
Future<LidarrAddedAlbum?> showLidarrAddAlbumSheet(
  BuildContext context, {
  required LidarrAlbumHit hit,
  required ServiceInstance connection,
  required String connectionName,
  LidarrArtist? libraryArtist,
}) {
  return AppBottomSheet.show<LidarrAddedAlbum>(
    context: context,
    builder: (_) => LidarrAddAlbumSheet(
      hit: hit,
      connection: connection,
      connectionName: connectionName,
      libraryArtist: libraryArtist,
    ),
  );
}

/// Adds one album Lidarr does not hold: the album, and with it the artist when
/// the library has not got them.
///
/// For an artist not in the library the sheet is the artist's add without the
/// artist's choices: the folder and the profiles they are filed under, and
/// whether Lidarr looks for the album now. Lidarr adds them and monitors only
/// this album, whatever the metadata profile (the post names the album, see
/// `LidarrService.addAlbum`); the profile starts on the folder's default, so
/// the rest of the artist's discography arrives unmonitored, and Lidarr's `None`
/// profile stays one of the choices.
///
/// For an artist already in the library there is nothing to choose but the
/// search: Lidarr adds the album under the folder and profiles the artist
/// already has.
class LidarrAddAlbumSheet extends ConsumerStatefulWidget {
  const LidarrAddAlbumSheet({
    super.key,
    required this.hit,
    required this.connection,
    required this.connectionName,
    this.libraryArtist,
  });

  final LidarrAlbumHit hit;
  final ServiceInstance connection;
  final String connectionName;

  /// The artist as the library holds them, or null when they are not in it.
  final LidarrArtist? libraryArtist;

  @override
  ConsumerState<LidarrAddAlbumSheet> createState() =>
      _LidarrAddAlbumSheetState();
}

class _LidarrAddAlbumSheetState extends ConsumerState<LidarrAddAlbumSheet>
    with LidarrAddChoices<LidarrAddAlbumSheet> {
  var _search = true;

  bool get _artistIsHeld => widget.libraryArtist != null;

  @override
  ServiceInstance get target => widget.connection;

  @override
  String get connectionName => widget.connectionName;

  Future<void> _add() async {
    final held = widget.libraryArtist;
    final LidarrNewArtistSetup? setup;
    if (held == null) {
      final folder = this.folder;
      final quality = qualityId;
      final metadata = metadataId;
      if (folder == null || quality == null || metadata == null) return;
      setup = LidarrNewArtistSetup(
        rootFolderPath: folder.path,
        qualityProfileId: quality,
        metadataProfileId: metadata,
      );
    } else {
      setup = null;
    }
    setState(() {
      adding = true;
      refusal = null;
    });
    try {
      final artist = await ref
          .read(lidarrServiceForProvider(widget.connection.id))
          .addAlbum(
            widget.hit,
            searchForNewAlbum: _search,
            libraryArtistId: held?.id,
            newArtist: setup,
          );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop<LidarrAddedAlbum>((connection: widget.connection, artist: artist));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        adding = false;
        refusal = refusalFor(
          error,
          sentence:
              'Could not add ${widget.hit.album.title} to $connectionName.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final hit = widget.hit;
    final options = _artistIsHeld
        ? null
        : ref.watch(lidarrAddOptionsProvider(widget.connection.id));
    if (options != null) seedFrom(options);
    final usable = _artistIsHeld || (options?.value?.missing == null);
    final ready = _artistIsHeld || (options?.value != null && usable);

    final searchRow = MediaSwitchRow(
      label: 'Search when added',
      detail: 'Lidarr looks for ${hit.album.title} right away',
      value: _search,
      onChanged: adding ? null : (on) => setState(() => _search = on),
    );
    final Widget body = options == null
        ? MediaGroup(children: [searchRow])
        : optionsBody(
            options,
            (value) =>
                MediaGroup(children: [...choiceRows(value, room), searchRow]),
          );

    return PopScope(
      // Nothing closes the sheet while the add is out: it would answer to
      // nobody, and the album would be on the server with no word of it.
      canPop: !adding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(hit: hit, closeEnabled: !adding),
          const SizedBox(height: AppSpacing.md),
          _ArtistNote(hit: hit, held: _artistIsHeld),
          const SizedBox(height: AppSpacing.md),
          body,
          if (ready && refusal != null) ...[
            const SizedBox(height: AppSpacing.md),
            refusal!,
          ],
          // Nothing to press while the options failed or are missing: a
          // primary action that cannot work is not drawn.
          if ((options?.isLoading ?? false) || ready) ...[
            const SizedBox(height: AppSpacing.lg),
            LidarrAddButton(
              onPressed: ready && !adding ? _add : null,
              adding: adding,
              label: _search ? 'Add and search' : 'Add to $connectionName',
            ),
          ],
        ],
      ),
    );
  }
}

/// `Your library doesn’t have The White Stripes yet. Lidarr adds them too, and
/// monitors only this album.`: the first sentence in blue, the line for a step
/// that is not a fault; or, for an artist the library holds, that Lidarr adds
/// the album and monitors it. No verb agrees with the artist's name.
class _ArtistNote extends StatelessWidget {
  const _ArtistNote({required this.hit, required this.held});

  final LidarrAlbumHit hit;
  final bool held;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = hit.artist.artistName;
    final lead = held
        ? 'Your library already has $name.'
        : 'Your library doesn’t have $name yet.';
    final rest = held
        ? 'Lidarr adds this album and monitors it.'
        : 'Lidarr adds them too, and monitors only this album.';
    final blue = statusToneColor(
      scheme,
      StatusTone.info,
      surface: room.fillQuiet,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: room.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.info_outline_rounded, size: 18, color: blue),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: lead,
                    style: TextStyle(color: blue),
                  ),
                  TextSpan(text: ' $rest'),
                ],
              ),
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The album as the search knows it: its cover, its title, who it is by, when
/// and what kind of release it is. Close at the end.
class _Header extends StatelessWidget {
  const _Header({required this.hit, required this.closeEnabled});

  final LidarrAlbumHit hit;
  final bool closeEnabled;

  static const double _cover = 72;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final album = hit.album;
    final source = ImageUtils.extractPosterUrl(
      album.images,
      // The catalog's own copy of the cover: nothing of the connection goes
      // with it.
      baseUrl: '',
      apiKey: '',
      coverTypes: const ['cover'],
    );
    final facts = joinDisplayParts([
      hit.artist.artistName,
      album.year,
      album.albumType,
    ]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: ShelfCover(
            art: source.url.isEmpty
                ? null
                : (url: source.url, headers: source.headers),
            size: const Size.square(_cover),
            fallback: Text(
              shelfInitials(album.title),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    album.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.section.copyWith(color: room.ink),
                  ),
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    facts,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        LidarrAddClose(enabled: closeEnabled),
      ],
    );
  }
}
