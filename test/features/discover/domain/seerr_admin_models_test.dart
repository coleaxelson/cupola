import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';

void main() {
  test(
    'parses the documented issue shape and keeps optional fields optional',
    () {
      final issue = SeerrIssue.fromJson({
        'id': '21',
        'issueType': '2',
        // Seerr's own row: no title, only what names the title elsewhere.
        'media': {'id': 81, 'mediaType': 'movie', 'tmdbId': 550},
        'createdBy': {'username': 'matt'},
        'comments': [
          {'id': 1},
        ],
      });

      expect(issue.id, 21);
      expect(issue.issueTypeLabel, 'Audio');
      expect(issue.media?.title, isNull);
      expect(issue.media?.tmdbId, 550);
      expect(issue.media?.mediaType, 'movie');
      expect(issue.createdBy?.displayName, 'matt');
      expect(issue.commentCount, 1);
      expect(issue.tone.name, 'warning');
    },
  );

  test('a Jellyfin account reads the name Seerr computed, not its email', () {
    final user = SeerrUser.fromJson({
      'id': 6,
      'email': 'anna@example.com',
      'displayName': 'Anna',
      'jellyfinUsername': 'anna.j',
    });

    expect(user.displayName, 'Anna');
    expect(
      SeerrUser.fromJson({
        'id': 6,
        'email': 'anna@example.com',
        'jellyfinUsername': 'anna.j',
      }).displayName,
      'anna.j',
    );
  });

  test('an account with nothing but an email reads the email', () {
    final user = SeerrUser.fromJson({'id': 7, 'email': 'luca@example.com'});

    expect(user.displayName, 'luca@example.com');
  });

  test('uses safe fallbacks for a sparse user', () {
    final user = SeerrUser.fromJson({'id': 4, 'email': 'matt@example.com'});

    expect(user.displayName, 'matt@example.com');
    expect(user.requestCount, isNull);
  });
}
