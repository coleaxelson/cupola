/// Issue 15: a `downloadFailed` that Sonarr already handled (it blocklists the
/// release and searches again) is a fact for History, not a Needs you fault,
/// and the replacement its delay profile holds says when it starts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/demo/world/service_fakes.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _series = {
  'id': 12,
  'title': 'Tulsa King',
  'tmdbId': 153312,
  'images': <Object?>[],
};
const _episode = {
  'id': 5005,
  'seriesId': 12,
  'seasonNumber': 4,
  'episodeNumber': 5,
  'title': 'Dinosaurs',
};
const _release =
    'Tulsa.King.S04E05.Dinosaurs.720p.AMZN.WEB-DL.DDP5.1.H.264-NTb';

final _now = DateTime.utc(2026, 10, 9, 20, 53);

Map<String, Object?> _failedDownload(DateTime at) => {
  'id': 777,
  'seriesId': 12,
  'episodeId': 5005,
  'eventType': 'downloadFailed',
  'sourceTitle': _release,
  'downloadId': 'ABCDEF0123',
  'date': at.toUtc().toIso8601String(),
  'series': _series,
  'episode': _episode,
  'data': {'message': 'Download client reported failure'},
};

/// What Sonarr's `/queue` holds for the replacement: no tracked-download
/// fields, no download id, and the time the delay profile lets go.
Map<String, Object?> _pending(String status, DateTime? ends) => {
  'id': 900,
  'seriesId': 12,
  'episodeId': 5005,
  'seasonNumber': 4,
  'series': _series,
  'episode': _episode,
  'title': _release,
  'status': status,
  'added': _now.subtract(const Duration(hours: 3)).toIso8601String(),
  'estimatedCompletionTime': ends?.toUtc().toIso8601String(),
  'protocol': 'torrent',
  'size': 1000,
  'sizeleft': 1000,
  'statusMessages': <Object?>[],
};

Future<ProviderContainer> _sonarrWith(Map<String, Object?> queued) async {
  final harness = await ProfileHarness.start(
    Profiles.p1,
    now: _now,
    overrides: [stallClockProvider.overrideWithValue(() => _now)],
  );
  harness.network.on(
    WorldIds.sonarr,
    'GET',
    '/api/v3/history',
    (r) => NetworkReply.json(
      pagedEnvelope(r, [
        _failedDownload(_now.subtract(const Duration(hours: 3))),
      ]),
    ),
  );
  harness.network.on(
    WorldIds.sonarr,
    'GET',
    '/api/v3/queue',
    (r) => NetworkReply.json(pagedEnvelope(r, [queued])),
  );
  return harness.container(retry: (_, _) => null);
}

void main() {
  test('a failed download Sonarr is retrying is no Needs you decision, no '
      'notice, and History still tells it', () async {
    final container = await _sonarrWith(
      _pending('delay', _now.add(const Duration(hours: 3))),
    );

    // Every source answered first: the merge is synchronous over their state.
    for (final source in DecisionSource.faultSources) {
      await container.read(dashboardDecisionSourceProvider(source).future);
    }
    final faults = container.read(dashboardFaultDecisionsProvider).decisions;
    expect(faults.where((d) => d.title == 'Tulsa King'), isEmpty);
    final all = container.read(dashboardDecisionsProvider).decisions;
    expect(all.where((d) => d.title == 'Tulsa King'), isEmpty);
    expect(
      needsYouNotices([
        ...faults,
        ...all,
      ], now: _now).where((notice) => notice.body.contains('Tulsa King')),
      isEmpty,
    );

    final history = await container.read(servicesArrHistoryProvider.future);
    final entry = history.entries.singleWhere(
      (e) => e.outcome == ArrImportOutcome.failed,
    );
    expect(historyEventLine(entry), startsWith('Download failed'));
  });

  test(
    'the release a delay profile holds is queued and says when it starts',
    () async {
      final container = await _sonarrWith(
        _pending('delay', _now.add(const Duration(hours: 3))),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);
      final item = inFlight.queued.singleWhere(
        (i) => i.service == ServiceKey.sonarr,
      );
      expect(item.startsInSeconds, const Duration(hours: 3).inSeconds);
      expect(
        queuedWords(item.startsInSeconds),
        'Queued\u00A0· starts in about 3\u00A0h',
      );
    },
  );

  test('a delay that already ended reads plain Queued', () async {
    final container = await _sonarrWith(
      _pending('delay', _now.subtract(const Duration(minutes: 5))),
    );
    final inFlight = await container.read(servicesInFlightProvider.future);
    final item = inFlight.queued.singleWhere(
      (i) => i.service == ServiceKey.sonarr,
    );
    expect(item.startsInSeconds, isNull);
    expect(queuedWords(item.startsInSeconds), 'Queued');
  });

  test('a record in line at its client (queued) has no estimate from the '
      'arr', () async {
    final container = await _sonarrWith(
      _pending('queued', _now.add(const Duration(hours: 3))),
    );
    final inFlight = await container.read(servicesInFlightProvider.future);
    final item = inFlight.queued.singleWhere(
      (i) => i.service == ServiceKey.sonarr,
    );
    expect(item.startsInSeconds, isNull);
  });
}
