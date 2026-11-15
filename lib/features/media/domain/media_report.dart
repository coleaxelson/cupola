import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// The page of the title an issue is about, or null when Seerr named no
/// TMDB id or a kind that is neither a movie nor a series.
MediaKey? mediaKeyOfIssue(SeerrIssue issue) {
  final tmdb = issue.media?.tmdbId;
  if (tmdb == null) return null;
  return switch (issue.media?.mediaType) {
    'movie' => MediaKey.movie(tmdb),
    'tv' => MediaKey.tv(tmdb),
    _ => null,
  };
}

/// A season of a series that is on the server, as a report may name it.
@immutable
class MediaReportSeason {
  const MediaReportSeason(this.number, this.episodeCount);

  /// Never 0: Seerr reads season 0 as every season, so Specials cannot be
  /// reported on their own and are never offered.
  final int number;

  /// How many episodes TMDB lists in it; 0 when it did not say.
  final int episodeCount;

  @override
  bool operator ==(Object other) =>
      other is MediaReportSeason &&
      other.number == number &&
      other.episodeCount == episodeCount;

  @override
  int get hashCode => Object.hash(number, episodeCount);
}

/// What the Seerr that holds a title lets a person report on it: the record's
/// own id (a report names Seerr's media id, never TMDB's), the issues Seerr
/// lists on the title, and for a series the seasons on the server.
@immutable
class MediaReportSource {
  const MediaReportSource({
    required this.seerr,
    required this.mediaId,
    required this.title,
    this.issues = const [],
    this.seasons = const [],
  });

  /// The Seerr connection the report is filed in.
  final ServiceInstance seerr;

  /// `mediaInfo.id`.
  final int mediaId;

  /// The title as TMDB's record names it; empty when it has none.
  final String title;

  /// `mediaInfo.issues`: Seerr filters them to `id`, `issueType`, `status`,
  /// the dates and `createdBy`. No words, no season, no episode, and none at
  /// all for an account with no issue permission.
  final List<SeerrIssue> issues;

  /// A series' seasons on the server, in order; empty for a movie.
  final List<MediaReportSeason> seasons;

  /// The open issues of the title, newest first.
  List<SeerrIssue> get openIssues => [
    for (final issue in _newestFirst(issues))
      if (issue.isOpen) issue,
  ];

  /// The newest report [userId] made on the title, or null; the API key has
  /// no user.
  SeerrIssue? ownLatest(int? userId) {
    if (userId == null) return null;
    return _newestFirst(
      issues,
    ).where((issue) => issue.isReportedBy(userId)).firstOrNull;
  }

  /// Season [number]'s episode count, 0 when unknown.
  int episodeCountOf(int number) =>
      seasons.where((s) => s.number == number).firstOrNull?.episodeCount ?? 0;

  bool hasSeason(int number) => seasons.any((s) => s.number == number);
}

List<SeerrIssue> _newestFirst(List<SeerrIssue> issues) {
  final sorted = [...issues];
  sorted.sort((a, b) {
    final byDate =
        (DateTime.tryParse(b.createdAt ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              DateTime.tryParse(a.createdAt ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  });
  return sorted;
}

/// The Seerr a report on this title goes to, or null for none: Seerr's own
/// rule for offering it, that the title is on the server.
///
/// A connection qualifies when its record of the title has a media row with
/// an id, and that row says the title is available (`status` or `status4k`
/// 5), or for a series partly available as well (4). The codes up to 5 read
/// the same in every numbering. Where two Seerr connections qualify, the
/// page's [focus] connection wins, else the first.
MediaReportSource? mediaReportSourceOf(
  List<MediaRow> rows, {
  required bool movie,
  String? focus,
}) {
  MediaReportSource? first;
  for (final row in rows) {
    if (row case MediaConnectionRow<MediaSeerrRecord>(
      :final connection,
      reading: MediaReadingAnswered<MediaSeerrRecord>(:final answer),
    )) {
      final source = _sourceOf(connection, answer.value, movie: movie);
      if (source == null) continue;
      if (connection.id == focus) return source;
      first ??= source;
    }
  }
  return first;
}

MediaReportSource? _sourceOf(
  ServiceInstance seerr,
  MediaSeerrRecord record, {
  required bool movie,
}) {
  final info = record.mediaInfo;
  final id = intOrNull(info?['id']);
  if (info == null || id == null || id <= 0) return null;
  bool held(Object? code) => switch (SeerrMediaAvailability.fromCode(
    code,
    numbering: record.numbering,
  )) {
    SeerrMediaAvailability.available => true,
    SeerrMediaAvailability.partiallyAvailable => !movie,
    _ => false,
  };
  if (!held(info['status']) && !held(info['status4k'])) return null;

  final counts = <int, int>{
    for (final season in _maps(record.details['seasons']))
      ?intOrNull(season['seasonNumber']):
          intOrNull(season['episodeCount']) ?? 0,
  };
  final seasons = movie
      ? const <MediaReportSeason>[]
      : ([
          for (final season in _maps(info['seasons']))
            if (intOrNull(season['seasonNumber']) case final number?)
              if (number > 0 &&
                  (held(season['status']) || held(season['status4k'])))
                MediaReportSeason(number, counts[number] ?? 0),
        ]..sort((a, b) => a.number.compareTo(b.number)));
  return MediaReportSource(
    seerr: seerr,
    mediaId: id,
    title:
        stringOrNull(record.details['title'] ?? record.details['name']) ?? '',
    issues: [
      for (final issue in _maps(info['issues'])) SeerrIssue.fromJson(issue),
    ],
    seasons: seasons,
  );
}

/// The maps in [raw], skipping anything else.
List<Map<String, dynamic>> _maps(Object? raw) => switch (raw) {
  final List<dynamic> list => [
    for (final item in list)
      if (item is Map) Map<String, dynamic>.from(item),
  ],
  _ => const [],
};
