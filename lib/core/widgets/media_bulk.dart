import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/count_format.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Why one title was refused, in the service's words.
@immutable
class MediaBulkFailure {
  const MediaBulkFailure({
    required this.id,
    required this.name,
    required this.line,
    required this.error,
  });

  /// The title's id on the wall.
  final int id;

  /// What the wall calls it (`Miles Davis`), for the retry's label.
  final String name;

  /// The refusal as the notice reads it, naming the title: `Lidarr refused
  /// Miles Davis: the folder is not reachable.`
  final String line;

  /// What the request failed with, for the failure's tone and remedy.
  final Object error;
}

/// What one bulk action did, title by title.
///
/// Only what the service reported: a title is in [done] because its own
/// request was accepted, and in [failures] because its own request was
/// refused. An action whose service cannot say which title failed does not
/// make one up; it asks one title at a time (see `LidarrService.updateArtistsInBulk`).
@immutable
class MediaBulkOutcome {
  const MediaBulkOutcome({required this.done, this.failures = const []});

  final List<int> done;
  final List<MediaBulkFailure> failures;

  /// Every title took it.
  bool get isWhole => failures.isEmpty;

  /// Some did, some did not.
  bool get isPartial => failures.isNotEmpty && done.isNotEmpty;

  /// None did.
  bool get isNone => done.isEmpty && failures.isNotEmpty;
}

/// An action once the person has decided what it does (the sheet is answered,
/// the confirmation given): what to run and what to say of the result.
///
/// Held by the wall so the notice's *Try again* runs exactly this for the
/// titles that were refused, and no other.
@immutable
class MediaBulkJob<T> {
  const MediaBulkJob({
    required this.run,
    required this.doneLine,
    required this.partialLine,
  });

  /// Runs the action for [items]. A refusal of one title is a
  /// [MediaBulkFailure] in the outcome; a failure that is not any one title's
  /// (nothing answered, the key was refused) is thrown.
  final Future<MediaBulkOutcome> Function(List<T> items) run;

  /// What the toast says when all [count] took it: `Lidarr is searching 3
  /// artists`.
  final String Function(int count) doneLine;

  /// The notice's first line when [done] of [total] took it: `2 of 3 artists
  /// updated`.
  final String Function(int done, int total) partialLine;
}

/// One of the actions on the selection bar: a glyph over its name, and what
/// it asks before it runs.
@immutable
class MediaBulkAction<T> {
  const MediaBulkAction({
    required this.label,
    required this.icon,
    required this.prepare,
    this.shownOnly = false,
  });

  final String label;
  final IconData icon;

  /// Asks what the action needs (a sheet, a confirmation) over [items], the
  /// titles selected. Null when the person backs out: nothing runs, the
  /// selection stays.
  final Future<MediaBulkJob<T>?> Function(BuildContext context, List<T> items)
  prepare;

  /// Whether the action takes only the selected titles the chip shows: the
  /// ones a person cannot see are not acted on (Remove). They stay selected
  /// and the header keeps saying so. Search, Monitor and Profile take the
  /// whole selection.
  final bool shownOnly;
}

/// What a library can do to several of its titles at once. A wall without one
/// does not offer to select.
@immutable
class MediaBulk<T> {
  const MediaBulk({
    required this.actions,
    required this.singular,
    required this.plural,
    required this.noneHint,
    required this.service,
    required this.instanceId,
    this.onChanged,
  }) : assert(actions.length > 0, 'a wall with no action does not select');

  final List<MediaBulkAction<T>> actions;

  /// The title, as the bar counts it: `artist`.
  final String singular;

  /// `artists`.
  final String plural;

  /// What a tap on an action says when nothing is selected: `Select an artist
  /// first`.
  final String noneHint;

  /// Whose titles these are, for a failure's remedy.
  final ServiceKey service;
  final String instanceId;

  /// Reads again what the action changed (the library, what is derived from
  /// it), once at least one title took it.
  final void Function(WidgetRef ref)? onChanged;

  /// `3 artists`, `1 artist`.
  String countOf(int count) =>
      '${formatCount(count)} ${count == 1 ? singular : plural}';
}
