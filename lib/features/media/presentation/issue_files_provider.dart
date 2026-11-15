import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One file the arrs hold that a reported problem could be about: what it
/// is, where it sits, and the release search that would replace it.
@immutable
class IssueFile {
  const IssueFile({
    required this.connectionId,
    required this.connectionName,
    required this.fileName,
    required this.target,
    this.quality,
    this.size,
    this.importedAt,
    this.episode = false,
  });

  /// The Radarr or Sonarr connection that holds it.
  final String connectionId;

  /// `Radarr`, `Radarr · 4K`: how the title's page names that connection.
  final String connectionName;

  /// The arr's quality name, `Remux-2160p`; null when it did not say.
  final String? quality;
  final int? size;

  /// The file's name as the arr wrote it: a machine string, drawn whole.
  final String fileName;
  final DateTime? importedAt;

  /// An episode's file rather than a movie's.
  final bool episode;

  /// The release search that looks for another copy of it, already stamped
  /// with [connectionId].
  final ReleaseSearchTarget target;

  /// `2160p Remux · 9.8 GB`, whichever of the two the arr said; empty with
  /// neither.
  String get headline => [
    if (quality case final q? when q.isNotEmpty) qualityWords(q),
    if (size case final s? when s > 0) formatBytes(s),
  ].join(dotSeparator);

  @override
  bool operator ==(Object other) =>
      other is IssueFile &&
      other.connectionId == connectionId &&
      other.fileName == fileName &&
      other.quality == quality &&
      other.size == size &&
      other.importedAt == importedAt &&
      other.target == target;

  @override
  int get hashCode =>
      Object.hash(connectionId, fileName, quality, size, importedAt, target);
}

/// Which files a thread asks for: the title, and for a series the season and
/// episode the problem is in (0 for none). [title] names the release search.
typedef IssueFilesScope = ({
  MediaKey key,
  int season,
  int episode,
  String title,
});

/// The files the title page already reads for [IssueFilesScope.key], from
/// the arrs: a movie's file on each Radarr that holds one, and for a problem
/// in one episode that episode's file on each Sonarr that holds it.
///
/// Nothing is asked of its own: it watches the page's own copies, so a title
/// whose copies are already read costs no request. A copy not yet read, one
/// that failed and one with no file draw nothing, and so does a problem that
/// names no file (a whole series, one season). Empty means omit the section.
final issueFilesProvider = Provider.autoDispose
    .family<List<IssueFile>, IssueFilesScope>((ref, scope) {
      final settings = ref.watch(currentSettingsProvider);
      final key = scope.key;
      final files = <IssueFile>[];
      if (key.isMovie) {
        for (final radarr in settings.instancesOf(ServiceKey.radarr)) {
          if (!radarr.isConfigured) continue;
          final copy = ref
              .watch(
                mediaRadarrCopyProvider((key: key, connectionId: radarr.id)),
              )
              .value
              ?.value;
          final movie = copy?.movie;
          final file = movie?.movieFile;
          if (movie == null || file == null) continue;
          final name = file.fileName;
          if (name == null) continue;
          files.add(
            IssueFile(
              connectionId: radarr.id,
              connectionName: settings.connectionTitle(
                radarr.id,
                radarr.service,
              ),
              quality: file.qualityName,
              size: file.size,
              fileName: name,
              importedAt: file.dateAdded,
              target: ReleaseSearchTarget.movie(
                movieId: movie.id,
                label: truncateTitle(movie.title),
              ).stampedWith(radarr.id),
            ),
          );
        }
        return files;
      }
      if (scope.season <= 0 || scope.episode <= 0) return files;
      for (final sonarr in settings.instancesOf(ServiceKey.sonarr)) {
        if (!sonarr.isConfigured) continue;
        final copy = ref
            .watch(mediaSonarrCopyProvider((key: key, connectionId: sonarr.id)))
            .value
            ?.value;
        final series = copy?.series;
        if (copy == null || series == null) continue;
        final record = copy.episodes
            .where(
              (e) =>
                  e.seasonNumber == scope.season &&
                  e.episodeNumber == scope.episode,
            )
            .firstOrNull;
        final fileId = record?.episodeFileId;
        if (record == null || !record.hasFile || fileId == null) continue;
        final file = ref
            .watch(
              mediaEpisodeFilesProvider((
                connectionId: sonarr.id,
                seriesId: series.id,
              )),
            )
            .value?[fileId];
        if (file == null) continue;
        files.add(
          IssueFile(
            connectionId: sonarr.id,
            connectionName: settings.connectionTitle(sonarr.id, sonarr.service),
            quality: file.qualityName,
            size: file.size,
            fileName: file.relativePath,
            importedAt: file.dateAdded,
            episode: true,
            target: ReleaseSearchTarget.episode(
              episodeId: record.id,
              seriesId: series.id,
              seasonNumber: record.seasonNumber,
              label:
                  '${truncateTitle(scope.title)}\u00A0· '
                  '${formatEpisodeCode(record.seasonNumber, record.episodeNumber)}',
            ).stampedWith(sonarr.id),
          ),
        );
      }
      return files;
    });
