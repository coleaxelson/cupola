import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_monitor.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/lidarr_add_parts.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// What the sheet resolves to when an artist was added: the connection it went
/// to and the artist as that Lidarr now holds it (its own id, no albums read
/// yet).
typedef LidarrAddedArtist = ({ServiceInstance connection, LidarrArtist artist});

/// Opens [LidarrAddArtistSheet] for [artist], a row of Lidarr's artist lookup.
///
/// [connections] are the Lidarr connections set up, [initial] (else the first)
/// the one the sheet opens on. Resolves to the artist that was added, null when
/// the sheet closed without adding.
Future<LidarrAddedArtist?> showLidarrAddArtistSheet(
  BuildContext context, {
  required LidarrArtist artist,
  required List<ServiceInstance> connections,
  required String Function(ServiceInstance connection) name,
  String Function(ServiceInstance connection)? sentenceName,
  ServiceInstance? initial,
}) {
  assert(connections.isNotEmpty, 'nothing to add to');
  return AppBottomSheet.show<LidarrAddedArtist>(
    context: context,
    builder: (_) => LidarrAddArtistSheet(
      artist: artist,
      connections: connections,
      name: name,
      sentenceName: sentenceName,
      initial: initial,
    ),
  );
}

/// Adds an artist nobody holds to Lidarr: which Lidarr, the folder it is filed
/// under, its quality and metadata profiles, which albums Lidarr looks for and
/// whether it searches now.
///
/// The body of the sheet, header included ([showLidarrAddArtistSheet] opens
/// it): the artist's photo and what is known of them, then the rows. Every row
/// starts on what the chosen folder's defaults say in Lidarr, the defaults the
/// web app's own add form starts on. A row is a picker only when there is more
/// than one thing to choose from; the connections are pills only when there is
/// more than one.
class LidarrAddArtistSheet extends ConsumerStatefulWidget {
  const LidarrAddArtistSheet({
    super.key,
    required this.artist,
    required this.connections,
    required this.name,
    String Function(ServiceInstance connection)? sentenceName,
    this.initial,
  }) : sentenceName = sentenceName ?? name;

  /// The lookup row: posted back as Lidarr's own metadata for the artist.
  final LidarrArtist artist;
  final List<ServiceInstance> connections;

  /// The connection's name as a pill reads it (`Lidarr · Away`).
  final String Function(ServiceInstance connection) name;

  /// The connection's name inside a sentence or a button (`Lidarr Away`):
  /// the pills' form, unless the caller gives one.
  final String Function(ServiceInstance connection) sentenceName;
  final ServiceInstance? initial;

  @override
  ConsumerState<LidarrAddArtistSheet> createState() =>
      _LidarrAddArtistSheetState();
}

class _LidarrAddArtistSheetState extends ConsumerState<LidarrAddArtistSheet>
    with LidarrAddChoices<LidarrAddArtistSheet> {
  late ServiceInstance _to = widget.initial ?? widget.connections.first;

  var _monitor = LidarrMonitor.all;

  /// `all`, `none`, or `new` when that is what the folder's defaults say.
  var _newItems = 'all';
  var _search = true;

  @override
  ServiceInstance get target => _to;

  @override
  String get connectionName => widget.sentenceName(_to);

  @override
  void applyDefaults(LidarrRootFolder folder, LidarrAddOptions options) {
    var applied = applyFolderDefaults(folder, options);
    if (!touched.contains(LidarrAddRow.monitor)) {
      _monitor = folder.defaultMonitor ?? LidarrMonitor.all;
      applied |= folder.defaultMonitor != null;
    }
    if (!touched.contains(LidarrAddRow.newItems)) {
      _newItems = folder.defaultNewItemMonitor ?? 'all';
      applied |= folder.defaultNewItemMonitor != null;
    }
    defaultsApplied = applied;
  }

  Future<void> _pickMonitor() async {
    final picked = await showMediaValueSheet<LidarrMonitor>(
      context,
      title: 'Monitor',
      value: _monitor,
      currentLabel: _monitor.label,
      options: [
        for (final monitor in LidarrMonitor.values)
          MediaDetailValueOption(
            value: monitor,
            label: monitor.label,
            detail: monitor.meaning,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _monitor = picked.value;
      touched.add(LidarrAddRow.monitor);
      refusal = null;
    });
  }

  /// Posts the add. On success the sheet resolves to the artist as Lidarr
  /// holds it; a refusal stays in the sheet, in Lidarr's words.
  Future<void> _add({required bool search}) async {
    final folder = this.folder;
    final quality = qualityId;
    final metadata = metadataId;
    if (folder == null || quality == null || metadata == null) return;
    final to = _to;
    setState(() {
      adding = true;
      refusal = null;
    });
    try {
      final added = await ref
          .read(lidarrServiceForProvider(to.id))
          .addArtist(
            widget.artist,
            qualityProfileId: quality,
            metadataProfileId: metadata,
            rootFolderPath: folder.path,
            monitor: _monitor.wireValue,
            monitorNewItems: _newItems,
            searchForMissingAlbums: search,
          );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop<LidarrAddedArtist>((connection: to, artist: added));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        adding = false;
        refusal = refusalFor(
          error,
          sentence:
              'Could not add ${widget.artist.artistName} to '
              '${widget.sentenceName(to)}.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final artist = widget.artist;
    final options = ref.watch(lidarrAddOptionsProvider(_to.id));
    seedFrom(options);
    final loaded = options.value;
    final usable = loaded != null && loaded.missing == null;
    final search = _monitor != LidarrMonitor.none && _search;

    return PopScope(
      // Nothing closes the sheet while the add is out: it would answer to
      // nobody, and the artist would be on the server with no word of it.
      canPop: !adding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(artist: artist, closeEnabled: !adding),
          const SizedBox(height: AppSpacing.lg),
          if (widget.connections.length > 1) ...[
            Text(
              'Instance',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectionPills<ServiceInstance>.wrap(
              values: widget.connections,
              selected: _to,
              labelBuilder: widget.name,
              onSelected: adding
                  ? (_) {}
                  : (connection) => setState(() {
                      _to = connection;
                      seededFrom = null;
                      refusal = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          optionsBody(options, (value) => _rows(value, room, search: search)),
          if (usable && defaultsApplied && touched.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'The folder’s defaults, as set in Lidarr.',
              style: AppType.caption.copyWith(color: room.inkTertiary),
            ),
          ],
          // A post that failed: its sentence, and why, over the button.
          if (usable && refusal != null) ...[
            const SizedBox(height: AppSpacing.md),
            refusal!,
          ],
          // Nothing to press while the options failed or are missing: a
          // primary action that cannot work is not drawn.
          if (options.isLoading || usable) ...[
            const SizedBox(height: AppSpacing.lg),
            LidarrAddButton(
              onPressed: usable && !adding ? () => _add(search: search) : null,
              adding: adding,
              label: search ? 'Add and search' : 'Add to $connectionName',
            ),
          ],
        ],
      ),
    );
  }

  Widget _rows(
    LidarrAddOptions options,
    CupolaRoom room, {
    required bool search,
  }) {
    return MediaGroup(
      children: [
        ...choiceRows(options, room),
        // Which albums, in Lidarr's words, with what each means.
        MediaValueRow(
          label: 'Monitor',
          value: MediaChoiceValue(
            label: _monitor.label,
            meaning: _monitor.meaning,
          ),
          onTap: adding ? null : _pickMonitor,
        ),
        MediaSwitchRow(
          label: 'Monitor new albums',
          detail: 'New releases are added and searched for',
          value: _newItems != 'none',
          onChanged: adding
              ? null
              : (on) => setState(() {
                  _newItems = on ? 'all' : 'none';
                  touched.add(LidarrAddRow.newItems);
                }),
        ),
        MediaSwitchRow(
          label: 'Search when added',
          detail: _monitor == LidarrMonitor.none
              ? 'Needs albums to monitor'
              : 'Lidarr looks for the albums it monitors',
          value: search,
          onChanged: _monitor == LidarrMonitor.none || adding
              ? null
              : (on) => setState(() => _search = on),
        ),
      ],
    );
  }
}

/// The artist, as the lookup knows them: the photo (their initials without
/// one), the name, what kind of artist and how to tell them from another of
/// the name, and what is written of them, two lines of it. Close at the end.
class _Header extends StatelessWidget {
  const _Header({required this.artist, required this.closeEnabled});

  final LidarrArtist artist;
  final bool closeEnabled;

  static const double _disc = 64;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final source = ImageUtils.extractPosterUrl(
      artist.images,
      // A lookup row's artwork is Lidarr's remote copy, fetched from where it
      // lives: nothing of the connection goes with it.
      baseUrl: '',
      apiKey: '',
      coverTypes: const ['poster', 'fanart', 'banner'],
    );
    final facts = [
      for (final part in [artist.artistType, artist.disambiguation])
        if (part != null && part.trim().isNotEmpty) part.trim(),
    ].join(dotSeparator);
    final overview = artist.overview?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _disc,
              height: _disc,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: room.fillQuiet,
                border: Border.all(color: room.hair),
              ),
              clipBehavior: Clip.antiAlias,
              child: ExcludeSemantics(
                child: ShelfArtwork(
                  art: source.url.isEmpty
                      ? null
                      : (url: source.url, headers: source.headers),
                  box: const Size.square(_disc),
                  fallback: Text(
                    shelfInitials(artist.artistName),
                    style: AppType.label.copyWith(color: room.inkSecondary),
                  ),
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
                        artist.artistName,
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
        ),
        if (overview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            overview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
        ],
      ],
    );
  }
}
