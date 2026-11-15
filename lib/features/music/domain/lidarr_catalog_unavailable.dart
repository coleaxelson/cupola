import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';

/// Lidarr answered, but the online catalog it looks artists and albums up in
/// (LidarrAPI, its metadata server) did not: its search needs that catalog,
/// and the library does not.
///
/// Lidarr reports it as a 503 whose message names LidarrAPI (`Search for
/// 'elbow' failed. Unable to communicate with LidarrAPI.`, `LidarrAPI is
/// temporarily unavailable`, or an invalid response from it): its
/// `SkyHookException`. A 503 that does not name it is something else in front
/// of Lidarr (a proxy with nothing behind it) and stays an ordinary failure:
/// Lidarr itself did not answer.
class LidarrCatalogUnavailable implements Exception {
  const LidarrCatalogUnavailable([this.message]);

  /// What Lidarr said, when it said anything.
  final String? message;

  /// [error] as Lidarr's catalog failure, or null when it is anything else.
  static LidarrCatalogUnavailable? of(Object? error) {
    final cause = unwrapFailure(error);
    if (cause is! DioException || cause.response?.statusCode != 503) {
      return null;
    }
    final message = failureServiceMessage(cause);
    if (message == null || !message.toLowerCase().contains('lidarrapi')) {
      return null;
    }
    return LidarrCatalogUnavailable(message);
  }

  @override
  String toString() => 'LidarrCatalogUnavailable(${message ?? ''})';
}
