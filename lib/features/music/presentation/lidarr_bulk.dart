import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/count_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_bulk.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What Lidarr's wall can do to several artists at once: search, monitor, set
/// the profiles, remove. The selection bar's four actions, each asking what it
/// needs before it runs.
///
/// [name] is the connection as a sentence says it (`Lidarr`, `Lidarr 4K`);
/// [instanceId] the connection the wall reads (empty for the lens's). The
/// actions read their service through [ref] when they run, so a wall that
/// outlives a connection change writes where it is looking.
///
/// [dialogsOnRoot] is where the confirmation opens: on the app's root
/// navigator, so it covers the bar and the tabs. A catalog scene, which has no
/// navigator above it to look at, opens it on its own.
MediaBulk<LidarrArtist> lidarrBulk({
  required WidgetRef ref,
  required String instanceId,
  required String name,
  void Function(WidgetRef ref)? onChanged,
  bool dialogsOnRoot = true,
}) {
  LidarrService service() => ref.read(lidarrServiceForProvider(instanceId));
  late final MediaBulk<LidarrArtist> bulk;

  MediaBulkJob<LidarrArtist> job({
    required Future<LidarrBulkResult> Function(List<int> ids) run,
    required String Function(int count) doneLine,
    required String Function(int done, int total) partialLine,
  }) => MediaBulkJob<LidarrArtist>(
    run: (items) async => _outcome(items, name, await run(_ids(items))),
    doneLine: doneLine,
    partialLine: partialLine,
  );

  String updated(int done, int total) =>
      '${formatCount(done)} of ${bulk.countOf(total)} updated';

  bulk = MediaBulk<LidarrArtist>(
    singular: 'artist',
    plural: 'artists',
    noneHint: 'Select an artist first',
    service: ServiceKey.lidarr,
    instanceId: instanceId,
    onChanged: onChanged,
    actions: [
      // A search starts nothing to ask about: it runs.
      MediaBulkAction<LidarrArtist>(
        label: 'Search',
        icon: Icons.search_rounded,
        prepare: (context, artists) async => job(
          run: service().searchArtistsInBulk,
          doneLine: (count) => '$name is searching ${bulk.countOf(count)}',
          partialLine: (done, total) =>
              '$name is searching ${formatCount(done)} of ${bulk.countOf(total)}',
        ),
      ),
      MediaBulkAction<LidarrArtist>(
        label: 'Monitor',
        icon: Icons.visibility_rounded,
        prepare: (context, artists) async {
          final edit = await AppBottomSheet.show<LidarrArtistEdit>(
            context: context,
            title: 'Monitor ${bulk.countOf(artists.length)}',
            subtitle: lidarrBulkNames(artists),
            builder: (_) => LidarrBulkMonitorSheet(artists: artists),
          );
          if (edit == null) return null;
          return job(
            run: (ids) => service().updateArtistsInBulk(ids, edit),
            doneLine: (count) => 'Updated ${bulk.countOf(count)}',
            partialLine: updated,
          );
        },
      ),
      MediaBulkAction<LidarrArtist>(
        label: 'Profile',
        icon: Icons.tune_rounded,
        prepare: (context, artists) async {
          final edit = await AppBottomSheet.show<LidarrArtistEdit>(
            context: context,
            title: 'Profiles for ${bulk.countOf(artists.length)}',
            subtitle: lidarrBulkNames(artists),
            builder: (_) => LidarrBulkProfileSheet(
              artists: artists,
              instanceId: instanceId,
            ),
          );
          if (edit == null) return null;
          return job(
            run: (ids) => service().updateArtistsInBulk(ids, edit),
            doneLine: (count) => 'Updated ${bulk.countOf(count)}',
            partialLine: updated,
          );
        },
      ),
      MediaBulkAction<LidarrArtist>(
        label: 'Remove',
        icon: Icons.delete_outline_rounded,
        prepare: (context, artists) async {
          final removal = await showLidarrBulkRemoveDialog(
            context,
            artists: artists,
            name: name,
            useRootNavigator: dialogsOnRoot,
          );
          if (removal == null) return null;
          return job(
            run: (ids) => service().removeArtistsInBulk(
              ids,
              deleteFiles: removal.deleteFiles,
              addImportListExclusion: removal.addImportListExclusion,
            ),
            doneLine: (count) => 'Removed ${bulk.countOf(count)} from $name',
            partialLine: (done, total) =>
                '${formatCount(done)} of ${bulk.countOf(total)} removed',
          );
        },
      ),
    ],
  );
  return bulk;
}

List<int> _ids(List<LidarrArtist> artists) => [
  for (final artist in artists) artist.id,
];

/// What Lidarr said of each artist, as the wall tells it: the artists it took
/// and, for each it refused, a line in its words that names the artist.
MediaBulkOutcome _outcome(
  List<LidarrArtist> artists,
  String name,
  LidarrBulkResult result,
) => MediaBulkOutcome(
  done: result.done,
  failures: [
    for (final artist in artists)
      if (result.refused[artist.id] case final error?)
        MediaBulkFailure(
          id: artist.id,
          name: artist.artistName,
          line: lidarrRefusalLine(artist.artistName, error, name),
          error: error,
        ),
  ],
);

/// One refusal as a sentence: `Lidarr refused Miles Davis: the folder is not
/// reachable.`, in Lidarr's own words when it gave any. A request that never
/// got an answer has no words of Lidarr's, and says why in the classified ones
/// after the name, which is all that can be said of it.
String lidarrRefusalLine(String artist, Object error, String name) {
  final said = failureServiceMessage(error);
  if (said != null) {
    final sentence = said.endsWith('.') ? said : '$said.';
    return '$name refused $artist: $sentence';
  }
  return '$artist: ${writeFailureReason(ServiceKey.lidarr, error, subject: name)}';
}

/// The artists a sheet is for, as it names them under its title: `Bill Evans,
/// Brian Eno and Miles Davis`, and past three `Bill Evans, Brian Eno and 12
/// more`.
String lidarrBulkNames(List<LidarrArtist> artists) {
  final names = [for (final artist in artists) artist.artistName];
  return switch (names.length) {
    0 => '',
    1 => names.first,
    2 => '${names.first} and ${names.last}',
    3 => '${names[0]}, ${names[1]} and ${names[2]}',
    _ => '${names[0]}, ${names[1]} and ${formatCount(names.length - 2)} more',
  };
}

/// What the Monitor sheet starts on for [artists]: what they all have when
/// they agree, and otherwise Monitor.
bool lidarrBulkStartMonitored(List<LidarrArtist> artists) =>
    artists.any((artist) => artist.monitored);

/// The albums-to-come setting the Monitor sheet starts on: `all` or `none`
/// when every artist has it, and otherwise null, `Leave as is`.
String? lidarrBulkStartNewItems(List<LidarrArtist> artists) {
  final first = artists.firstOrNull?.monitorNewItems;
  if (first != 'all' && first != 'none') return null;
  return artists.every((artist) => artist.monitorNewItems == first)
      ? first
      : null;
}

/// The profile every artist of [artists] has, by [of], or null when they
/// differ or one does not say.
int? lidarrBulkSharedProfile(
  List<LidarrArtist> artists,
  int? Function(LidarrArtist artist) of,
) {
  final first = artists.firstOrNull == null ? null : of(artists.first);
  if (first == null) return null;
  return artists.every((artist) => of(artist) == first) ? first : null;
}

/// The Monitor sheet's body: whether to monitor, and what to do with albums
/// that come later. Resolves to the edit it makes.
///
/// Starts on what the selection already has when it all agrees, otherwise on
/// Monitor and Leave as is. `Apply` is always there: choosing is the point.
class LidarrBulkMonitorSheet extends StatefulWidget {
  const LidarrBulkMonitorSheet({super.key, required this.artists});

  final List<LidarrArtist> artists;

  @override
  State<LidarrBulkMonitorSheet> createState() => _LidarrBulkMonitorSheetState();
}

class _LidarrBulkMonitorSheetState extends State<LidarrBulkMonitorSheet> {
  late bool _monitored = lidarrBulkStartMonitored(widget.artists);

  /// `all`, `none`, or null for Leave as is.
  late String? _newItems = lidarrBulkStartNewItems(widget.artists);

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final count = formatCount(widget.artists.length);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTabs<bool>(
          semanticLabel: 'Monitor or stop monitoring',
          values: const [true, false],
          selected: _monitored,
          labelBuilder: (monitored) =>
              monitored ? 'Monitor' : 'Stop monitoring',
          onSelected: (monitored) => setState(() => _monitored = monitored),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'Monitor new albums',
            style: AppType.label.copyWith(color: room.inkSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PageTabs<String?>(
          semanticLabel: 'Monitor new albums',
          values: const [null, 'all', 'none'],
          selected: _newItems,
          labelBuilder: (value) => switch (value) {
            'all' => 'All',
            'none' => 'None',
            _ => 'Leave as is',
          },
          onSelected: (value) => setState(() => _newItems = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          style: mediaLeadStyle(context, null),
          onPressed: () => Navigator.of(context).pop(
            LidarrArtistEdit(monitored: _monitored, monitorNewItems: _newItems),
          ),
          child: Text(
            'Apply to $count ${widget.artists.length == 1 ? 'artist' : 'artists'}',
          ),
        ),
      ],
    );
  }
}

/// The Profile sheet's body: a quality profile and a metadata profile for the
/// whole selection, each started on what they all have or Leave as is, and
/// `Apply`, which is there only when something is going to change.
class LidarrBulkProfileSheet extends ConsumerStatefulWidget {
  const LidarrBulkProfileSheet({
    super.key,
    required this.artists,
    required this.instanceId,
  });

  final List<LidarrArtist> artists;
  final String instanceId;

  @override
  ConsumerState<LidarrBulkProfileSheet> createState() =>
      _LidarrBulkProfileSheetState();
}

class _LidarrBulkProfileSheetState
    extends ConsumerState<LidarrBulkProfileSheet> {
  late final int? _sharedQuality = lidarrBulkSharedProfile(
    widget.artists,
    (artist) => artist.qualityProfileId,
  );
  late final int? _sharedMetadata = lidarrBulkSharedProfile(
    widget.artists,
    (artist) => artist.metadataProfileId,
  );

  /// The choice on each row: null is Leave as is.
  late int? _quality = _sharedQuality;
  late int? _metadata = _sharedMetadata;

  /// What is going to be written: a profile chosen that is not what they all
  /// have already.
  LidarrArtistEdit get _edit => LidarrArtistEdit(
    qualityProfileId: _quality != _sharedQuality ? _quality : null,
    metadataProfileId: _metadata != _sharedMetadata ? _metadata : null,
  );

  Future<void> _pickQuality(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int?>(
      context,
      title: 'Quality profile',
      value: _quality,
      currentLabel: _qualityName(options),
      options: [
        const MediaDetailValueOption(value: null, label: 'Leave as is'),
        for (final profile in options.qualityProfiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _quality = picked.value);
  }

  Future<void> _pickMetadata(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int?>(
      context,
      title: 'Metadata profile',
      value: _metadata,
      currentLabel: _metadataName(options),
      options: [
        const MediaDetailValueOption(value: null, label: 'Leave as is'),
        for (final profile in options.metadataProfiles)
          MediaDetailValueOption(
            value: profile.id,
            label: profile.name,
            detail: profile.typesLine,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _metadata = picked.value);
  }

  String _qualityName(LidarrAddOptions options) =>
      options.qualityProfiles
          .where((profile) => profile.id == _quality)
          .firstOrNull
          ?.name ??
      'Leave as is';

  String _metadataName(LidarrAddOptions options) =>
      options.metadataProfiles
          .where((profile) => profile.id == _metadata)
          .firstOrNull
          ?.name ??
      'Leave as is';

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final options = ref.watch(lidarrAddOptionsProvider(widget.instanceId));
    final loaded = options.value;
    final count = formatCount(widget.artists.length);
    final artists = widget.artists.length == 1 ? 'artist' : 'artists';
    // A Lidarr with no profile of a kind has nothing to choose from.
    final usable =
        loaded != null &&
        loaded.qualityProfiles.isNotEmpty &&
        loaded.metadataProfiles.isNotEmpty;
    final stacked = mediaStacked(context);
    final align = stacked ? TextAlign.start : TextAlign.end;

    final Widget rows = switch (options) {
      AsyncError(:final error) => AppErrorState.compact(
        error: error,
        service: ServiceKey.lidarr,
        instanceId: widget.instanceId,
        onRetry: () =>
            ref.invalidate(lidarrAddOptionsProvider(widget.instanceId)),
      ),
      AsyncData(:final value) when !usable => LidarrBulkNoProfiles(
        sentence:
            'Lidarr has no '
            '${value.qualityProfiles.isEmpty ? 'quality' : 'metadata'} '
            'profile yet.',
      ),
      AsyncData(:final value) => MediaGroup(
        children: [
          MediaValueRow(
            label: 'Quality profile',
            value: Text(
              _qualityName(value),
              textAlign: align,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: () => _pickQuality(value),
          ),
          MediaValueRow(
            label: 'Metadata profile',
            value: Text(
              _metadataName(value),
              textAlign: align,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: () => _pickMetadata(value),
          ),
        ],
      ),
      _ => const LidarrAddOptionsLoadingRows(),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rows,
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          style: mediaLeadStyle(context, null),
          // Nothing to apply until a profile is chosen that they do not all
          // have already: a button that writes nothing is not drawn live.
          onPressed: usable && !_edit.isEmpty
              ? () => Navigator.of(context).pop(_edit)
              : null,
          child: Text('Apply to $count $artists'),
        ),
      ],
    );
  }
}

/// What the Profile sheet says of a Lidarr that has no profile to offer.
class LidarrBulkNoProfiles extends StatelessWidget {
  const LidarrBulkNoProfiles({super.key, required this.sentence});

  final String sentence;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Text(
      '$sentence Add one in Lidarr, then come back.',
      style: AppType.body.copyWith(color: CupolaRoom.of(context).inkSecondary),
    ),
  );
}

/// The two profile rows, while Lidarr is being read.
class LidarrAddOptionsLoadingRows extends StatelessWidget {
  const LidarrAddOptionsLoadingRows({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Reading the profiles',
    child: ExcludeSemantics(
      child: MediaGroup(
        children: [
          for (var i = 0; i < 2; i++)
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

/// What the Remove confirmation was answered with.
typedef LidarrBulkRemoval = ({bool deleteFiles, bool addImportListExclusion});

/// Asks whether to remove [artists] from Lidarr, and whether to take their
/// files with them and keep Lidarr from adding them again. Resolves to the
/// choices, or null when the person kept them.
///
/// The app's one removal confirmation ([showAppConfirmDialog], neutral, the
/// verb naming the whole of what happens) over the sentence a single removal
/// reads, for several. What the files take is the sum of their sizes on disk;
/// where Lidarr did not say some artist's, no figure is printed, because a
/// sum of what is known is a floor and reads as a total.
Future<LidarrBulkRemoval?> showLidarrBulkRemoveDialog(
  BuildContext context, {
  required List<LidarrArtist> artists,
  required String name,
  bool useRootNavigator = true,
}) async {
  final count = formatCount(artists.length);
  final noun = artists.length == 1 ? 'artist' : 'artists';
  final unknown = artists.any((artist) => artist.statistics == null);
  final total = artists.fold<int>(0, (sum, artist) => sum + artist.sizeOnDisk);
  final removal = mediaRemoval(
    title: '$count $noun',
    name: name,
    // Not "none of their albums are on your server" about sizes nobody read.
    sizeOnDisk: unknown ? 1 : total,
    monitored: artists.any((artist) => artist.monitored),
    works: 'albums',
  );
  final filesLabel = unknown
      ? 'Also delete their files'
      : total > 0
      ? 'Also delete ${formatBytes(total)} of files'
      : null;
  final taken = unknown ? null : formatBytes(total);

  String confirm({required bool files, required bool exclude}) {
    final remove = 'Remove $count $noun';
    final deleting = files && filesLabel != null;
    return switch ((deleting, exclude)) {
      (true, true) => '$remove, delete ${taken ?? 'files'}, don’t add again',
      (true, false) => '$remove and delete ${taken ?? 'files'}',
      (false, true) => '$remove and don’t add them again',
      (false, false) => remove,
    };
  }

  final result = await showAppConfirmDialog(
    context: context,
    useRootNavigator: useRootNavigator,
    title: removal.title,
    message: removal.message,
    icon: Icons.delete_outline_rounded,
    cancelLabel: 'Keep them',
    confirmLabel: confirm(files: false, exclude: false),
    confirmLabelFor: (checked) =>
        confirm(files: checked('files'), exclude: checked('exclude')),
    options: [
      if (filesLabel != null)
        AppConfirmOption(
          key: 'files',
          label: filesLabel,
          subtitle: 'Their folders on your server. This cannot be undone.',
        ),
      AppConfirmOption(
        key: 'exclude',
        label: 'Don’t add them again',
        subtitle: 'Keeps $name’s import lists from bringing them back',
      ),
    ],
  );
  if (!result.confirmed) return null;
  return (
    deleteFiles: result.option('files'),
    addImportListExclusion: result.option('exclude'),
  );
}
