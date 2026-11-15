/// The files a problem could be about: read from the copies the title's page
/// already holds, never asked for anew.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/presentation/issue_files_provider.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/model_builders.dart';
import '../../../test_helpers/settings_scope.dart';

const _movie = MediaKey.movie(603);
const _series = MediaKey.tv(358332);

RadarrMovie _held({
  int id = 7,
  String quality = 'Remux-2160p',
  int size = 9800000000,
  bool file = true,
}) => RadarrMovie.fromJson({
  'id': id,
  'title': 'Tears of Steel',
  'sortTitle': 'tears of steel',
  'tmdbId': 603,
  'year': 2012,
  'status': 'released',
  'hasFile': file,
  'monitored': true,
  if (file)
    'movieFile': {
      'id': 70,
      'relativePath': 'Tears of Steel (2012) Remux-2160p.mkv',
      'size': size,
      'dateAdded': '2026-10-04T21:00:00Z',
      'quality': {
        'quality': {'name': quality},
      },
    },
});

MediaAnswer<T> _at<T>(T value) => MediaAnswer(value, DateTime(2026, 10, 5));

Future<ProviderContainer> _container({
  Map<String, RadarrMovie?> radarrs = const {},
  Map<String, SonarrSeries?> sonarrs = const {},
  List<SonarrEpisode> episodes = const [],
  Map<int, SonarrEpisodeFile> files = const {},
  Set<String> failing = const {},
}) async {
  final instances = {
    for (final id in radarrs.keys)
      id: ServiceInstance(
        id: id,
        service: ServiceKey.radarr,
        label: id == 'radarr' ? 'HD' : '4K',
        url: 'https://$id.test',
        credential: 'k',
      ),
    for (final id in sonarrs.keys)
      id: ServiceInstance(
        id: id,
        service: ServiceKey.sonarr,
        url: 'https://$id.test',
        credential: 'k',
      ),
  };
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...await settingsScopeOverrides(
        customize: (settings) {
          var next = settings;
          for (final instance in instances.values) {
            next = next.copyWithInstance(instance);
          }
          return next;
        },
      ),
      mediaRadarrCopyProvider.overrideWith((ref, source) async {
        if (failing.contains(source.connectionId)) throw StateError('down');
        return _at(
          MediaRadarrCopy(
            movie: radarrs[source.connectionId],
            queue: ArrQueueSnapshot.empty,
          ),
        );
      }),
      mediaSonarrCopyProvider.overrideWith((ref, source) async {
        if (failing.contains(source.connectionId)) throw StateError('down');
        return _at(
          MediaSonarrCopy(
            series: sonarrs[source.connectionId],
            queue: ArrQueueSnapshot.empty,
            episodes: episodes,
          ),
        );
      }),
      mediaEpisodeFilesProvider.overrideWith((ref, source) async => files),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The provider settled: its copies are read, and every one of them answered.
Future<List<IssueFile>> _files(
  ProviderContainer container,
  IssueFilesScope scope,
) async {
  final sub = container.listen(issueFilesProvider(scope), (_, _) {});
  addTearDown(sub.close);
  // The copies are futures: let them answer, then read what they gave.
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(issueFilesProvider(scope));
}

void main() {
  const movie = (key: _movie, season: 0, episode: 0, title: 'Tears of Steel');

  test('a movie: its file on each Radarr that holds one', () async {
    final container = await _container(
      radarrs: {
        'radarr': _held(quality: 'Bluray-1080p', size: 1200000000),
        'radarr-4k': _held(id: 9),
      },
    );
    final files = await _files(container, movie);
    expect(files.map((f) => f.connectionId), ['radarr', 'radarr-4k']);
    expect(files.map((f) => f.connectionName), [
      'Radarr\u00A0· HD',
      'Radarr\u00A0· 4K',
    ]);
    expect(files.first.headline, startsWith('1080p Bluray'));
    expect(files.last.headline, startsWith('2160p Remux'));
    expect(files.last.fileName, 'Tears of Steel (2012) Remux-2160p.mkv');
    expect(files.last.importedAt, DateTime.utc(2026, 10, 4, 21));
  });

  test(
    'its search is that copy: its movie, stamped with its connection',
    () async {
      final container = await _container(radarrs: {'radarr-4k': _held(id: 9)});
      final target = (await _files(container, movie)).single.target;
      expect(target.scope, ReleaseSearchScope.movie);
      expect(target.id, 9);
      expect(target.instanceId, 'radarr-4k');
      expect(target.service, ServiceKey.radarr);
    },
  );

  test(
    'a Radarr that holds no file, does not track it, or did not answer draws nothing',
    () async {
      final container = await _container(
        radarrs: {
          'radarr': _held(file: false),
          'radarr-4k': null,
          'radarr-3': _held(id: 3),
        },
        failing: {'radarr-3'},
      );
      expect(await _files(container, movie), isEmpty);
    },
  );

  group('a series', () {
    final series = buildSeries(id: 5, title: 'Cosmos Laundromat');
    const episode = (
      key: _series,
      season: 2,
      episode: 3,
      title: 'Cosmos Laundromat',
    );
    final records = [
      SonarrEpisode.fromJson({
        'id': 31,
        'seasonNumber': 2,
        'episodeNumber': 3,
        'title': 'The Second Cycle',
        'hasFile': true,
        'monitored': true,
        'episodeFileId': 400,
      }),
      SonarrEpisode.fromJson({
        'id': 32,
        'seasonNumber': 2,
        'episodeNumber': 4,
        'title': 'Tachyon',
        'hasFile': true,
        'monitored': true,
        'episodeFileId': 401,
      }),
    ];
    const file = SonarrEpisodeFile(
      id: 400,
      relativePath: 'Cosmos.Laundromat.S02E03.mkv',
      qualityName: 'WEBDL-720p',
      size: 800000000,
    );

    test("an episode's file, and the search for that episode", () async {
      final container = await _container(
        sonarrs: {'sonarr': series},
        episodes: records,
        files: {400: file},
      );
      final files = await _files(container, episode);
      expect(files, hasLength(1));
      expect(files.single.fileName, 'Cosmos.Laundromat.S02E03.mkv');
      expect(files.single.headline, startsWith('720p WEB'));
      expect(files.single.episode, isTrue);
      final target = files.single.target;
      expect(target.scope, ReleaseSearchScope.episode);
      expect(target.id, 31);
      expect(target.parentId, 5);
      expect(target.seasonNumber, 2);
      expect(target.instanceId, 'sonarr');
      expect(
        target.label,
        '${'Cosmos Laundromat'}\u00A0· ${formatEpisodeCode(2, 3)}',
      );
    });

    test('no file read yet for the episode: nothing, never a guess', () async {
      final container = await _container(
        sonarrs: {'sonarr': series},
        episodes: records,
        files: const {},
      );
      expect(await _files(container, episode), isEmpty);
    });

    test('an episode with no file on disk draws nothing', () async {
      final container = await _container(
        sonarrs: {'sonarr': series},
        episodes: [
          SonarrEpisode.fromJson({
            'id': 31,
            'seasonNumber': 2,
            'episodeNumber': 3,
            'title': 'The Second Cycle',
            'hasFile': false,
            'monitored': true,
          }),
        ],
        files: {400: file},
      );
      expect(await _files(container, episode), isEmpty);
    });

    test('a season, or the whole series, names no file', () async {
      final container = await _container(
        sonarrs: {'sonarr': series},
        episodes: records,
        files: {400: file},
      );
      expect(
        await _files(container, (
          key: _series,
          season: 2,
          episode: 0,
          title: 'Cosmos Laundromat',
        )),
        isEmpty,
      );
      expect(
        await _files(container, (
          key: _series,
          season: 0,
          episode: 0,
          title: 'Cosmos Laundromat',
        )),
        isEmpty,
      );
    });

    test('a Sonarr that does not track the series draws nothing', () async {
      final container = await _container(
        sonarrs: {'sonarr': null},
        episodes: records,
        files: {400: file},
      );
      expect(await _files(container, episode), isEmpty);
    });
  });
}
