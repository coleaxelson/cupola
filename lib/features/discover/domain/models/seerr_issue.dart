import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';

/// Which issues a list asks for, as Seerr's `filter` names them.
enum SeerrIssueFilter {
  open('open', 'Open'),
  resolved('resolved', 'Resolved'),
  all('all', 'All');

  const SeerrIssueFilter(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// What a problem is about, as Seerr's `IssueType` numbers it.
///
/// A label and nothing more: the server treats the four alike. The wrong
/// file sits under [video].
enum SeerrIssueType {
  video(1, 'Video'),
  audio(2, 'Audio'),
  subtitles(3, 'Subtitles'),
  other(4, 'Other');

  const SeerrIssueType(this.wire, this.label);

  /// The number Seerr sends and expects.
  final int wire;
  final String label;

  /// The type Seerr's [wire] number names, or null for any other.
  static SeerrIssueType? fromWire(Object? value) {
    final number = intOrNull(value);
    for (final type in values) {
      if (type.wire == number) return type;
    }
    return null;
  }
}

/// Where an issue stands, as Seerr's `IssueStatus` numbers it.
enum SeerrIssueStatus {
  open(1, 'open'),
  resolved(2, 'resolved');

  const SeerrIssueStatus(this.wire, this.route);

  final int wire;

  /// The last segment of `POST /issue/{id}/…` that moves an issue here.
  final String route;

  static SeerrIssueStatus? fromWire(Object? value) {
    final number = intOrNull(value);
    for (final status in values) {
      if (status.wire == number) return status;
    }
    return null;
  }
}

@immutable
class SeerrIssueMedia {
  const SeerrIssueMedia({
    this.id,
    this.tmdbId,
    this.title,
    this.mediaType,
    this.posterPath,
  });

  /// Seerr's own media id (`mediaInfo.id`), which a report names. Not TMDB's.
  final int? id;
  final int? tmdbId;
  final String? title;
  final String? mediaType;
  final String? posterPath;

  factory SeerrIssueMedia.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return SeerrIssueMedia(
      id: intOrNull(json['id']),
      tmdbId: intOrNull(json['tmdbId'] ?? json['tmdb_id']),
      title: stringOrNull(json['title'] ?? json['name']),
      mediaType: stringOrNull(
        json['mediaType'] ?? json['media_type'] ?? json['type'],
      ),
      posterPath: stringOrNull(json['posterPath'] ?? json['poster_path']),
    );
  }

  SeerrIssueMedia copyWith({String? title, String? posterPath}) =>
      SeerrIssueMedia(
        id: id,
        tmdbId: tmdbId,
        title: title ?? this.title,
        mediaType: mediaType,
        posterPath: posterPath ?? this.posterPath,
      );
}

/// One message of an issue's conversation.
///
/// The text is user text: it never appears in [toString].
@immutable
class SeerrIssueComment {
  const SeerrIssueComment({
    required this.id,
    required this.message,
    this.authorId,
    this.authorName,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String message;

  /// Who wrote it. The issue list carries no `user` on its comments, so both
  /// are null there; `GET /issue/{id}` joins it.
  final int? authorId;
  final String? authorName;
  final String? createdAt;
  final String? updatedAt;

  factory SeerrIssueComment.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final user = json['user'];
    final author = user is Map ? SeerrUser.fromJson(user) : null;
    return SeerrIssueComment(
      id: intOrNull(json['id']) ?? 0,
      // Kept as it was written: the person's words, spaces included.
      message: json['message']?.toString() ?? '',
      authorId: author?.id,
      authorName: author?.displayName,
      createdAt: stringOrNull(json['createdAt'] ?? json['created_at']),
      updatedAt: stringOrNull(json['updatedAt'] ?? json['updated_at']),
    );
  }

  /// Whether the account [userId] wrote it. False when the author is unknown
  /// or [userId] is (the API key has no user).
  bool isBy(int? userId) => userId != null && authorId == userId;

  /// Whether it was edited after it was written.
  bool get isEdited =>
      createdAt != null && updatedAt != null && createdAt != updatedAt;

  @override
  String toString() => 'SeerrIssueComment($id)';
}

@immutable
class SeerrIssue {
  const SeerrIssue({
    required this.id,
    required this.type,
    required this.status,
    this.media,
    this.createdBy,
    this.modifiedBy,
    this.problemSeason = 0,
    this.problemEpisode = 0,
    this.comments = const [],
    int? commentCount,
    this.createdAt,
    this.updatedAt,
  }) : _commentCount = commentCount;

  final int id;

  /// What the problem is about; null for a number Seerr does not define.
  final SeerrIssueType? type;

  /// Where it stands. Null when the server did not send one, which is not
  /// the same as either.
  final SeerrIssueStatus? status;
  final SeerrIssueMedia? media;
  final SeerrUser? createdBy;
  final SeerrUser? modifiedBy;

  /// The season the problem is in; 0 is every season, and the whole title for
  /// a movie. Seerr cannot name Specials on their own.
  final int problemSeason;

  /// The episode the problem is in; 0 is every episode.
  final int problemEpisode;

  /// The whole conversation, the report first. The list sends the comments
  /// without their authors; `GET /issue/{id}` sends them with.
  final List<SeerrIssueComment> comments;
  final int? _commentCount;
  final String? createdAt;
  final String? updatedAt;

  factory SeerrIssue.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final rawComments = json['comments'];
    return SeerrIssue(
      id: intOrNull(json['id']) ?? 0,
      type: SeerrIssueType.fromWire(json['issueType'] ?? json['issue_type']),
      status: SeerrIssueStatus.fromWire(json['status']),
      media: json['media'] == null
          ? null
          : SeerrIssueMedia.fromJson(json['media']),
      createdBy: json['createdBy'] == null
          ? null
          : SeerrUser.fromJson(json['createdBy']),
      modifiedBy: json['modifiedBy'] == null
          ? null
          : SeerrUser.fromJson(json['modifiedBy']),
      problemSeason: intOrNull(json['problemSeason']) ?? 0,
      problemEpisode: intOrNull(json['problemEpisode']) ?? 0,
      comments: rawComments is List
          ? List.unmodifiable(rawComments.map(SeerrIssueComment.fromJson))
          : const [],
      commentCount: rawComments is List
          ? null
          : intOrNull(json['commentCount']),
      createdAt: stringOrNull(json['createdAt'] ?? json['created_at']),
      updatedAt: stringOrNull(json['updatedAt'] ?? json['updated_at']),
    );
  }

  SeerrIssue copyWith({SeerrIssueMedia? media}) => SeerrIssue(
    id: id,
    type: type,
    status: status,
    media: media ?? this.media,
    createdBy: createdBy,
    modifiedBy: modifiedBy,
    problemSeason: problemSeason,
    problemEpisode: problemEpisode,
    comments: comments,
    commentCount: _commentCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// How many comments the issue has, the report itself counted: the
  /// reporter may delete the issue only while this is one.
  int get commentCount =>
      comments.isNotEmpty ? comments.length : (_commentCount ?? 0);

  /// The report's own words: the first comment. Null for an issue read
  /// without its comments.
  String? get message => comments.isEmpty ? null : comments.first.message;

  /// The replies: every comment after the report.
  List<SeerrIssueComment> get replies =>
      comments.length < 2 ? const [] : comments.sublist(1);

  String get issueTypeLabel => type?.label ?? 'Issue';

  bool get isResolved => status == SeerrIssueStatus.resolved;

  /// Whether this issue can still be resolved.
  ///
  /// A missing `status` is treated as open: the Resolve call is idempotent on
  /// Overseerr's side, so offering it on an issue that turns out to be closed
  /// costs a redundant POST, while withholding it on an open one leaves the
  /// user with no way to act.
  bool get isOpen => !isResolved;

  /// Whether the account [userId] reported it. False for the API key, which
  /// has no user id, and for an issue whose reporter is unknown.
  bool isReportedBy(int? userId) =>
      userId != null && createdBy != null && createdBy!.id == userId;

  /// **From the record, never from the query that fetched it.** This used to
  /// read the `SeerrIssueFilter`, which meant the "All" tab painted every row
  /// amber, resolved issues included, and reported the whole list as
  /// faulting. Amber is a fault (the tone rule); a resolved issue is a
  /// completed thing and reads green.
  StatusTone get tone => isResolved ? StatusTone.success : StatusTone.warning;

  @override
  String toString() => 'SeerrIssue($id)';
}

/// Why a [SeerrIssueDraft] cannot be sent yet.
enum SeerrIssueDraftProblem {
  /// No type was picked.
  noType,

  /// The message is empty once trimmed.
  noMessage,

  /// An episode without a season: season 0 means every season, and an
  /// episode belongs to one.
  episodeWithoutSeason,

  /// A negative season or episode.
  negativeNumber,
}

/// A problem report about to be sent (`POST /issue`).
///
/// A movie names no season or episode. A series names the season and episode
/// the problem is in, 0 for all. Season 0 is "every season" to Seerr, so
/// Specials cannot be reported on their own and are never offered.
///
/// The message is user text: it never appears in [toString].
@immutable
class SeerrIssueDraft {
  /// A problem with a movie.
  const SeerrIssueDraft.movie({
    required this.type,
    required this.message,
    required this.mediaId,
  }) : problemSeason = null,
       problemEpisode = null;

  /// A problem with a series, 0 for the whole of it, one season, or one
  /// episode of a season.
  const SeerrIssueDraft.series({
    required this.type,
    required this.message,
    required this.mediaId,
    this.problemSeason = 0,
    this.problemEpisode = 0,
  });

  final SeerrIssueType? type;
  final String message;

  /// Seerr's media id (`mediaInfo.id`), never TMDB's.
  final int mediaId;

  /// Null for a movie.
  final int? problemSeason;

  /// Null for a movie.
  final int? problemEpisode;

  bool get isSeries => problemSeason != null;

  /// The first thing that stops this draft from being sent, or null.
  SeerrIssueDraftProblem? get problem {
    if (type == null) return SeerrIssueDraftProblem.noType;
    if (message.trim().isEmpty) return SeerrIssueDraftProblem.noMessage;
    final season = problemSeason ?? 0;
    final episode = problemEpisode ?? 0;
    if (season < 0 || episode < 0) return SeerrIssueDraftProblem.negativeNumber;
    if (episode > 0 && season == 0) {
      return SeerrIssueDraftProblem.episodeWithoutSeason;
    }
    return null;
  }

  bool get isValid => problem == null;

  /// The body of `POST /issue`: the type, the message, the media, and for a
  /// series the season and episode. Never a `userId`: Seerr reports as the
  /// caller.
  ///
  /// Throws a [StateError] for a draft that is not [isValid]; the sheet
  /// never offers to send one.
  Map<String, dynamic> toJson() {
    final stopped = problem;
    if (stopped != null) {
      throw StateError('The report cannot be sent: ${stopped.name}.');
    }
    return {
      'issueType': type!.wire,
      'message': message.trim(),
      'mediaId': mediaId,
      if (isSeries) ...{
        'problemSeason': problemSeason,
        'problemEpisode': problemEpisode,
      },
    };
  }

  @override
  String toString() => 'SeerrIssueDraft($mediaId)';
}

/// How many issues the server holds (`GET /issue/count`). A figure Seerr did
/// not send is null, never 0.
@immutable
class SeerrIssueCount {
  const SeerrIssueCount({
    this.open,
    this.closed,
    this.total,
    this.video,
    this.audio,
    this.subtitles,
    this.other,
  });

  final int? open;
  final int? closed;
  final int? total;
  final int? video;
  final int? audio;
  final int? subtitles;
  final int? other;

  factory SeerrIssueCount.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return SeerrIssueCount(
      open: intOrNull(json['open']),
      closed: intOrNull(json['closed']),
      total: intOrNull(json['total']),
      video: intOrNull(json['video']),
      audio: intOrNull(json['audio']),
      subtitles: intOrNull(json['subtitles']),
      // Seerr spells this one `others`.
      other: intOrNull(json['others'] ?? json['other']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeerrIssueCount &&
      other.open == open &&
      other.closed == closed &&
      other.total == total &&
      other.video == video &&
      other.audio == audio &&
      other.subtitles == subtitles &&
      other.other == this.other;

  @override
  int get hashCode =>
      Object.hash(open, closed, total, video, audio, subtitles, other);

  @override
  String toString() => 'SeerrIssueCount(open: $open, closed: $closed)';
}
