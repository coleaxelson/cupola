import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_monitor.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
  ServiceInstance? initial,
}) {
  assert(connections.isNotEmpty, 'nothing to add to');
  return AppBottomSheet.show<LidarrAddedArtist>(
    context: context,
    builder: (_) => LidarrAddArtistSheet(
      artist: artist,
      connections: connections,
      name: name,
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
    this.initial,
  });

  /// The lookup row: posted back as Lidarr's own metadata for the artist.
  final LidarrArtist artist;
  final List<ServiceInstance> connections;
  final String Function(ServiceInstance connection) name;
  final ServiceInstance? initial;

  @override
  ConsumerState<LidarrAddArtistSheet> createState() =>
      _LidarrAddArtistSheetState();
}

/// The rows a person can change away from the folder's defaults.
enum _Row { quality, metadata, monitor, newItems }

class _LidarrAddArtistSheetState extends ConsumerState<LidarrAddArtistSheet> {
  late ServiceInstance _to = widget.initial ?? widget.connections.first;

  /// The options the selections were last seeded from: a new answer (another
  /// connection, a Retry) seeds them again.
  LidarrAddOptions? _seededFrom;

  LidarrRootFolder? _folder;
  int? _qualityId;
  int? _metadataId;
  var _monitor = LidarrMonitor.all;

  /// `all`, `none`, or `new` when that is what the folder's defaults say.
  var _newItems = 'all';
  var _search = true;

  /// Whether the folder's defaults filled any row.
  var _defaultsApplied = false;

  /// What the person changed: the folder's defaults no longer describe it.
  final _touched = <_Row>{};

  var _adding = false;
  _Refusal? _refusal;

  String get _connectionName => widget.name(_to);

  /// Fills the rows the person has not touched from [folder]'s defaults.
  void _applyDefaults(LidarrRootFolder folder, LidarrAddOptions options) {
    _folder = folder;
    var applied = false;
    if (!_touched.contains(_Row.quality)) {
      final wanted = folder.defaultQualityProfileId;
      final known = options.qualityProfiles.any((p) => p.id == wanted);
      _qualityId = known ? wanted : options.qualityProfiles.first.id;
      applied |= known;
    }
    if (!_touched.contains(_Row.metadata)) {
      final wanted = folder.defaultMetadataProfileId;
      final known = options.metadataProfiles.any((p) => p.id == wanted);
      _metadataId = known ? wanted : options.metadataProfiles.first.id;
      applied |= known;
    }
    if (!_touched.contains(_Row.monitor)) {
      _monitor = folder.defaultMonitor ?? LidarrMonitor.all;
      applied |= folder.defaultMonitor != null;
    }
    if (!_touched.contains(_Row.newItems)) {
      _newItems = folder.defaultNewItemMonitor ?? 'all';
      applied |= folder.defaultNewItemMonitor != null;
    }
    _defaultsApplied = applied;
  }

  void _seed(LidarrAddOptions options) {
    _seededFrom = options;
    _touched.clear();
    _refusal = null;
    if (options.missing != null) return;
    _applyDefaults(options.folders.first, options);
  }

  Future<void> _pickFolder(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<String>(
      context,
      title: 'Folder',
      value: _folder?.path,
      currentLabel: _folder?.path ?? '',
      options: [
        for (final folder in options.folders)
          MediaDetailValueOption(
            value: folder.path,
            label: folder.path,
            detail: folder.freeSpace == null
                ? null
                : '${formatBytes(folder.freeSpace!)} free',
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _applyDefaults(
        options.folders.firstWhere((f) => f.path == picked.value),
        options,
      );
      _refusal = null;
    });
  }

  Future<void> _pickQuality(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: _qualityId,
      currentLabel: _qualityName(options) ?? '',
      options: [
        for (final profile in options.qualityProfiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _qualityId = picked.value;
      _touched.add(_Row.quality);
      _refusal = null;
    });
  }

  Future<void> _pickMetadata(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Metadata profile',
      value: _metadataId,
      currentLabel: _metadataOf(options)?.name ?? '',
      options: [
        for (final profile in options.metadataProfiles)
          MediaDetailValueOption(
            value: profile.id,
            label: profile.name,
            detail: profile.typesLine,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _metadataId = picked.value;
      _touched.add(_Row.metadata);
      _refusal = null;
    });
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
      _touched.add(_Row.monitor);
      _refusal = null;
    });
  }

  String? _qualityName(LidarrAddOptions options) => options.qualityProfiles
      .where((p) => p.id == _qualityId)
      .firstOrNull
      ?.name;

  LidarrMetadataProfile? _metadataOf(LidarrAddOptions options) =>
      options.metadataProfiles.where((p) => p.id == _metadataId).firstOrNull;

  /// Posts the add. On success the sheet resolves to the artist as Lidarr
  /// holds it; a refusal stays in the sheet, in Lidarr's words.
  Future<void> _add({required bool search}) async {
    final folder = _folder;
    final quality = _qualityId;
    final metadata = _metadataId;
    if (folder == null || quality == null || metadata == null) return;
    final to = _to;
    setState(() {
      _adding = true;
      _refusal = null;
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
      final name = widget.name(to);
      setState(() {
        _adding = false;
        _refusal = _Refusal(
          sentence: 'Could not add ${widget.artist.artistName} to $name.',
          // Lidarr's own words when it gave any ("This artist has already
          // been added"), otherwise why in the classified words.
          detail:
              failureServiceMessage(error) ??
              writeFailureReason(ServiceKey.lidarr, error, subject: name),
          reason: classifyConnectionFailure(error),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final artist = widget.artist;
    final options = ref.watch(lidarrAddOptionsProvider(_to.id));
    if (options.value case final loaded? when !identical(loaded, _seededFrom)) {
      _seed(loaded);
    }
    final loaded = options.value;
    final usable = loaded != null && loaded.missing == null;
    final search = _monitor != LidarrMonitor.none && _search;

    final Widget body = switch (options) {
      AsyncError(:final error) => AppErrorState.compact(
        error: error,
        service: ServiceKey.lidarr,
        instanceId: _to.id,
        onRetry: () => ref.invalidate(lidarrAddOptionsProvider(_to.id)),
      ),
      AsyncData(:final value) when value.missing != null => _Missing(
        sentence: '$_connectionName has no ${value.missing} yet.',
        remedy: 'Add one in $_connectionName, then come back.',
        name: _connectionName,
        onOpen: () => _openInLidarr(value.missing!),
      ),
      AsyncData(:final value) => _rows(value, room, search: search),
      _ => const _OptionsLoading(),
    };

    return PopScope(
      // Nothing closes the sheet while the add is out: it would answer to
      // nobody, and the artist would be on the server with no word of it.
      canPop: !_adding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(artist: artist, closeEnabled: !_adding),
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
              onSelected: _adding
                  ? (_) {}
                  : (connection) => setState(() {
                      _to = connection;
                      _seededFrom = null;
                      _refusal = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          body,
          if (usable && _defaultsApplied && _touched.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'The folder’s defaults, as set in Lidarr.',
              style: AppType.caption.copyWith(color: room.inkTertiary),
            ),
          ],
          // A post that failed: its sentence, and why, over the button.
          if (usable && _refusal != null) ...[
            const SizedBox(height: AppSpacing.md),
            _refusal!,
          ],
          // Nothing to press while the options failed or are missing: a
          // primary action that cannot work is not drawn.
          if (options.isLoading || usable) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: usable && !_adding ? () => _add(search: search) : null,
              style: mediaLeadStyle(context, null),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_adding)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.add_rounded, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      search ? 'Add and search' : 'Add to $_connectionName',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lidarr's own settings page for what is missing, at the address the
  /// connection is reached at now: away from home, the one at home would not
  /// open.
  Future<void> _openInLidarr(String missing) async {
    final base = ref.read(connectionReachProvider(_to.id))?.url ?? '';
    final path = missing == 'root folder'
        ? '/settings/mediamanagement'
        : '/settings/profiles';
    final target = Uri.tryParse(UrlUtils.buildUrl(base, path));
    final opened =
        target != null &&
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $_connectionName');
    }
  }

  Widget _rows(
    LidarrAddOptions options,
    CupolaRoom room, {
    required bool search,
  }) {
    final folder = _folder!;
    final metadata = _metadataOf(options);
    // Where a value stacks under its label it starts where the label does.
    final stacked = mediaStacked(context);
    final align = stacked ? TextAlign.start : TextAlign.end;
    return MediaGroup(
      children: [
        MediaValueRow(
          label: 'Folder',
          value: Column(
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                folder.path,
                textAlign: align,
                style: AppType.mono.copyWith(color: room.inkSecondary),
              ),
              if (folder.freeSpace case final free?)
                Text(
                  '${formatBytes(free)} free',
                  textAlign: align,
                  style: AppType.caption.copyWith(color: room.inkTertiary),
                ),
            ],
          ),
          onTap: options.folders.length > 1 && !_adding
              ? () => _pickFolder(options)
              : null,
        ),
        MediaValueRow(
          label: 'Quality profile',
          value: Text(
            _qualityName(options) ?? '',
            textAlign: align,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          onTap: options.qualityProfiles.length > 1 && !_adding
              ? () => _pickQuality(options)
              : null,
        ),
        MediaValueRow(
          label: 'Metadata profile',
          value: MediaChoiceValue(
            label: metadata?.name ?? '',
            meaning: metadata?.typesLine,
          ),
          onTap: options.metadataProfiles.length > 1 && !_adding
              ? () => _pickMetadata(options)
              : null,
        ),
        // Which albums, in Lidarr's words, with what each means.
        MediaValueRow(
          label: 'Monitor',
          value: MediaChoiceValue(
            label: _monitor.label,
            meaning: _monitor.meaning,
          ),
          onTap: _adding ? null : _pickMonitor,
        ),
        MediaSwitchRow(
          label: 'Monitor new albums',
          detail: 'New releases are added and searched for',
          value: _newItems != 'none',
          onChanged: _adding
              ? null
              : (on) => setState(() {
                  _newItems = on ? 'all' : 'none';
                  _touched.add(_Row.newItems);
                }),
        ),
        MediaSwitchRow(
          label: 'Search when added',
          detail: _monitor == LidarrMonitor.none
              ? 'Needs albums to monitor'
              : 'Lidarr looks for the albums it monitors',
          value: search,
          onChanged: _monitor == LidarrMonitor.none || _adding
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
            // Pulled into the corner: the glyph sits in a 44 target.
            Transform.translate(
              offset: const Offset(AppSpacing.row, -AppSpacing.sm),
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: closeEnabled
                    ? () => Navigator.of(context).maybePop()
                    : null,
                constraints: const BoxConstraints.tightFor(
                  width: DesignTokens.sizeTouch,
                  height: DesignTokens.sizeTouch,
                ),
              ),
            ),
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

/// The group of rows, while the options are being read.
class _OptionsLoading extends StatelessWidget {
  const _OptionsLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reading the options',
      child: ExcludeSemantics(
        child: MediaGroup(
          children: [
            for (var i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Row(
                  children: [
                    ShimmerPlaceholder.text(width: 96),
                    const Spacer(),
                    ShimmerPlaceholder.text(width: 72),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the sheet could not do: its sentence, and why under it. Amber unless
/// the server did not answer: a refusal is a fault, only silence is red.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.sentence, this.detail, this.reason});

  final String sentence;
  final String? detail;
  final ServiceFailureReason? reason;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sentence,
          style: AppType.row.copyWith(
            color: statusToneColor(
              Theme.of(context).colorScheme,
              surface: room.raised,
              switch (reason) {
                final reason? => failureTone(reason),
                null => StatusTone.warning,
              },
            ),
          ),
        ),
        if ((detail ?? '').isNotEmpty)
          Text(
            detail!,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
      ],
    );
  }
}

/// A Lidarr with nothing to file under or no profile to give: what is true,
/// and the way out, which is Lidarr's own settings.
class _Missing extends StatelessWidget {
  const _Missing({
    required this.sentence,
    required this.remedy,
    required this.name,
    required this.onOpen,
  });

  final String sentence;
  final String remedy;
  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Refusal(sentence: sentence),
        Text(
          remedy,
          style: AppType.meta
              .weight(FontWeight.w400)
              .copyWith(color: room.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ShelfOpenIn(name: name, onTap: onOpen),
      ],
    );
  }
}
