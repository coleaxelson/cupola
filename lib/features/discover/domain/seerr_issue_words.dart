import 'package:cupola/core/status/media_status.dart';
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
