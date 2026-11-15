import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/arr_bulk.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/count_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a library's selection bar says and asks, for one service: the nouns of
/// its titles, and which of the editor's controls its sheets offer.
///
/// The arrs' editors do not take the same fields, so the sheets are built from
/// what each one accepts: Sonarr and Readarr take `monitorNewItems` (a second
/// control on the Monitor sheet, named by [newItemsHeading]), Lidarr and
/// Readarr a metadata profile, and Radarr neither.
@immutable
class ArrBulkKind {
  const ArrBulkKind({
    required this.service,
    required this.singular,
    required this.plural,
    required this.noneHint,
    this.works,
    this.newItemsHeading,
    this.hasMetadataProfile = false,
  });

  final ServiceKey service;

  /// The title, as the bar counts it: `movie`, `series`, `author`.
  final String singular;
  final String plural;

  /// What a tap on an action says when nothing is selected: `Select a movie
  /// first`.
  final String noneHint;

  /// What the arr looks for of a person's, for the removal's sentence (`their
  /// albums`): null for a title, which reads `them`.
  final String? works;

  /// The Monitor sheet's second control (`Monitor new albums`), or null where
  /// the editor takes no `monitorNewItems`.
  final String? newItemsHeading;

  /// The editor takes a metadata profile beside the quality profile.
  final bool hasMetadataProfile;

  /// `3 movies`, `1 series`, `12 series`.
  String countOf(int count) =>
      '${formatCount(count)} ${count == 1 ? singular : plural}';

  /// What a profile sheet is called over [count] titles.
  String profileTitle(int count) =>
      '${hasMetadataProfile ? 'Profiles' : 'Profile'} for ${countOf(count)}';
}

/// The titles a sheet is for, as it names them under its title: `Bill Evans,
/// Brian Eno and Miles Davis`, and past three `Bill Evans, Brian Eno and 12
/// more`.
String arrBulkNames(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.first,
  2 => '${names.first} and ${names.last}',
  3 => '${names[0]}, ${names[1]} and ${names[2]}',
  _ => '${names[0]}, ${names[1]} and ${formatCount(names.length - 2)} more',
};

/// One refusal as a sentence: `Lidarr refused Miles Davis: the folder is not
/// reachable.`, in the arr's own words when it gave any. A request that never
/// got an answer has no words of the arr's, and says why in the classified
/// ones after the name, which is all that can be said of it.
String arrRefusalLine(
  String title,
  Object error,
  ServiceKey service,
  String name,
) {
  final said = failureServiceMessage(error);
  if (said != null) {
    final sentence = said.endsWith('.') ? said : '$said.';
    return '$name refused $title: $sentence';
  }
  return '$title: ${writeFailureReason(service, error, subject: name)}';
}

/// What the Monitor sheet starts on: what the titles all have when they
/// agree, and otherwise Monitor.
bool arrBulkStartMonitored(Iterable<bool> monitored) =>
    monitored.any((value) => value);

/// The albums-to-come setting the Monitor sheet starts on: `all` or `none`
/// when every title has it, and otherwise null, `Leave as is`.
String? arrBulkStartNewItems(List<String?> values) {
  final first = values.firstOrNull;
  if (first != 'all' && first != 'none') return null;
  return values.every((value) => value == first) ? first : null;
}

/// The profile every title has, or null when they differ or one does not say.
int? arrBulkSharedProfile(List<int?> profiles) {
  final first = profiles.firstOrNull;
  if (first == null) return null;
  return profiles.every((profile) => profile == first) ? first : null;
}

/// The Monitor sheet's body: whether to monitor and, where the editor takes
/// it, what to do with what comes later. Resolves to the edit it makes.
///
/// Starts on what the selection already has when it all agrees, otherwise on
/// Monitor and Leave as is. `Apply` is always there: choosing is the point.
class ArrBulkMonitorSheet extends StatefulWidget {
  const ArrBulkMonitorSheet({
    super.key,
    required this.kind,
    required this.count,
    required this.startMonitored,
    this.startNewItems,
  });

  final ArrBulkKind kind;
  final int count;
  final bool startMonitored;

  /// `all`, `none`, or null for Leave as is.
  final String? startNewItems;

  @override
  State<ArrBulkMonitorSheet> createState() => _ArrBulkMonitorSheetState();
}

class _ArrBulkMonitorSheetState extends State<ArrBulkMonitorSheet> {
  late bool _monitored = widget.startMonitored;
  late String? _newItems = widget.startNewItems;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final heading = widget.kind.newItemsHeading;
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
        // Only where the editor takes one: a control that is not sent is a
        // promise the arr does not keep.
        if (heading != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              heading,
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PageTabs<String?>(
            semanticLabel: heading,
            values: const [null, 'all', 'none'],
            selected: _newItems,
            labelBuilder: (value) => switch (value) {
              'all' => 'All',
              'none' => 'None',
              _ => 'Leave as is',
            },
            onSelected: (value) => setState(() => _newItems = value),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          style: mediaLeadStyle(context, null),
          onPressed: () => Navigator.of(context).pop(
            ArrBulkEdit(
              monitored: _monitored,
              monitorNewItems: heading == null ? null : _newItems,
            ),
          ),
          child: Text('Apply to ${widget.kind.countOf(widget.count)}'),
        ),
      ],
    );
  }
}

/// One profile a sheet offers, with what choosing it means under its name.
typedef ArrProfileChoice = ({int id, String name, String? detail});

/// The profiles one arr offers: quality always, metadata where its editor
/// takes it.
typedef ArrProfileOptions = ({
  List<ArrProfileChoice> quality,
  List<ArrProfileChoice>? metadata,
});

/// The Profile sheet's body: a quality profile (and a metadata profile where
/// the editor takes one) for the whole selection, each started on what they
/// all have or Leave as is, and `Apply`, which is there only when something is
/// going to change.
class ArrBulkProfileSheet extends StatefulWidget {
  const ArrBulkProfileSheet({
    super.key,
    required this.kind,
    required this.count,
    required this.sharedQuality,
    required this.sharedMetadata,
    required this.options,
    required this.instanceId,
    required this.onRetry,
  });

  final ArrBulkKind kind;
  final int count;
  final int? sharedQuality;
  final int? sharedMetadata;
  final AsyncValue<ArrProfileOptions> options;
  final String instanceId;
  final VoidCallback onRetry;

  @override
  State<ArrBulkProfileSheet> createState() => _ArrBulkProfileSheetState();
}

class _ArrBulkProfileSheetState extends State<ArrBulkProfileSheet> {
  /// The choice on each row: null is Leave as is.
  late int? _quality = widget.sharedQuality;
  late int? _metadata = widget.sharedMetadata;

  /// What is going to be written: a profile chosen that is not what they all
  /// have already.
  ArrBulkEdit get _edit => ArrBulkEdit(
    qualityProfileId: _quality != widget.sharedQuality ? _quality : null,
    metadataProfileId: widget.kind.hasMetadataProfile
        ? (_metadata != widget.sharedMetadata ? _metadata : null)
        : null,
  );

  static String _nameOf(List<ArrProfileChoice> profiles, int? id) =>
      profiles.where((profile) => profile.id == id).firstOrNull?.name ??
      'Leave as is';

  Future<void> _pick({
    required String title,
    required List<ArrProfileChoice> profiles,
    required int? current,
    required ValueChanged<int?> onPicked,
  }) async {
    final picked = await showMediaValueSheet<int?>(
      context,
      title: title,
      value: current,
      currentLabel: _nameOf(profiles, current),
      options: [
        const MediaDetailValueOption(value: null, label: 'Leave as is'),
        for (final profile in profiles)
          MediaDetailValueOption(
            value: profile.id,
            label: profile.name,
            detail: profile.detail,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked.value));
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final kind = widget.kind;
    final loaded = widget.options.value;
    // An arr with no profile of a kind has nothing to choose from.
    final missing = loaded == null
        ? null
        : loaded.quality.isEmpty
        ? 'quality'
        : (kind.hasMetadataProfile && (loaded.metadata?.isEmpty ?? true))
        ? 'metadata'
        : null;
    final usable = loaded != null && missing == null;
    final align = mediaStacked(context) ? TextAlign.start : TextAlign.end;
    final name = kind.service.title;

    Widget row(String label, String value, VoidCallback onTap) => MediaValueRow(
      label: label,
      value: Text(
        value,
        textAlign: align,
        style: AppType.meta.copyWith(color: room.inkSecondary),
      ),
      onTap: onTap,
    );

    final Widget rows = switch (widget.options) {
      AsyncError(:final error) => AppErrorState.compact(
        error: error,
        service: kind.service,
        instanceId: widget.instanceId,
        onRetry: widget.onRetry,
      ),
      AsyncData() when !usable => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          '$name has no $missing profile yet. Add one in $name, then come '
          'back.',
          style: AppType.body.copyWith(color: room.inkSecondary),
        ),
      ),
      AsyncData(:final value) => MediaGroup(
        children: [
          row(
            'Quality profile',
            _nameOf(value.quality, _quality),
            () => _pick(
              title: 'Quality profile',
              profiles: value.quality,
              current: _quality,
              onPicked: (id) => _quality = id,
            ),
          ),
          if (value.metadata case final metadata?)
            row(
              'Metadata profile',
              _nameOf(metadata, _metadata),
              () => _pick(
                title: 'Metadata profile',
                profiles: metadata,
                current: _metadata,
                onPicked: (id) => _metadata = id,
              ),
            ),
        ],
      ),
      _ => Semantics(
        label: 'Reading the profiles',
        child: ExcludeSemantics(
          child: MediaGroup(
            children: [
              for (var i = 0; i < (kind.hasMetadataProfile ? 2 : 1); i++)
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
      ),
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
          child: Text('Apply to ${kind.countOf(widget.count)}'),
        ),
      ],
    );
  }
}

/// What the Remove confirmation was answered with.
typedef ArrBulkRemoval = ({bool deleteFiles, bool addImportListExclusion});

/// Asks whether to remove [titles] from the arr called [name], and whether to
/// take their files with them and keep the arr from adding them again.
/// Resolves to the choices, or null when the person kept them.
///
/// The app's one removal confirmation ([showAppConfirmDialog], neutral, the
/// verb naming the whole of what happens) over the sentence a single removal
/// reads, for several. What the files take is the sum of [sizes]; where one
/// is null (the arr did not say) no figure is printed, because a sum of what is
/// known is a floor and reads as a total. [monitored] is whether each title is
/// watched, for what the arr stops doing.
Future<ArrBulkRemoval?> showArrBulkRemoveDialog(
  BuildContext context, {
  required ArrBulkKind kind,
  required String name,
  required List<int?> sizes,
  required List<bool> monitored,
  bool useRootNavigator = true,
}) async {
  final count = formatCount(sizes.length);
  final noun = sizes.length == 1 ? kind.singular : kind.plural;
  final unknown = sizes.any((size) => size == null);
  final total = sizes.fold<int>(0, (sum, size) => sum + (size ?? 0));
  final works = kind.works == null ? 'them' : 'their ${kind.works}';

  final stops = monitored.any((value) => value)
      ? '$name stops looking for $works.'
      : '$name stops tracking them.';
  // Not "none of them are on your server" about sizes nobody read.
  final rest = !unknown && total == 0
      ? (kind.works == null
            ? 'None of them are on your server yet.'
            : 'None of their ${kind.works} are on your server yet.')
      : null;

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
    title: 'Remove $count $noun from $name?',
    message: rest == null ? stops : '$stops $rest',
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

/// What a service's wall can do to several of its titles, in its own terms:
/// how to read a title and how to ask the arr. [arrBulk] turns it into the
/// selection bar's four actions.
class ArrBulkAdapter<T> {
  const ArrBulkAdapter({
    required this.kind,
    required this.instanceId,
    required this.name,
    required this.idOf,
    required this.nameOf,
    required this.monitoredOf,
    required this.qualityOf,
    required this.sizeOf,
    required this.search,
    required this.update,
    required this.remove,
    required this.watchProfiles,
    required this.retryProfiles,
    this.metadataOf,
    this.newItemsOf,
    this.onChanged,
  });

  final ArrBulkKind kind;
  final String instanceId;

  /// The connection as a sentence says it (`Radarr 4K`).
  final String name;

  final int Function(T title) idOf;
  final String Function(T title) nameOf;
  final bool Function(T title) monitoredOf;
  final int? Function(T title) qualityOf;
  final int? Function(T title)? metadataOf;
  final String? Function(T title)? newItemsOf;

  /// What the title's files take, in bytes, or null where the arr did not say.
  final int? Function(T title) sizeOf;

  final Future<ArrBulkResult> Function(List<int> ids) search;
  final Future<ArrBulkResult> Function(List<int> ids, ArrBulkEdit edit) update;
  final Future<ArrBulkResult> Function(
    List<int> ids, {
    required bool deleteFiles,
    required bool addImportListExclusion,
  })
  remove;

  /// The profiles the arr offers, watched where the sheet draws them.
  final AsyncValue<ArrProfileOptions> Function(WidgetRef ref) watchProfiles;
  final void Function(WidgetRef ref) retryProfiles;

  final void Function(WidgetRef ref)? onChanged;
}

/// The four actions of the selection bar for [adapter]'s service: Search,
/// Monitor, Profile, Remove, each asking what it needs before it runs.
///
/// [dialogsOnRoot] is where the confirmation opens: on the app's root
/// navigator, so it covers the bar and the tabs. A catalog scene, which has no
/// navigator above it to look at, opens it on its own.
MediaBulk<T> arrBulk<T>(
  WidgetRef ref,
  ArrBulkAdapter<T> adapter, {
  bool dialogsOnRoot = true,
}) {
  final kind = adapter.kind;
  final name = adapter.name;
  late final MediaBulk<T> bulk;

  List<int> idsOf(List<T> titles) => [for (final t in titles) adapter.idOf(t)];

  MediaBulkOutcome outcome(List<T> titles, ArrBulkResult result) =>
      MediaBulkOutcome(
        done: result.done,
        failures: [
          for (final title in titles)
            if (result.refused[adapter.idOf(title)] case final error?)
              MediaBulkFailure(
                id: adapter.idOf(title),
                name: adapter.nameOf(title),
                line: arrRefusalLine(
                  adapter.nameOf(title),
                  error,
                  kind.service,
                  name,
                ),
                error: error,
              ),
        ],
      );

  MediaBulkJob<T> job(
    Future<ArrBulkResult> Function(List<int> ids) run, {
    required String Function(int count) doneLine,
    required String Function(int done, int total) partialLine,
  }) => MediaBulkJob<T>(
    run: (titles) async => outcome(titles, await run(idsOf(titles))),
    doneLine: doneLine,
    partialLine: partialLine,
  );

  String updated(int done, int total) =>
      '${formatCount(done)} of ${bulk.countOf(total)} updated';

  Future<ArrBulkEdit?> ask(
    BuildContext context,
    List<T> titles, {
    required String title,
    required Widget Function(BuildContext context) builder,
  }) => AppBottomSheet.show<ArrBulkEdit>(
    context: context,
    title: title,
    subtitle: arrBulkNames([for (final t in titles) adapter.nameOf(t)]),
    builder: builder,
  );

  bulk = MediaBulk<T>(
    singular: kind.singular,
    plural: kind.plural,
    noneHint: kind.noneHint,
    service: kind.service,
    instanceId: adapter.instanceId,
    onChanged: adapter.onChanged,
    actions: [
      // A search starts nothing to ask about: it runs.
      MediaBulkAction<T>(
        label: 'Search',
        icon: Icons.search_rounded,
        prepare: (context, titles) async => job(
          adapter.search,
          doneLine: (count) => '$name is searching ${bulk.countOf(count)}',
          partialLine: (done, total) =>
              '$name is searching ${formatCount(done)} of '
              '${bulk.countOf(total)}',
        ),
      ),
      MediaBulkAction<T>(
        label: 'Monitor',
        icon: Icons.visibility_rounded,
        prepare: (context, titles) async {
          final edit = await ask(
            context,
            titles,
            title: 'Monitor ${bulk.countOf(titles.length)}',
            builder: (_) => ArrBulkMonitorSheet(
              kind: kind,
              count: titles.length,
              startMonitored: arrBulkStartMonitored([
                for (final t in titles) adapter.monitoredOf(t),
              ]),
              startNewItems: adapter.newItemsOf == null
                  ? null
                  : arrBulkStartNewItems([
                      for (final t in titles) adapter.newItemsOf!(t),
                    ]),
            ),
          );
          if (edit == null) return null;
          return job(
            (ids) => adapter.update(ids, edit),
            doneLine: (count) => 'Updated ${bulk.countOf(count)}',
            partialLine: updated,
          );
        },
      ),
      MediaBulkAction<T>(
        label: 'Profile',
        icon: Icons.tune_rounded,
        prepare: (context, titles) async {
          final edit = await ask(
            context,
            titles,
            title: kind.profileTitle(titles.length),
            builder: (_) => Consumer(
              builder: (context, ref, _) => ArrBulkProfileSheet(
                kind: kind,
                count: titles.length,
                sharedQuality: arrBulkSharedProfile([
                  for (final t in titles) adapter.qualityOf(t),
                ]),
                sharedMetadata: adapter.metadataOf == null
                    ? null
                    : arrBulkSharedProfile([
                        for (final t in titles) adapter.metadataOf!(t),
                      ]),
                options: adapter.watchProfiles(ref),
                instanceId: adapter.instanceId,
                onRetry: () => adapter.retryProfiles(ref),
              ),
            ),
          );
          if (edit == null) return null;
          return job(
            (ids) => adapter.update(ids, edit),
            doneLine: (count) => 'Updated ${bulk.countOf(count)}',
            partialLine: updated,
          );
        },
      ),
      MediaBulkAction<T>(
        label: 'Remove',
        icon: Icons.delete_outline_rounded,
        prepare: (context, titles) async {
          final removal = await showArrBulkRemoveDialog(
            context,
            kind: kind,
            name: name,
            sizes: [for (final t in titles) adapter.sizeOf(t)],
            monitored: [for (final t in titles) adapter.monitoredOf(t)],
            useRootNavigator: dialogsOnRoot,
          );
          if (removal == null) return null;
          return job(
            (ids) => adapter.remove(
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

/// The quality profiles an arr listed (`{id, name, …}` each), as the sheet
/// offers them: an entry with no id cannot be chosen and is left out.
List<ArrProfileChoice> arrQualityChoices(List<Map<String, dynamic>> profiles) =>
    [
      for (final profile in profiles)
        if (profile['id'] case final int id)
          (id: id, name: profile['name'] as String? ?? 'Profile', detail: null),
    ];
