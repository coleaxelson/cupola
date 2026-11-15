import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';

/// Which title's report a surface draws, and the Seerr connection the page
/// was opened from (`MediaPage.focus`).
typedef MediaReportScope = ({MediaKey key, String? focus});

/// The Seerr a report on the title goes to, once its record says the title is
/// on the server; null otherwise, and the surface draws nothing.
///
/// Derived from the page's own rows, so it asks nothing of its own.
final mediaReportSourceProvider = Provider.autoDispose
    .family<MediaReportSource?, MediaReportScope>(
      (ref, scope) => mediaReportSourceOf(
        ref.watch(mediaRowsProvider(scope.key)),
        movie: scope.key.isMovie,
        focus: scope.focus,
      ),
    );

/// One issue with its conversation, read for the row that speaks of it:
/// Seerr's list on a title carries neither the words nor the replies.
final mediaReportIssueProvider = FutureProvider.autoDispose
    .family<SeerrIssue, ({String connectionId, int issueId})>(
      (ref, source) => ref
          .watch(seerrServiceForProvider(source.connectionId))
          .getIssue(source.issueId),
      retry: noProviderRetry,
    );

/// After a report is filed: the title's Seerr record and the Issues list are
/// read again, so the row says so and the list holds it.
void readReportsAgain(
  ProviderContainer container, {
  required MediaKey key,
  required String connectionId,
}) {
  container
    ..invalidate(
      mediaSeerrRecordProvider((key: key, connectionId: connectionId)),
    )
    ..invalidate(mediaReportIssueProvider)
    ..invalidate(seerrIssuesProvider);
}
