import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_issue_words.dart';

SeerrIssue _issue({int status = 1, int season = 0, int episode = 0}) =>
    SeerrIssue.fromJson({
      'id': 1,
      'issueType': 1,
      'status': status,
      'problemSeason': season,
      'problemEpisode': episode,
    });

void main() {
  group('where in a series the problem is', () {
    test('a movie, or a series as a whole, has no place', () {
      expect(issuePlace(_issue()), isNull);
    });

    test('a season, and an episode of it', () {
      expect(issuePlace(_issue(season: 2)), 'S2');
      expect(
        issuePlace(_issue(season: 2, episode: 3)),
        formatEpisodeCode(2, 3),
      );
    });

    test(
      'an episode without a season names nothing: season 0 is every one',
      () {
        expect(issuePlace(_issue(episode: 3)), isNull);
      },
    );
  });

  group('where it stands, as each reader says it', () {
    test('open is a fault to the operator and a wait to the requester', () {
      expect(issueState(_issue(), operator: true), (
        word: 'Open',
        tone: StatusTone.warning,
      ));
      expect(issueState(_issue(), operator: false), (
        word: 'Reported',
        tone: StatusTone.info,
      ));
    });

    test('resolved is green and quiet for both', () {
      for (final operator in [true, false]) {
        expect(issueState(_issue(status: 2), operator: operator), (
          word: 'Resolved',
          tone: StatusTone.success,
        ));
      }
    });
  });

  group('when it was said', () {
    final now = DateTime(2026, 10, 5, 12, 30);

    test('today and yesterday carry the clock', () {
      expect(
        issueMoment(DateTime(2026, 10, 5, 8, 12), now: now),
        'today 08:12',
      );
      expect(
        issueMoment(DateTime(2026, 10, 4, 21, 40), now: now),
        'yesterday 21:40',
      );
    });

    test('older, the day alone', () {
      expect(issueMoment(DateTime(2026, 10, 2, 9, 0), now: now), 'Friday');
      expect(
        issueMoment(DateTime(2026, 9, 26, 21, 40), now: now),
        'Sat 26 Sep',
      );
    });

    test('a clock ahead of this one is still today', () {
      expect(
        issueMoment(DateTime(2026, 10, 5, 23, 0), now: now),
        'today 23:00',
      );
    });
  });

  test('replies are counted in the singular and the plural', () {
    expect(repliesLabel(1), '1 reply');
    expect(repliesLabel(2), '2 replies');
  });

  group('what the others said to the reporter', () {
    SeerrIssue conversation(List<(int, String)> authors) =>
        SeerrIssue.fromJson({
          'id': 1,
          'issueType': 1,
          'status': 1,
          'comments': [
            {
              'id': 1,
              'message': 'It is wrong',
              'user': {'id': 7, 'displayName': 'Anna'},
            },
            for (final (index, (id, name)) in authors.indexed)
              {
                'id': 2 + index,
                'message': 'Reply',
                'user': {'id': id, 'displayName': name},
              },
          ],
        });

    test('nobody else replied: nothing to say', () {
      expect(replyLineFrom(conversation([]), me: 7), isNull);
      // Her own reply is not said back to her.
      expect(replyLineFrom(conversation([(7, 'Anna')]), me: 7), isNull);
    });

    test('one name, two, and the first and the others', () {
      expect(
        replyLineFrom(conversation([(1, 'Matt')]), me: 7),
        '1 reply from Matt',
      );
      expect(
        replyLineFrom(
          conversation([(1, 'Matt'), (2, 'Luca'), (1, 'Matt')]),
          me: 7,
        ),
        '3 replies from Matt and Luca',
      );
      expect(
        replyLineFrom(
          conversation([(1, 'Matt'), (2, 'Luca'), (3, 'Sara'), (4, 'Marco')]),
          me: 7,
        ),
        '4 replies from Matt and 3 others',
      );
    });

    test('her own replies are not counted among the others', () {
      expect(
        replyLineFrom(conversation([(7, 'Anna'), (1, 'Matt')]), me: 7),
        '1 reply from Matt',
      );
    });
  });

  test('who said what about where, without when', () {
    final issue = SeerrIssue.fromJson({
      'id': 1,
      'issueType': 2,
      'status': 1,
      'problemSeason': 2,
      'problemEpisode': 3,
      'createdBy': {'id': 7, 'displayName': 'Anna'},
    });
    expect(issueWho(issue), 'S2\u00A0E3\u00A0· Audio\u00A0· Anna');
    expect(issueWho(_issue()), 'Video');
  });
}
