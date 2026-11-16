import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The rows a person can change away from the folder's defaults.
enum LidarrAddRow { quality, metadata, monitor, newItems }

/// What the two Lidarr add sheets (an artist, an album) share: the folder and
/// the two profiles a new artist is filed under, read from the options of the
/// connection the sheet is on, started on the folder's defaults and changed
/// one row at a time; the write in flight and what Lidarr refused.
///
/// A row is a picker only when there is more than one thing to choose from.
/// A new answer for the options (another connection, a Retry) seeds the
/// choices again.
mixin LidarrAddChoices<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The connection the sheet adds to.
  ServiceInstance get target;

  /// The connection's name, as the button and the sentences say it.
  String get connectionName;

  /// The options the choices were last seeded from.
  LidarrAddOptions? seededFrom;

  LidarrRootFolder? folder;
  int? qualityId;
  int? metadataId;

  /// Whether the folder's defaults filled any row.
  var defaultsApplied = false;

  /// What the person changed: the folder's defaults no longer describe it.
  final touched = <LidarrAddRow>{};

  /// The post is out.
  var adding = false;
  LidarrAddRefusal? refusal;

  /// The metadata profile a fresh sheet starts on: the folder's default, which
  /// the album sheet replaces with the profile that keeps only what is added.
  int? preferredMetadataId(LidarrRootFolder folder, LidarrAddOptions options) =>
      folder.defaultMetadataProfileId;

  /// Fills the rows the person has not touched from [folder]'s defaults.
  /// Returns whether a default named one of them.
  bool applyFolderDefaults(LidarrRootFolder folder, LidarrAddOptions options) {
    this.folder = folder;
    var applied = false;
    if (!touched.contains(LidarrAddRow.quality)) {
      final wanted = folder.defaultQualityProfileId;
      final known = options.qualityProfiles.any((p) => p.id == wanted);
      qualityId = known ? wanted : options.qualityProfiles.first.id;
      applied |= known;
    }
    if (!touched.contains(LidarrAddRow.metadata)) {
      final wanted = preferredMetadataId(folder, options);
      final known = options.metadataProfiles.any((p) => p.id == wanted);
      metadataId = known ? wanted : options.metadataProfiles.first.id;
      applied |= known;
    }
    return applied;
  }

  /// Applies [folder]'s defaults to the choices. A sheet with more rows than
  /// these overrides it and calls this first.
  void applyDefaults(LidarrRootFolder folder, LidarrAddOptions options) {
    defaultsApplied = applyFolderDefaults(folder, options);
  }

  void seed(LidarrAddOptions options) {
    seededFrom = options;
    touched.clear();
    refusal = null;
    if (options.missing != null) return;
    applyDefaults(options.folders.first, options);
  }

  /// Seeds from [options] when it is an answer the choices do not come from
  /// yet. Call it from `build`.
  void seedFrom(AsyncValue<LidarrAddOptions> options) {
    if (options.value case final loaded? when !identical(loaded, seededFrom)) {
      seed(loaded);
    }
  }

  String? qualityName(LidarrAddOptions options) =>
      options.qualityProfiles.where((p) => p.id == qualityId).firstOrNull?.name;

  LidarrMetadataProfile? metadataOf(LidarrAddOptions options) =>
      options.metadataProfiles.where((p) => p.id == metadataId).firstOrNull;

  Future<void> pickFolder(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<String>(
      context,
      title: 'Folder',
      value: folder?.path,
      currentLabel: folder?.path ?? '',
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
      applyDefaults(
        options.folders.firstWhere((f) => f.path == picked.value),
        options,
      );
      refusal = null;
    });
  }

  Future<void> pickQuality(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: qualityId,
      currentLabel: qualityName(options) ?? '',
      options: [
        for (final profile in options.qualityProfiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      qualityId = picked.value;
      touched.add(LidarrAddRow.quality);
      refusal = null;
    });
  }

  Future<void> pickMetadata(LidarrAddOptions options) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Metadata profile',
      value: metadataId,
      currentLabel: metadataOf(options)?.name ?? '',
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
      metadataId = picked.value;
      touched.add(LidarrAddRow.metadata);
      refusal = null;
    });
  }

  /// Folder, Quality profile and Metadata profile, in the group's rows.
  List<Widget> choiceRows(LidarrAddOptions options, CupolaRoom room) {
    final folder = this.folder!;
    final metadata = metadataOf(options);
    // Where a value stacks under its label it starts where the label does.
    final stacked = mediaStacked(context);
    final align = stacked ? TextAlign.start : TextAlign.end;
    return [
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
        onTap: options.folders.length > 1 && !adding
            ? () => pickFolder(options)
            : null,
      ),
      MediaValueRow(
        label: 'Quality profile',
        value: Text(
          qualityName(options) ?? '',
          textAlign: align,
          style: AppType.meta.copyWith(color: room.inkSecondary),
        ),
        onTap: options.qualityProfiles.length > 1 && !adding
            ? () => pickQuality(options)
            : null,
      ),
      MediaValueRow(
        label: 'Metadata profile',
        value: MediaChoiceValue(
          label: metadata?.name ?? '',
          meaning: metadata?.typesLine,
        ),
        onTap: options.metadataProfiles.length > 1 && !adding
            ? () => pickMetadata(options)
            : null,
      ),
    ];
  }

  /// What the sheet shows for [options]: the failure with Retry, what the
  /// Lidarr is missing, the rows from [rows], or the rows' skeleton.
  Widget optionsBody(
    AsyncValue<LidarrAddOptions> options,
    Widget Function(LidarrAddOptions options) rows,
  ) {
    return switch (options) {
      AsyncError(:final error) => AppErrorState.compact(
        error: error,
        service: ServiceKey.lidarr,
        instanceId: target.id,
        onRetry: () => ref.invalidate(lidarrAddOptionsProvider(target.id)),
      ),
      AsyncData(:final value) when value.missing != null => LidarrAddMissing(
        sentence: '$connectionName has no ${value.missing} yet.',
        remedy: 'Add one in $connectionName, then come back.',
        name: connectionName,
        onOpen: () => openInLidarr(value.missing!),
      ),
      AsyncData(:final value) => rows(value),
      _ => const LidarrAddOptionsLoading(),
    };
  }

  /// Lidarr's own settings page for what is missing, at the address the
  /// connection is reached at now: away from home, the one at home would not
  /// open.
  Future<void> openInLidarr(String missing) async {
    final base = ref.read(connectionReachProvider(target.id))?.url ?? '';
    final path = missing == 'root folder'
        ? '/settings/mediamanagement'
        : '/settings/profiles';
    final uri = Uri.tryParse(UrlUtils.buildUrl(base, path));
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $connectionName');
    }
  }

  /// What a failed post says: [sentence], and Lidarr's own words under it
  /// when it gave any (`This artist has already been added`), otherwise why,
  /// in the classified words.
  LidarrAddRefusal refusalFor(Object error, {required String sentence}) =>
      LidarrAddRefusal(
        sentence: sentence,
        detail:
            failureServiceMessage(error) ??
            writeFailureReason(
              ServiceKey.lidarr,
              error,
              subject: connectionName,
            ),
        reason: classifyConnectionFailure(error),
      );
}

/// The primary button of an add sheet: [label] with the plus, a spinner while
/// the post is out, inert while the options load or [onPressed] is null.
class LidarrAddButton extends StatelessWidget {
  const LidarrAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.adding,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: mediaLeadStyle(context, null),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (adding)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.add_rounded, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

/// The close control in the corner of an add sheet's header: the glyph sits in
/// a 44 target, pulled into the corner.
class LidarrAddClose extends StatelessWidget {
  const LidarrAddClose({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(AppSpacing.row, -AppSpacing.sm),
      child: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
        constraints: const BoxConstraints.tightFor(
          width: DesignTokens.sizeTouch,
          height: DesignTokens.sizeTouch,
        ),
      ),
    );
  }
}

/// The group of rows, while the options are being read.
class LidarrAddOptionsLoading extends StatelessWidget {
  const LidarrAddOptionsLoading({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reading the options',
      child: ExcludeSemantics(
        child: MediaGroup(
          children: [
            for (var i = 0; i < rows; i++)
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
class LidarrAddRefusal extends StatelessWidget {
  const LidarrAddRefusal({
    super.key,
    required this.sentence,
    this.detail,
    this.reason,
  });

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
class LidarrAddMissing extends StatelessWidget {
  const LidarrAddMissing({
    super.key,
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
        LidarrAddRefusal(sentence: sentence),
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
