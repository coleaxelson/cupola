import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// What a wall's own *Wanted* read answered: how many things each title is
/// short of, by title id.
///
/// The ids are the answer to "which titles are wanted" and the counts are what
/// the wall says under each of them while the chip is on (`3 albums wanted`).
@immutable
class MediaBrowseWantedSet {
  const MediaBrowseWantedSet({required this.countById, this.isFloor = false});

  /// How many wanted things each wanted title has, by title id. A title that
  /// is absent has none.
  final Map<int, int> countById;

  /// The read stopped before the end of the service's list, so the titles and
  /// every count in [countById] are a floor, never a total: the wall says
  /// `34+`, not `34`.
  final bool isFloor;

  /// The wanted titles.
  Set<int> get ids => countById.keys.toSet();
}

/// A figure and the words around it, for [MediaBrowseWanted]: `3 albums
/// wanted`, `34 artists have a wanted album`. [isFloor] says the figure is a
/// floor and is to read `3+`.
typedef MediaBrowseWantedWords = String Function(int count, bool isFloor);

/// A chip a wall defines for itself, in place of the Missing chip.
///
/// Missing asks each title's own status, which is the right question when a
/// title is the unit that is on disk or not (a movie, a series), and the wrong
/// one when a title is a collection: Lidarr's Missing finds the artists with
/// *no* track on disk, so an artist missing 30 of its 31 albums sits under
/// Available. A wall whose service already answers the better question (what
/// is wanted: released, monitored, nothing on disk) hands that answer here,
/// and the scaffold draws the chip, the caption and the line from it.
///
/// What this carries is exactly what the scaffold cannot know: the answer, the
/// words, and whose failure it is.
@immutable
class MediaBrowseWanted {
  const MediaBrowseWanted({
    required this.answer,
    required this.service,
    required this.instanceId,
    required this.failureConsequence,
    required this.onRetry,
    required this.captionOf,
    required this.summaryOf,
    this.label = 'Wanted',
  });

  /// The service's answer, which may still be out or may have failed. The
  /// chip is drawn either way: it replaces Missing, which is there from the
  /// first frame, and a chip that appeared late would shove the ones after it.
  /// Selected before the answer lands it waits; failed, it says so and offers
  /// a retry. It never filters the wall to nothing on a question nobody
  /// answered.
  final AsyncValue<MediaBrowseWantedSet> answer;

  /// Whose read this is, and the connection it went to: the failure's remedy
  /// opens that connection's form.
  final ServiceKey service;
  final String instanceId;

  /// What the wall is without when the read failed, after `so`: `the artists
  /// with a wanted album are not shown`.
  final String failureConsequence;

  final VoidCallback onRetry;

  /// A tile's caption while the chip is on, from the count of that title.
  final MediaBrowseWantedWords captionOf;

  /// The line under the chips while the chip is on, from how many titles are
  /// wanted.
  final MediaBrowseWantedWords summaryOf;

  /// The chip's label.
  final String label;
}
