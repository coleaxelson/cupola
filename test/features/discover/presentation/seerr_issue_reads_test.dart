/// The reads that speak of Seerr's issues, and the one helper that drops them
/// all: a report, a reply, a resolve, a reopen and a delete each call it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';

import '../../../test_helpers/fake_services.dart';

void main() {
  late FakeSeerrService seerr;
  late ProviderContainer container;

  setUp(() {
    seerr = FakeSeerrService()
      ..issueCount = const SeerrIssueCount(open: 2)
      ..issues = [
        SeerrIssue.fromJson({
          'id': 1,
          'issueType': 1,
          'status': 1,
          'comments': [
            {'id': 1, 'message': 'It is wrong'},
          ],
        }),
      ];
    container = ProviderContainer(
      overrides: [
        seerrServiceProvider.overrideWith((ref) => seerr),
        seerrServiceForProvider.overrideWith((ref, id) => seerr),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> readAll() async {
    await container.read(issueCountProvider('').future);
    await container.read(latestOpenIssuesProvider('').future);
    await container.read(ownIssuesProvider('').future);
    await container.read(seerrIssuesProvider(SeerrIssueFilter.open).future);
  }

  test('the count is Seerr\'s own and the page is the newest few', () async {
    expect((await container.read(issueCountProvider('').future)).open, 2);
    expect(
      (await container.read(latestOpenIssuesProvider('').future)).single.id,
      1,
    );
    expect(seerr.issueCountReads, 1);
    expect(seerr.latestIssueReads, 1);
  });

  test('a count that did not answer is an error and never a zero', () async {
    seerr.issueCount = null;

    await expectLater(
      container.read(issueCountProvider('').future),
      throwsException,
    );
  });

  test('one helper drops every read that speaks of issues', () async {
    await readAll();
    expect(seerr.issueCountReads, 1);
    expect(seerr.latestIssueReads, 1);
    // Held, as a screen that shows them holds them.
    container
      ..listen(issueCountProvider(''), (_, _) {})
      ..listen(latestOpenIssuesProvider(''), (_, _) {})
      ..listen(ownIssuesProvider(''), (_, _) {})
      ..listen(seerrIssuesProvider(SeerrIssueFilter.open), (_, _) {});

    invalidateSeerrIssues(container);
    await readAll();

    expect(seerr.issueCountReads, 2);
    expect(seerr.latestIssueReads, 2);
  });

  test('a write on an issue that has no known title drops the same reads '
      'and the issue\'s page', () async {
    await readAll();
    container
      ..listen(issueCountProvider(''), (_, _) {})
      ..listen(latestOpenIssuesProvider(''), (_, _) {});

    readIssuesAgain(container);
    await readAll();

    expect(seerr.issueCountReads, 2);
    expect(seerr.latestIssueReads, 2);
  });
}
