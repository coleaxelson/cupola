/// The problems people reported, as the one fault each Seerr raises in Needs
/// you: Seerr's own count, the newest rows under it, and nothing from a Seerr
/// that did not say or that its account may not ask.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/services/presentation/services_decisions.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';

import '../../../test_helpers/profiles/profiles.dart';

SeerrIssue _issue(
  int id,
  String title,
  String reporter, {
  SeerrIssueType type = SeerrIssueType.video,
  int season = 0,
  int episode = 0,
}) => SeerrIssue(
  id: id,
  type: type,
  status: SeerrIssueStatus.open,
  problemSeason: season,
  problemEpisode: episode,
  media: SeerrIssueMedia(
    title: title,
    mediaType: 'movie',
    posterPath: '/p.jpg',
  ),
  createdBy: SeerrUser(id: id, serverDisplayName: reporter),
  createdAt: '2026-09-26T10:00:00.000Z',
);

/// The issue decisions of [profile] with [count] answering for each Seerr
/// that is asked, [rows] its newest page, and the ids that were asked.
Future<({DashboardDecisions read, List<String> counted, List<String> paged})>
_read(
  ConfigProfile profile, {
  Future<SeerrIssueCount> Function(String id)? count,
  Future<List<SeerrIssue>> Function(String id)? rows,
}) async {
  final harness = await ProfileHarness.start(profile);
  final counted = <String>[];
  final paged = <String>[];
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      issueCountProvider.overrideWith((ref, id) {
        counted.add(id);
        return (count ?? (_) async => const SeerrIssueCount(open: 3))(id);
      }),
      latestOpenIssuesProvider.overrideWith((ref, id) {
        paged.add(id);
        return (rows ?? (_) async => const <SeerrIssue>[])(id);
      }),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  final read = await container.read(
    dashboardDecisionSourceProvider(DecisionSource.issues).future,
  );
  return (read: read, counted: counted, paged: paged);
}

void main() {
  test('Seerr\'s own count is the fault, the newest rows its members, who '
      'said it its reporters', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => const SeerrIssueCount(open: 7),
      rows: (_) async => [
        _issue(31, 'Tears of Steel', 'Luca'),
        _issue(
          30,
          'Cosmos Laundromat',
          'Anna',
          type: SeerrIssueType.audio,
          season: 2,
          episode: 3,
        ),
        _issue(29, 'Big Buck Bunny', 'Luca', type: SeerrIssueType.subtitles),
      ],
    );

    final fault = result.read.decisions.single;
    expect(fault.kind, DecisionKind.reportedProblems);
    expect(fault.isFault, isTrue);
    // Seerr's count, not the three rows read.
    expect(fault.count, 7);
    expect(fault.title, '7 reported problems');
    expect(fault.detail, 'Seerr\u00A0· Issues');
    expect(fault.reporters, ['Luca', 'Anna']);
    expect(fault.route, '/stack/seerr/issues');
    expect(
      [for (final row in fault.members) row.title],
      ['Tears of Steel', 'Cosmos Laundromat', 'Big Buck Bunny'],
    );
    expect(fault.members[0].detail, 'Video\u00A0· Luca');
    expect(fault.members[1].detail, 'S2\u00A0E3\u00A0· Audio\u00A0· Anna');
    // Each row opens its own issue on the Seerr it was read from.
    expect(
      fault.members[0].route,
      '/stack/seerr/issues/31?i=${WorldIds.seerr}',
    );
    expect(result.read.coverage.failed, isEmpty);
    expect(faultWordsOf(fault).headline, '7 reported problems');
    expect(
      faultWordsOf(fault).explanation,
      'Luca and Anna say something is wrong with what they watch.',
    );
    expect(faultActionLabel(fault), 'Review 7');
  });

  test('one open problem reads in the singular and reviews without a '
      'number', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => const SeerrIssueCount(open: 1),
      rows: (_) async => [_issue(5, 'Tears of Steel', 'Luca')],
    );

    final fault = result.read.decisions.single;
    expect(fault.title, '1 reported problem');
    expect(faultActionLabel(fault), 'Review');
    expect(
      faultWordsOf(fault).explanation,
      'Luca says something is wrong with what they watch.',
    );
  });

  test('nothing open is no fault, and not a zero either', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => const SeerrIssueCount(open: 0),
    );

    expect(result.read.decisions, isEmpty);
    expect(result.read.coverage.failed, isEmpty);
    // The rows are not read for a count of nothing.
    expect(result.paged, isEmpty);
  });

  test('a count that did not answer adds nothing and is named, never a '
      'zero', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => throw Exception('no count'),
      rows: (_) async => [_issue(5, 'Tears of Steel', 'Luca')],
    );

    expect(result.read.decisions, isEmpty);
    expect(result.read.coverage.failed, hasLength(1));
    expect(result.read.coverage.failed.keys.single.service, ServiceKey.seerr);
  });

  test('a count without its figure is no answer', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => const SeerrIssueCount(),
    );

    expect(result.read.decisions, isEmpty);
    expect(result.read.coverage.failed, hasLength(1));
  });

  test('rows that did not arrive leave the fault with its count and no '
      'rows', () async {
    final result = await _read(
      Profiles.p1,
      count: (_) async => const SeerrIssueCount(open: 4),
      rows: (_) async => throw Exception('page failed'),
    );

    final fault = result.read.decisions.single;
    expect(fault.count, 4);
    expect(fault.members, isEmpty);
    expect(fault.reporters, isEmpty);
    // No sentence is said of nobody.
    expect(faultWordsOf(fault).explanation, isNull);
    expect(result.read.coverage.failed, isEmpty);
  });

  test('a Seerr whose account may not view issues is asked nothing', () async {
    // P9: the household's Seerr answers the operator's key; Sara's answers
    // an account of his that may only request.
    final result = await _read(
      Profiles.p9,
      count: (_) async => const SeerrIssueCount(open: 2),
      rows: (_) async => [_issue(8, 'Charge', 'Sara')],
    );

    expect(result.counted, [WorldIds.seerr]);
    expect(result.paged, [WorldIds.seerr]);
    final fault = result.read.decisions.single;
    expect(fault.instanceId, WorldIds.seerr);
    // Sara's connection is named under the figure as answering, not as a
    // failure: nothing was wrong with it.
    expect(result.read.coverage.failed, isEmpty);
  });

  test(
    'a requester has no problems to review: her Seerr is asked nothing',
    () async {
      final result = await _read(
        Profiles.p2,
        count: (_) async => const SeerrIssueCount(open: 2),
        rows: (_) async => [_issue(8, 'Charge', 'Sara')],
      );

      expect(result.read.decisions, isEmpty);
      expect(result.counted, isEmpty);
      expect(result.paged, isEmpty);
    },
  );

  test('the reporters are said as one, two, or the first two and the '
      'others', () {
    expect(reportersSentence(const []), isNull);
    expect(
      reportersSentence(const ['Luca']),
      'Luca says something is wrong with what they watch.',
    );
    expect(
      reportersSentence(const ['Luca', 'Anna']),
      'Luca and Anna say something is wrong with what they watch.',
    );
    expect(
      reportersSentence(const ['Luca', 'Anna', 'Sara']),
      'Luca, Anna and 1 other say something is wrong with what they watch.',
    );
    expect(
      reportersSentence(const ['Luca', 'Anna', 'Sara', 'Marco']),
      'Luca, Anna and 2 others say something is wrong with what they watch.',
    );
  });
}
