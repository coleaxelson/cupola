/// What the selection bar asks before it acts on several artists: the Monitor
/// sheet, the Profile sheet, the removal's confirmation, and the words each
/// of them and the failures are written in.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_bulk.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/music/presentation/lidarr_bulk.dart';

import '../../../test_helpers/fake_services.dart';

LidarrArtist _artist(
  int id,
  String name, {
  bool monitored = true,
  String? newItems = 'all',
  int? quality = 1,
  int? metadata = 1,
  int? size = 1024 * 1024 * 1024,
}) => LidarrArtist(
  id: id,
  artistName: name,
  foreignArtistId: 'mb-$id',
  status: 'continuing',
  monitored: monitored,
  images: const [],
  genres: const [],
  monitorNewItems: newItems,
  qualityProfileId: quality,
  metadataProfileId: metadata,
  statistics: size == null ? null : {'sizeOnDisk': size},
);

final _three = [
  _artist(1, 'Bill Evans'),
  _artist(2, 'Brian Eno'),
  _artist(3, 'Miles Davis'),
];

/// What three artists of a gibibyte each take, as the app writes a size.
final _threeGb = formatBytes(3 * 1024 * 1024 * 1024);

const _options = LidarrAddOptions(
  folders: [LidarrRootFolder(path: '/music')],
  qualityProfiles: [(id: 1, name: 'Lossless'), (id: 2, name: 'Any')],
  metadataProfiles: [
    LidarrMetadataProfile(
      id: 1,
      name: 'Standard',
      allowedPrimaryTypes: ['Album', 'EP'],
    ),
    LidarrMetadataProfile(id: 2, name: 'None'),
  ],
);

/// What a Lidarr is asked to do, recorded.
class _Lidarr extends FakeLidarrService {
  final edits = <(List<int>, LidarrArtistEdit)>[];
  final removed = <(List<int>, bool, bool)>[];
  final searched = <List<int>>[];

  @override
  Future<LidarrBulkResult> updateArtistsInBulk(
    List<int> artistIds,
    LidarrArtistEdit edit,
  ) async {
    edits.add((artistIds, edit));
    return LidarrBulkResult(done: artistIds);
  }

  @override
  Future<LidarrBulkResult> removeArtistsInBulk(
    List<int> artistIds, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    removed.add((artistIds, deleteFiles, addImportListExclusion));
    return LidarrBulkResult(done: artistIds);
  }

  @override
  Future<LidarrBulkResult> searchArtistsInBulk(List<int> artistIds) async {
    searched.add(artistIds);
    return LidarrBulkResult(
      done: [
        for (final id in artistIds)
          if (id != 2) id,
      ],
      refused: {
        for (final id in artistIds)
          if (id == 2)
            id: DioException(
              requestOptions: RequestOptions(path: '/api/v1/command'),
              response: Response(
                requestOptions: RequestOptions(path: '/api/v1/command'),
                statusCode: 400,
                data: {'message': 'The folder is not reachable'},
              ),
              type: DioExceptionType.badResponse,
            ),
      },
    );
  }
}

/// The actions of [lidarrBulk] over [artists], each behind a button that runs
/// what it asks and keeps the job it came back with.
class _Host extends ConsumerStatefulWidget {
  const _Host(this.artists);

  final List<LidarrArtist> artists;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  final jobs = <String, MediaBulkJob<LidarrArtist>?>{};
  MediaBulkOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final bulk = lidarrBulk(ref: ref, instanceId: 'lidarr-one', name: 'Lidarr');
    return Scaffold(
      body: Column(
        children: [
          for (final action in bulk.actions)
            TextButton(
              onPressed: () async {
                final job = await action.prepare(context, widget.artists);
                jobs[action.label] = job;
                if (job != null) {
                  final result = await job.run(widget.artists);
                  setState(() => outcome = result);
                }
              },
              child: Text('Run ${action.label}'),
            ),
          Text(
            outcome == null
                ? 'nothing yet'
                : 'done ${outcome!.done} refused '
                      '${[for (final f in outcome!.failures) f.line]}',
          ),
        ],
      ),
    );
  }
}

Future<_Lidarr> _pump(
  WidgetTester tester, {
  List<LidarrArtist>? artists,
  LidarrAddOptions options = _options,
  bool optionsFail = false,
}) async {
  final lidarr = _Lidarr();
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lidarrServiceForProvider.overrideWith((ref, id) => lidarr),
        lidarrAddOptionsProvider.overrideWith(
          (ref, id) => optionsFail
              ? Future<LidarrAddOptions>.error(
                  DioException.connectionError(
                    requestOptions: RequestOptions(path: '/api/v1/rootfolder'),
                    reason: 'Connection refused',
                  ),
                )
              : Future.value(options),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: _Host(artists ?? _three),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lidarr;
}

void main() {
  group('the words', () {
    test('the artists a sheet is for, as it names them', () {
      expect(lidarrBulkNames([_artist(1, 'Bill Evans')]), 'Bill Evans');
      expect(
        lidarrBulkNames(_three.take(2).toList()),
        'Bill Evans and Brian Eno',
      );
      expect(lidarrBulkNames(_three), 'Bill Evans, Brian Eno and Miles Davis');
      expect(
        lidarrBulkNames([
          for (var i = 0; i < 14; i++)
            _artist(i, ['Bill Evans', 'Brian Eno'][i % 2]),
        ]),
        'Bill Evans, Brian Eno and 12 more',
      );
    });

    test('a refusal names the artist and keeps Lidarr’s own words', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
          statusCode: 400,
          data: [
            {
              'propertyName': 'RootFolderPath',
              'errorMessage': 'Folder /music/Miles Davis is not reachable',
            },
          ],
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        lidarrRefusalLine('Miles Davis', error, 'Lidarr'),
        'Lidarr refused Miles Davis: Folder /music/Miles Davis is not '
        'reachable.',
      );
    });

    test('a request nothing answered has no words of Lidarr’s, and says '
        'why in the house words', () {
      final line = lidarrRefusalLine(
        'Miles Davis',
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
          reason: 'Connection refused',
        ),
        'Lidarr',
      );

      expect(line, startsWith('Miles Davis: '));
      expect(line, contains('Lidarr'));
      expect(line, isNot(contains('refused Miles')));
    });
  });

  group('what the sheets start on', () {
    test('Monitor, when they agree on it, and when they are mixed', () {
      expect(lidarrBulkStartMonitored(_three), isTrue);
      expect(
        lidarrBulkStartMonitored([
          _artist(1, 'A', monitored: false),
          _artist(2, 'B', monitored: false),
        ]),
        isFalse,
      );
      expect(
        lidarrBulkStartMonitored([
          _artist(1, 'A', monitored: false),
          _artist(2, 'B'),
        ]),
        isTrue,
        reason: 'otherwise Monitor',
      );
    });

    test('Monitor new albums: what they all have, otherwise Leave as is', () {
      expect(lidarrBulkStartNewItems(_three), 'all');
      expect(
        lidarrBulkStartNewItems([
          _artist(1, 'A', newItems: 'none'),
          _artist(2, 'B', newItems: 'none'),
        ]),
        'none',
      );
      expect(
        lidarrBulkStartNewItems([
          _artist(1, 'A', newItems: 'none'),
          _artist(2, 'B'),
        ]),
        isNull,
      );
      expect(
        lidarrBulkStartNewItems([
          _artist(1, 'A', newItems: 'new'),
          _artist(2, 'B', newItems: 'new'),
        ]),
        isNull,
        reason: 'the sheet has no word for it',
      );
    });

    test('a profile: the one they all have, otherwise none', () {
      int? quality(LidarrArtist a) => a.qualityProfileId;
      expect(lidarrBulkSharedProfile(_three, quality), 1);
      expect(
        lidarrBulkSharedProfile([
          _artist(1, 'A'),
          _artist(2, 'B', quality: 2),
        ], quality),
        isNull,
      );
      expect(
        lidarrBulkSharedProfile([_artist(1, 'A', quality: null)], quality),
        isNull,
        reason: 'a record that does not say',
      );
    });
  });

  group('Monitor', () {
    testWidgets('is a sheet under the artists it is for, starting on what '
        'they have, and applies exactly what was chosen', (tester) async {
      final lidarr = await _pump(tester);

      await tester.tap(find.text('Run Monitor'));
      await tester.pumpAndSettle();

      expect(find.text('Monitor 3 artists'), findsOneWidget);
      expect(
        find.text('Bill Evans, Brian Eno and Miles Davis'),
        findsOneWidget,
      );
      expect(find.text('Monitor new albums'), findsOneWidget);
      for (final label in const [
        'Monitor',
        'Stop monitoring',
        'Leave as is',
        'All',
        'None',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Apply to 3 artists'), findsOneWidget);

      await tester.tap(find.text('Stop monitoring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to 3 artists'));
      await tester.pumpAndSettle();

      expect(lidarr.edits, hasLength(1));
      final (ids, edit) = lidarr.edits.single;
      expect(ids, [1, 2, 3]);
      expect(edit.monitored, isFalse);
      expect(edit.monitorNewItems, 'none');
      expect(edit.qualityProfileId, isNull);
      expect(find.textContaining('done [1, 2, 3]'), findsOneWidget);
    });

    testWidgets('left as it started, it sets Monitor and touches nothing '
        'else', (tester) async {
      final lidarr = await _pump(
        tester,
        artists: [
          _artist(1, 'A', newItems: 'none'),
          _artist(2, 'B', newItems: 'all'),
        ],
      );

      await tester.tap(find.text('Run Monitor'));
      await tester.pumpAndSettle();
      expect(find.text('Monitor 2 artists'), findsOneWidget);
      await tester.tap(find.text('Apply to 2 artists'));
      await tester.pumpAndSettle();

      final (_, edit) = lidarr.edits.single;
      expect(edit.monitored, isTrue);
      expect(
        edit.monitorNewItems,
        isNull,
        reason: 'they differ, so Leave as is',
      );
    });

    testWidgets('closing the sheet runs nothing', (tester) async {
      final lidarr = await _pump(tester);

      await tester.tap(find.text('Run Monitor'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      expect(lidarr.edits, isEmpty);
      expect(find.text('nothing yet'), findsOneWidget);
    });
  });

  group('Profile', () {
    testWidgets('lists the two rows on Leave as is, and Apply is not live '
        'until something changes', (tester) async {
      final lidarr = await _pump(
        tester,
        artists: [_artist(1, 'A', quality: 1), _artist(2, 'B', quality: 2)],
      );

      await tester.tap(find.text('Run Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profiles for 2 artists'), findsOneWidget);
      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('Metadata profile'), findsOneWidget);
      // They differ in quality, and say nothing of their metadata profile.
      expect(find.text('Leave as is'), findsWidgets);
      final apply = find.widgetWithText(FilledButton, 'Apply to 2 artists');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any'));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final (ids, edit) = lidarr.edits.single;
      expect(ids, [1, 2]);
      expect(edit.qualityProfileId, 2);
      expect(edit.metadataProfileId, isNull);
      expect(edit.monitored, isNull);
    });

    testWidgets('starts on the profile they all share, and choosing that '
        'one again changes nothing', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Run Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Lossless'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      final apply = find.widgetWithText(FilledButton, 'Apply to 3 artists');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lossless').last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    });

    testWidgets('a Lidarr that did not answer says so, with Retry, and '
        'offers nothing to apply', (tester) async {
      await _pump(tester, optionsFail: true);

      await tester.tap(find.text('Run Profile'));
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      final apply = find.widgetWithText(FilledButton, 'Apply to 3 artists');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    });
  });

  group('Search', () {
    testWidgets('runs at once for every artist, with nothing to ask, and '
        'reports the refusals by artist', (tester) async {
      final lidarr = await _pump(tester);

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();

      expect(lidarr.searched, [
        [1, 2, 3],
      ]);
      expect(
        find.textContaining('refused Brian Eno: The folder is not reachable.'),
        findsOneWidget,
      );
      expect(find.textContaining('done [1, 3]'), findsOneWidget);
    });
  });

  group('Remove', () {
    testWidgets('asks the question a single removal asks, for all of them, '
        'with the size they take', (tester) async {
      final lidarr = await _pump(tester);

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 3 artists from Lidarr?'), findsOneWidget);
      expect(
        find.text('Lidarr stops looking for their albums.'),
        findsOneWidget,
      );
      // Three artists of 1 GB each.
      expect(find.text('Also delete $_threeGb of files'), findsOneWidget);
      expect(find.text('Don’t add them again'), findsOneWidget);
      expect(find.text('Keep them'), findsOneWidget);
      expect(find.text('Remove 3 artists'), findsOneWidget);

      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(lidarr.removed, isEmpty);
    });

    testWidgets('the confirm names the whole of what is chosen, and sends '
        'it', (tester) async {
      final lidarr = await _pump(tester);

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete $_threeGb of files'));
      await tester.pump();
      expect(
        find.text('Remove 3 artists and delete $_threeGb'),
        findsOneWidget,
      );
      await tester.tap(find.text('Don’t add them again'));
      await tester.pump();
      expect(
        find.text('Remove 3 artists, delete $_threeGb, don’t add again'),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Remove 3 artists, delete $_threeGb, don’t add again'),
      );
      await tester.pumpAndSettle();

      expect(lidarr.removed, hasLength(1));
      final (ids, deleteFiles, exclude) = lidarr.removed.single;
      expect(ids, [1, 2, 3]);
      expect(deleteFiles, isTrue);
      expect(exclude, isTrue);
    });

    testWidgets('an artist with no size leaves the figure out rather than '
        'print a floor', (tester) async {
      await _pump(
        tester,
        artists: [_artist(1, 'A'), _artist(2, 'B', size: null)],
      );

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Also delete their files'), findsOneWidget);
      expect(find.textContaining('GB'), findsNothing);
      expect(find.text('Remove 2 artists'), findsOneWidget);
    });

    testWidgets('nothing on disk offers no files to delete', (tester) async {
      await _pump(
        tester,
        artists: [_artist(1, 'A', size: 0), _artist(2, 'B', size: 0)],
      );

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Also delete'), findsNothing);
      expect(find.text('Don’t add them again'), findsOneWidget);
      expect(
        find.textContaining('None of their albums are on your server yet'),
        findsOneWidget,
      );
    });

    testWidgets('the removal’s confirm is the app’s own: neutral, with a '
        'verb that names what happens', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Remove 3 artists'),
      );
      final colors = Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).colorScheme;
      final background = confirm.style?.backgroundColor?.resolve({});
      expect(background, anyOf(isNull, isNot(colors.error)));
    });
  });

  group('the bar', () {
    testWidgets('has the four actions, in the order of the board', (
      tester,
    ) async {
      await _pump(tester);

      final host = tester.element(find.byType(_Host));
      final container = ProviderScope.containerOf(host);
      expect(container, isNotNull);
      expect(find.text('Run Search'), findsOneWidget);
      final labels = [
        for (final text in tester.widgetList<Text>(find.textContaining('Run ')))
          text.data,
      ];
      expect(labels, [
        'Run Search',
        'Run Monitor',
        'Run Profile',
        'Run Remove',
      ]);
    });
  });
}
