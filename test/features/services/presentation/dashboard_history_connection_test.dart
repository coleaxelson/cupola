/// A history record carries the connection it came off.
///
/// A record's ids are its server's. Each Radarr numbers its movies from one, so
/// "movie 1" on the 4K is a different movie on the HD: whatever opens from a
/// record (History's row, a card) must resolve its connection from the record,
/// never through the lens at tap time.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import 'package:cupola/demo/world/service_fakes.dart';

/// One failed download of Elephants Dream, movie 1 on the 4K Radarr.
Map<String, Object?> _failedDownload(DateTime now) => {
  'id': 41,
  'movieId': 1,
  'eventType': 'downloadFailed',
  'sourceTitle': 'Elephants.Dream.2006.2160p.UHD.BluRay',
  'date': now.subtract(const Duration(minutes: 20)).toUtc().toIso8601String(),
  'movie': {'id': 1, 'title': 'Elephants Dream', 'year': 2006},
  'data': {'message': 'Not a valid video file'},
};

void main() {
  test(
    'P1, lens on the 4K: a failed download keeps the 4K connection',
    () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withLens(ServiceKey.radarr, WorldIds.radarr4k),
      );
      harness.network.on(
        WorldIds.radarr4k,
        'GET',
        '/api/v3/history',
        (r) => NetworkReply.json(
          pagedEnvelope(r, [_failedDownload(harness.network.now)]),
        ),
      );
      final container = harness.container(retry: (_, _) => null);

      final history = await container.read(servicesArrHistoryProvider.future);
      final entry = history.entries.singleWhere(
        (entry) => entry.outcome == ArrImportOutcome.failed,
      );
      expect(entry.instanceId, WorldIds.radarr4k);
    },
  );
}
