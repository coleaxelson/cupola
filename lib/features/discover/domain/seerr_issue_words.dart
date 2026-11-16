import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart'
    show joinDisplayParts;
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';

/// The words an issue is told in, on the Issues tab and on its own page: one
/// place, so a row and the page it opens never disagree.

/// Where in a series the problem is: `S2 E3`, `S2`, or null for the whole
/// title (a movie, or a series reported as one).
String? issuePlace(SeerrIssue issue) => switch ((
  issue.problemSeason,
  issue.problemEpisode,
)) {
  (final season, _) when season <= 0 => null,
  (final season, final episode) when episode <= 0 => formatSeasonCode(season),
  (final season, final episode) => formatEpisodeCode(season, episode),
};

/// Who said what about where, without when: `S2 E3 · Audio · Anna`. The line
/// of a row that says its day itself, at the moment it is drawn.
String issueWho(SeerrIssue issue) => joinDisplayParts([
  issuePlace(issue),
  issue.type?.label,
  issue.createdBy?.displayName,
]);

/// `1 reply`, `3 replies`.
String repliesLabel(int count) => count == 1 ? '1 reply' : '$count replies';

/// A state word and its tone.
typedef IssueState = ({String word, StatusTone tone});

/// Where an issue stands, as its reader says it.
///
/// An open issue is a fault to fix for whoever runs the server (amber,
/// `Open`) and a wait on someone else for whoever reported it (blue,
/// `Reported`); a resolved one is green and quiet for both.
IssueState issueState(SeerrIssue issue, {required bool operator}) {
  if (issue.isResolved) {
    return (word: 'Resolved', tone: StatusTone.success);
  }
  return operator
      ? (word: 'Open', tone: StatusTone.warning)
      : (word: 'Reported', tone: StatusTone.info);
}

/// When a thing was said, as the thread tells it: `today 08:12`, `yesterday
/// 21:40`, then the day the app says days (`Wednesday`, `Sat 26 Sep`).
String issueMoment(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final past = formatPastDay(local, now: now);
  final clock = formatClockTime(local);
  return switch (past) {
    null => 'today $clock',
    'yesterday' => 'yesterday $clock',
    final day => day,
  };
}

/// What the others said to the reporter, as her list says it: `1 reply from
/// Matt`, `3 replies from Matt and Luca`, `2 replies from Matt and 2 others`.
///
/// Read from an issue **with its conversation** ([me] is the account that
/// reported it, whose own replies are not said back to her); null when nobody
/// else replied. A reply whose author the server did not name is counted and
/// not attributed: `2 replies`.
String? replyLineFrom(SeerrIssue issue, {required int? me}) {
  final others = [
    for (final reply in issue.replies)
      if (!reply.isBy(me)) reply,
  ];
  if (others.isEmpty) return null;
  final names = <String>[];
  for (final reply in others) {
    final name = reply.authorName?.trim();
    if (name != null && name.isNotEmpty && !names.contains(name)) {
      names.add(name);
    }
  }
  final count = repliesLabel(others.length);
  return switch (names.length) {
    0 => count,
    1 => '$count from ${names[0]}',
    2 => '$count from ${names[0]} and ${names[1]}',
    final many => '$count from ${names[0]} and ${many - 1} others',
  };
}
