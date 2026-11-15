import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';

import '../../../../test_helpers/fixtures.dart';

void main() {
  group('SeerrIssue.fromJson', () {
    final issue = SeerrIssue.fromJson(
      jsonFixtureMap('seerr/issue_detail.json'),
    );

    test('reads the problem and where it is', () {
      expect(issue.id, 22);
      expect(issue.type, SeerrIssueType.subtitles);
      expect(issue.issueTypeLabel, 'Subtitles');
      expect(issue.problemSeason, 2);
      expect(issue.problemEpisode, 4);
      expect(issue.media?.id, 82);
      expect(issue.media?.tmdbId, 1399);
      expect(issue.isOpen, isTrue);
      expect(issue.tone, StatusTone.warning);
    });

    test("the media row's availability tells whether it is on the server", () {
      // Status 4 on a series: partly there.
      expect(issue.media?.status, 4);
      expect(issue.media?.isOnServer, isTrue);
      SeerrIssueMedia media(String type, {int? status, int? status4k}) =>
          SeerrIssueMedia.fromJson({
            'mediaType': type,
            'status': status,
            'status4k': status4k,
          });
      expect(media('movie', status: 5).isOnServer, isTrue);
      expect(media('movie', status: 1, status4k: 5).isOnServer, isTrue);
      // Partly available is a series' word, never a movie's.
      expect(media('movie', status: 4).isOnServer, isFalse);
      expect(media('tv', status: 4).isOnServer, isTrue);
      // Requested, in the works, or not said: not a claim either way.
      for (final code in [null, 1, 2, 3]) {
        expect(media('movie', status: code).isOnServer, isFalse);
      }
    });

    test('naming a title from its page keeps the rest of the row', () {
      final named = issue.media!.copyWith(
        title: 'Game of Thrones',
        posterPath: '/got.jpg',
        year: '2011',
      );
      expect(named.title, 'Game of Thrones');
      expect(named.year, '2011');
      expect(named.id, 82);
      expect(named.tmdbId, 1399);
      expect(named.status, 4);
      expect(named.isOnServer, isTrue);
    });

    test('the first comment is the report, the rest are replies', () {
      expect(issue.message, 'Subtitles are missing');
      expect(issue.comments, hasLength(3));
      expect(issue.commentCount, 3);
      expect(issue.replies.map((c) => c.message), [
        'Which language?',
        'Italian, episode 4',
      ]);
    });

    test('a comment carries its author from the detail', () {
      expect(issue.comments.first.authorId, 5);
      expect(issue.comments.first.authorName, 'Luca');
      expect(issue.comments[1].authorId, 1);
      expect(issue.comments[1].authorName, 'Matt');
      expect(issue.comments[2].isEdited, isTrue);
      expect(issue.comments[0].isEdited, isFalse);
    });

    test('the list sends comments without a user: the author is unknown', () {
      final listed = SeerrIssue.fromJson(
        ((jsonFixtureMap('seerr/issues.json')['results']) as List)[1],
      );
      expect(listed.comments, hasLength(2));
      expect(listed.commentCount, 2);
      expect(listed.comments.first.authorId, isNull);
      expect(listed.comments.first.authorName, isNull);
      expect(listed.comments.first.isBy(5), isFalse);
      expect(listed.message, 'Subtitles are missing');
    });

    test('own is the reporter\'s id, and never the key', () {
      expect(issue.isReportedBy(5), isTrue);
      expect(issue.isReportedBy(4), isFalse);
      expect(issue.isReportedBy(null), isFalse);
      expect(issue.comments[1].isBy(1), isTrue);
      expect(issue.comments[1].isBy(5), isFalse);
      expect(issue.comments[1].isBy(null), isFalse);
    });

    test('sparse answers keep every field optional', () {
      final bare = SeerrIssue.fromJson({'id': 3});
      expect(bare.problemSeason, 0);
      expect(bare.problemEpisode, 0);
      expect(bare.comments, isEmpty);
      expect(bare.message, isNull);
      expect(bare.replies, isEmpty);
      expect(bare.commentCount, 0);
      expect(bare.type, isNull);
      expect(bare.issueTypeLabel, 'Issue');
      expect(SeerrIssue.fromJson({'id': 3, 'commentCount': 5}).commentCount, 5);
    });

    test('resolved reads green and cannot be resolved again', () {
      final done = SeerrIssue.fromJson({'id': 3, 'status': 2});
      expect(done.isResolved, isTrue);
      expect(done.tone, StatusTone.success);
    });

    test('copyWith keeps the conversation and the count', () {
      final named = issue.copyWith(
        media: issue.media?.copyWith(title: 'Game of Thrones'),
      );
      expect(named.media?.title, 'Game of Thrones');
      expect(named.comments, hasLength(3));
      expect(named.problemEpisode, 4);
    });
  });

  group('user text stays out of strings', () {
    test('an issue, a comment and a draft print no message', () {
      final issue = SeerrIssue.fromJson(
        jsonFixtureMap('seerr/issue_detail.json'),
      );
      const draft = SeerrIssueDraft.movie(
        type: SeerrIssueType.video,
        message: 'secret words',
        mediaId: 81,
      );
      for (final text in [
        issue.toString(),
        issue.comments.first.toString(),
        draft.toString(),
      ]) {
        expect(text, isNot(contains('Subtitles are missing')));
        expect(text, isNot(contains('secret words')));
      }
    });
  });

  group('SeerrIssueType and SeerrIssueStatus', () {
    test('read Seerr numbers', () {
      expect(SeerrIssueType.fromWire(1), SeerrIssueType.video);
      expect(SeerrIssueType.fromWire('4'), SeerrIssueType.other);
      expect(SeerrIssueType.fromWire(99), isNull);
      expect(SeerrIssueStatus.fromWire(2), SeerrIssueStatus.resolved);
      expect(SeerrIssueStatus.fromWire(null), isNull);
      expect(SeerrIssueStatus.open.route, 'open');
      expect(SeerrIssueStatus.resolved.route, 'resolved');
    });
  });

  group('SeerrIssueDraft', () {
    test('a movie sends the type, the message and the media, nothing else', () {
      const draft = SeerrIssueDraft.movie(
        type: SeerrIssueType.audio,
        message: '  Out of sync  ',
        mediaId: 81,
      );
      expect(draft.toJson(), {
        'issueType': 2,
        'message': 'Out of sync',
        'mediaId': 81,
      });
    });

    test('a series sends season and episode, 0 for all', () {
      const whole = SeerrIssueDraft.series(
        type: SeerrIssueType.video,
        message: 'x',
        mediaId: 82,
      );
      expect(whole.toJson(), {
        'issueType': 1,
        'message': 'x',
        'mediaId': 82,
        'problemSeason': 0,
        'problemEpisode': 0,
      });
      const episode = SeerrIssueDraft.series(
        type: SeerrIssueType.subtitles,
        message: 'x',
        mediaId: 82,
        problemSeason: 2,
        problemEpisode: 4,
      );
      expect(episode.toJson()['problemSeason'], 2);
      expect(episode.toJson()['problemEpisode'], 4);
      const season = SeerrIssueDraft.series(
        type: SeerrIssueType.video,
        message: 'x',
        mediaId: 82,
        problemSeason: 3,
      );
      expect(season.toJson()['problemEpisode'], 0);
    });

    test('never sends a user', () {
      for (final draft in const [
        SeerrIssueDraft.movie(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
        ),
        SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
        ),
      ]) {
        expect(draft.toJson().containsKey('userId'), isFalse);
      }
    });

    test('a movie sends no season or episode keys', () {
      const draft = SeerrIssueDraft.movie(
        type: SeerrIssueType.other,
        message: 'x',
        mediaId: 1,
      );
      expect(draft.toJson().keys, ['issueType', 'message', 'mediaId']);
    });

    final problems = <(String, SeerrIssueDraft, SeerrIssueDraftProblem?)>[
      (
        'a type is required',
        const SeerrIssueDraft.movie(type: null, message: 'x', mediaId: 1),
        SeerrIssueDraftProblem.noType,
      ),
      (
        'a message is required',
        const SeerrIssueDraft.movie(
          type: SeerrIssueType.video,
          message: '',
          mediaId: 1,
        ),
        SeerrIssueDraftProblem.noMessage,
      ),
      (
        'spaces are no message',
        const SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: ' \n\t ',
          mediaId: 1,
        ),
        SeerrIssueDraftProblem.noMessage,
      ),
      (
        'an episode needs a season: season 0 is every season, not Specials',
        const SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
          problemEpisode: 3,
        ),
        SeerrIssueDraftProblem.episodeWithoutSeason,
      ),
      (
        'a negative season is no season',
        const SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
          problemSeason: -1,
        ),
        SeerrIssueDraftProblem.negativeNumber,
      ),
      (
        'a season alone is fine',
        const SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
          problemSeason: 1,
        ),
        null,
      ),
      (
        'an episode of a season is fine',
        const SeerrIssueDraft.series(
          type: SeerrIssueType.video,
          message: 'x',
          mediaId: 1,
          problemSeason: 1,
          problemEpisode: 1,
        ),
        null,
      ),
    ];
    for (final (name, draft, expected) in problems) {
      test(name, () {
        expect(draft.problem, expected);
        expect(draft.isValid, expected == null);
        if (expected != null) {
          expect(draft.toJson, throwsStateError);
        }
      });
    }

    test('a draft that cannot be sent says why without its words', () {
      const draft = SeerrIssueDraft.movie(
        type: null,
        message: 'my private words',
        mediaId: 1,
      );
      expect(
        () => draft.toJson(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
    });
  });

  group('SeerrIssueCount', () {
    test('reads Seerr\'s count, `others` included', () {
      final count = SeerrIssueCount.fromJson(
        jsonFixtureMap('seerr/issue_count.json'),
      );
      expect(count.total, 7);
      expect(count.open, 4);
      expect(count.closed, 3);
      expect(count.video, 3);
      expect(count.audio, 2);
      expect(count.subtitles, 1);
      expect(count.other, 1);
    });

    test('a figure Seerr did not send is null, never 0', () {
      final count = SeerrIssueCount.fromJson({'open': 2});
      expect(count.open, 2);
      expect(count.closed, isNull);
      expect(count.total, isNull);
      expect(count.video, isNull);
      expect(count.other, isNull);
      final none = SeerrIssueCount.fromJson('nonsense');
      expect(none.open, isNull);
      expect(none, const SeerrIssueCount());
    });
  });
}
