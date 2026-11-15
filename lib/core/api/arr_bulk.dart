import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/parallel_reads.dart';

/// What an arr's editor (`PUT /…/editor`) is asked to set on a set of titles.
///
/// Every arr's editor leaves a field it was not sent alone, so an edit carries
/// only what was chosen: a title's other settings are never written back from
/// a copy that may be stale. A service sends the fields its own editor takes
/// (Radarr's has no `monitorNewItems` and no metadata profile).
@immutable
class ArrBulkEdit {
  const ArrBulkEdit({
    this.monitored,
    this.monitorNewItems,
    this.qualityProfileId,
    this.metadataProfileId,
  });

  /// Whether the arr watches the title; null leaves it as it is.
  final bool? monitored;

  /// What the arr does with albums, seasons or books it learns of later:
  /// `all`, `none` or (Lidarr's) `new`; null leaves it as it is.
  final String? monitorNewItems;

  final int? qualityProfileId;
  final int? metadataProfileId;

  /// Nothing is to change.
  bool get isEmpty =>
      monitored == null &&
      monitorNewItems == null &&
      qualityProfileId == null &&
      metadataProfileId == null;

  /// The fields of the request body, those that are set.
  Map<String, dynamic> get fields => {
    'monitored': ?monitored,
    'monitorNewItems': ?monitorNewItems,
    'qualityProfileId': ?qualityProfileId,
    'metadataProfileId': ?metadataProfileId,
  };
}

/// What an arr said of a set of titles a write was for: the ids it took and,
/// for each it refused, what it refused with.
///
/// Only what the arr reported. A title is in [refused] because its own request
/// was turned down, and never because a request for several was.
@immutable
class ArrBulkResult {
  const ArrBulkResult({required this.done, this.refused = const {}});

  final List<int> done;

  /// The failure each refused title's request ended in, by id.
  final Map<int, Object> refused;
}

/// Whether [error] is an arr turning a *request* down for what was in it,
/// which a request for fewer titles can get a different answer to: a 400, 409
/// or 422. Not a refused key (401, 403), not a missing route and not a server
/// fault: those would answer every title the same.
bool isBulkRefusal(Object error) =>
    error is DioException &&
    switch (error.response?.statusCode) {
      400 || 409 || 422 => true,
      _ => false,
    };

/// How many titles are asked at once when they have to be asked one by one: a
/// NAS answers a handful of small writes together and not a thousand.
const int bulkLanes = 4;

/// [send] for all of [ids] at once, and, when the arr refuses that
/// ([isBulkRefusal]), for each one by itself.
///
/// The arrs' editors validate the whole set before saving any, name no title in
/// a refusal, and (for a delete) report nothing per title, so the set is asked
/// first, which is one write however many titles there are, and a refusal of it
/// (nothing was saved) is followed by one request per title, so each answer is
/// real. Any other failure is not about any title: it is thrown.
Future<ArrBulkResult> bulkInOne(
  List<int> ids,
  Future<Object?> Function(List<int> ids) send,
) async {
  try {
    await send(ids);
    return ArrBulkResult(done: ids);
  } catch (error) {
    if (!isBulkRefusal(error)) rethrow;
    // One title asked alone and refused is that title's refusal.
    if (ids.length == 1) {
      return ArrBulkResult(done: const [], refused: {ids.single: error});
    }
  }
  return bulkEachOf(ids, (id) => send([id]));
}

/// [task] for each of [ids], [bulkLanes] at a time, the failure of one kept
/// with its id and never stopping the others.
Future<ArrBulkResult> bulkEachOf(
  List<int> ids,
  Future<Object?> Function(int id) task,
) async {
  final errors = await runInLanes<Object?>(ids.length, bulkLanes, (
    index,
  ) async {
    try {
      await task(ids[index]);
      return null;
    } catch (error) {
      return error;
    }
  });
  return ArrBulkResult(
    done: [
      for (final (index, id) in ids.indexed)
        if (errors[index] == null) id,
    ],
    refused: {for (final (index, id) in ids.indexed) id: ?errors[index]},
  );
}
