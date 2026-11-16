/// The sheet that adds an artist to Lidarr: its defaults, its pickers, its
/// states, and what it posts.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';
import 'package:cupola/features/music/presentation/lidarr_add_artist_sheet.dart';
import 'package:cupola/features/music/presentation/lidarr_add_options_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

const _home = ServiceInstance(
  id: 'lidarr',
  service: ServiceKey.lidarr,
  url: 'https://lidarr.test',
  credential: 'key',
);

const _away = ServiceInstance(
  id: 'lidarr-away',
  service: ServiceKey.lidarr,
  label: 'Away',
  url: 'https://lidarr-away.test',
  credential: 'key',
);

String _name(ServiceInstance connection) =>
    connection.label.isEmpty ? 'Lidarr' : 'Lidarr · ${connection.label}';

LidarrArtist _elbow({String overview = 'English rock band formed in 1997.'}) =>
    LidarrArtist.fromJson({
      'artistName': 'Elbow',
      'foreignArtistId': 'mbid-elbow',
      'artistType': 'Group',
      'disambiguation': 'Bury, England',
      'overview': overview,
      'images': const <Object?>[],
    });

const _standard = LidarrMetadataProfile(
  id: 1,
  name: 'Standard',
  allowedPrimaryTypes: ['Album', 'EP'],
);

const _singles = LidarrMetadataProfile(
  id: 2,
  name: 'Singles',
  allowedPrimaryTypes: ['Single'],
);

LidarrAddOptions _options({
  List<LidarrRootFolder>? folders,
  List<LidarrMetadataProfile> metadata = const [_standard],
}) => LidarrAddOptions(
  folders:
      folders ??
      const [
        LidarrRootFolder(
          path: '/music',
          freeSpace: 2308974418944,
          defaultQualityProfileId: 2,
          defaultMetadataProfileId: 1,
          defaultMonitor: null,
          defaultNewItemMonitor: 'all',
        ),
      ],
  qualityProfiles: const [(id: 1, name: 'Lossless'), (id: 2, name: 'Any')],
  metadataProfiles: metadata,
);

/// A phone, 390 wide and tall enough that the whole sheet is in reach: the
/// sheet rises from the bottom.
void _phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The sheet's own Lidarr: the one the add is posted to.
class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final client = FakeApiClient()
    ..postResponseData = {
      'id': 12,
      'artistName': 'Elbow',
      'foreignArtistId': 'mbid-elbow',
      'status': 'continuing',
      'monitored': true,
      'images': const <Object?>[],
    };

  /// The connections the options were asked of.
  final asked = <String>[];

  LidarrAddedArtist? added;
  var closed = false;

  Future<void> open({
    LidarrAddOptions? options,
    Future<LidarrAddOptions>? pending,
    Object? error,
    List<ServiceInstance> connections = const [_home],
    LidarrArtist? artist,
    bool settle = true,
  }) async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => connections.fold(
        settings,
        (settings, connection) => settings.copyWithInstance(connection),
      ),
    );
    _phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          lidarrAddOptionsProvider.overrideWith((ref, id) {
            asked.add(id);
            if (error != null) return Future.error(error);
            return pending ?? Future.value(options ?? _options());
          }),
          lidarrServiceForProvider.overrideWith(
            (ref, id) => LidarrService(client),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    added = await showLidarrAddArtistSheet(
                      context,
                      artist: artist ?? _elbow(),
                      connections: connections,
                      name: _name,
                    );
                    closed = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    // A skeleton shimmers for ever: a test of one pumps by hand.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> tapAdd() async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  Map<dynamic, dynamic> get posted => client.lastPostData as Map;
}

/// The switch of the row that carries [label].
Switch _switchOf(WidgetTester tester, String label) => tester.widget<Switch>(
  find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(Switch),
  ),
);

Finder get _addButton => find.byType(FilledButton);

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _addButton, matching: find.byType(Text)))
    .data!;

void main() {
  group('the header', () {
    testWidgets('names the artist, who they are and what is written of them', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open();

      expect(find.text('Elbow'), findsOneWidget);
      expect(find.text('Group\u00A0· Bury, England'), findsOneWidget);
      // No photo: their initial on the disc.
      expect(find.text('E'), findsOneWidget);
      expect(find.text('English rock band formed in 1997.'), findsOneWidget);
    });

    testWidgets('clamps a long overview to two lines', (tester) async {
      final harness = _Harness(tester);
      await harness.open(artist: _elbow(overview: 'A long history. ' * 40));

      final overview = tester.widget<Text>(
        find.textContaining('A long history.'),
      );
      expect(overview.maxLines, 2);
      expect(overview.overflow, TextOverflow.ellipsis);
    });
  });

  group('the folder’s defaults', () {
    testWidgets('fill the rows and say so once', (tester) async {
      final harness = _Harness(tester);
      await harness.open(
        options: _options(
          folders: const [
            LidarrRootFolder(
              path: '/music',
              freeSpace: 2308974418944,
              defaultQualityProfileId: 2,
              defaultMetadataProfileId: 1,
              defaultNewItemMonitor: 'none',
            ),
          ],
        ),
      );

      expect(find.text('/music'), findsOneWidget);
      expect(find.text('2.1\u00A0TB free'), findsOneWidget);
      // Quality profile 2 is the folder's, not the first of the list.
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Lossless'), findsNothing);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Albums and EPs'), findsOneWidget);
      expect(find.text('All albums'), findsOneWidget);
      expect(find.text('Every album, out and to come'), findsOneWidget);
      expect(_switchOf(tester, 'Monitor new albums').value, isFalse);
      expect(_switchOf(tester, 'Search when added').value, isTrue);
      expect(
        find.text('The folder’s defaults, as set in Lidarr.'),
        findsOneWidget,
      );
    });

    testWidgets('are posted as they stand', (tester) async {
      final harness = _Harness(tester);
      await harness.open(
        options: _options(
          folders: const [
            LidarrRootFolder(
              path: '/music',
              defaultQualityProfileId: 2,
              defaultMetadataProfileId: 1,
              defaultNewItemMonitor: 'none',
            ),
          ],
        ),
      );

      await harness.tapAdd();

      expect(harness.client.lastPostPath, '/api/v1/artist');
      expect(harness.posted['artistName'], 'Elbow');
      expect(harness.posted['foreignArtistId'], 'mbid-elbow');
      expect(harness.posted['qualityProfileId'], 2);
      expect(harness.posted['metadataProfileId'], 1);
      expect(harness.posted['rootFolderPath'], '/music');
      expect(harness.posted['monitored'], isTrue);
      expect(harness.posted['monitorNewItems'], 'none');
      expect(harness.posted['addOptions'], {
        'monitor': 'all',
        'searchForMissingAlbums': true,
      });
      // The sheet resolves to the artist as Lidarr now holds it.
      expect(harness.closed, isTrue);
      expect(harness.added!.artist.id, 12);
      expect(harness.added!.connection.id, 'lidarr');
    });

    testWidgets('a folder with none starts on the first profiles and stays '
        'quiet about it', (tester) async {
      final harness = _Harness(tester);
      await harness.open(
        options: _options(folders: const [LidarrRootFolder(path: '/music')]),
      );

      expect(find.text('Lossless'), findsOneWidget);
      expect(find.textContaining('defaults, as set in Lidarr'), findsNothing);
    });

    testWidgets('stop being claimed once the person changes a row', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open();
      expect(find.textContaining('defaults, as set in Lidarr'), findsOneWidget);

      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lossless'));
      await tester.pumpAndSettle();

      expect(find.text('Lossless'), findsOneWidget);
      expect(find.textContaining('defaults, as set in Lidarr'), findsNothing);
    });

    testWidgets('a second folder brings its own', (tester) async {
      final harness = _Harness(tester);
      await harness.open(
        options: _options(
          folders: const [
            LidarrRootFolder(
              path: '/music',
              defaultQualityProfileId: 2,
              defaultMetadataProfileId: 1,
            ),
            LidarrRootFolder(
              path: '/classical',
              freeSpace: 500000000000,
              defaultQualityProfileId: 1,
              defaultMetadataProfileId: 1,
            ),
          ],
        ),
      );
      expect(find.text('Any'), findsOneWidget);

      await tester.tap(find.text('Folder'));
      await tester.pumpAndSettle();
      // Each folder with the room it has left.
      expect(find.textContaining('GB free'), findsOneWidget);
      await tester.tap(find.text('/classical'));
      await tester.pumpAndSettle();

      expect(find.text('/classical'), findsOneWidget);
      expect(find.text('Lossless'), findsOneWidget);

      await harness.tapAdd();
      expect(harness.posted['rootFolderPath'], '/classical');
      expect(harness.posted['qualityProfileId'], 1);
    });
  });

  group('Monitor', () {
    testWidgets('offers the seven choices, each with what it means', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open();

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();

      for (final label in [
        'All albums',
        'Future albums',
        'Missing albums',
        'Existing albums',
        'First album',
        'Latest album',
        'None',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Only albums not out yet'), findsOneWidget);
      expect(
        find.text('Lists the artist and looks for nothing'),
        findsOneWidget,
      );

      await tester.tap(find.text('Latest album'));
      await tester.pumpAndSettle();
      await harness.tapAdd();

      expect(harness.posted['addOptions'], {
        'monitor': 'latest',
        'searchForMissingAlbums': true,
      });
      expect(harness.posted['monitored'], isTrue);
    });

    testWidgets('None dims Search when added and says what it needs', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open();

      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MediaValueOptionRow),
          matching: find.text('None'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Needs albums to monitor'), findsOneWidget);
      final search = _switchOf(tester, 'Search when added');
      expect(search.value, isFalse);
      expect(search.onChanged, isNull);

      await harness.tapAdd();
      expect(harness.posted['monitored'], isFalse);
      expect(harness.posted['addOptions'], {
        'monitor': 'none',
        'searchForMissingAlbums': false,
      });
    });
  });

  group('the button', () {
    testWidgets('says Add and search while Search when added is on, and '
        'names Lidarr when it is off', (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      expect(_buttonLabel(tester), 'Add and search');

      await tester.tap(find.text('Search when added'));
      await tester.pumpAndSettle();

      expect(_switchOf(tester, 'Search when added').value, isFalse);
      expect(_buttonLabel(tester), 'Add to Lidarr');

      await harness.tapAdd();
      expect(harness.posted['addOptions'], {
        'monitor': 'all',
        'searchForMissingAlbums': false,
      });
    });

    testWidgets('names the connection it adds to when it does not search', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open(connections: const [_home, _away]);

      await tester.tap(find.text('Lidarr · Away'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search when added'));
      await tester.pumpAndSettle();

      expect(_buttonLabel(tester), 'Add to Lidarr · Away');
    });
  });

  group('choices', () {
    testWidgets('a row with one thing to choose is not a picker', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open();

      for (final label in ['Folder', 'Metadata profile']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        // No picker rose: it would carry its row's title and "Currently".
        expect(find.textContaining('Currently'), findsNothing, reason: label);
      }
    });

    testWidgets('the metadata profile is a picker with what each keeps', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open(
        options: _options(metadata: const [_standard, _singles]),
      );

      await tester.tap(find.text('Metadata profile'));
      await tester.pumpAndSettle();
      expect(find.text('Currently Standard'), findsOneWidget);
      // The profile's name, and the one type it keeps under it.
      expect(find.text('Singles'), findsNWidgets(2));
      await tester.tap(find.text('Singles').first);
      await tester.pumpAndSettle();

      // The name, and what it keeps under it.
      expect(find.text('Singles'), findsNWidgets(2));
      await harness.tapAdd();
      expect(harness.posted['metadataProfileId'], 2);
    });

    testWidgets('the connections are pills only when there are two', (
      tester,
    ) async {
      final one = _Harness(tester);
      await one.open();
      expect(find.byType(SelectionPill), findsNothing);
      expect(find.text('Instance'), findsNothing);
    });

    testWidgets('two connections: the pills, and the options of the one '
        'chosen', (tester) async {
      final harness = _Harness(tester);
      await harness.open(connections: const [_home, _away]);

      expect(find.text('Instance'), findsOneWidget);
      expect(find.byType(SelectionPill), findsNWidgets(2));
      expect(harness.asked, ['lidarr']);

      await tester.tap(find.text('Lidarr · Away'));
      await tester.pumpAndSettle();

      expect(harness.asked, ['lidarr', 'lidarr-away']);
      await harness.tapAdd();
      expect(harness.added!.connection.id, 'lidarr-away');
    });
  });

  group('while the options are read', () {
    testWidgets('the rows are skeletons and nothing can be added', (
      tester,
    ) async {
      final harness = _Harness(tester);
      final pending = Completer<LidarrAddOptions>();
      await harness.open(pending: pending.future, settle: false);

      expect(find.byType(ShimmerPlaceholder), findsWidgets);
      expect(find.text('Quality profile'), findsNothing);
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

      pending.complete(_options());
      await tester.pumpAndSettle();
      expect(find.text('Quality profile'), findsOneWidget);
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
    });
  });

  group('when the options cannot be read', () {
    testWidgets('Lidarr is named, Retry reads them again, and there is '
        'nothing to add yet', (tester) async {
      final harness = _Harness(tester);
      await harness.open(
        error: DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/rootfolder'),
          reason: 'down',
        ),
      );

      final failure = tester.widget<AppErrorState>(find.byType(AppErrorState));
      expect(failure.compact, isTrue);
      expect(failure.service, ServiceKey.lidarr);
      expect(failure.instanceId, 'lidarr');
      expect(find.textContaining('Lidarr'), findsWidgets);
      expect(find.text('Quality profile'), findsNothing);
      // A button that cannot work is not drawn.
      expect(_addButton, findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(harness.asked, ['lidarr', 'lidarr']);
    });

    testWidgets('a Lidarr with nothing to file under says so, what to do, '
        'and opens its settings', (tester) async {
      final harness = _Harness(tester);
      await harness.open(options: _options(folders: const []));

      expect(find.text('Lidarr has no root folder yet.'), findsOneWidget);
      expect(find.text('Add one in Lidarr, then come back.'), findsOneWidget);
      expect(find.text('Open in Lidarr'), findsOneWidget);
      expect(find.byType(ShelfOpenIn), findsOneWidget);
      expect(_addButton, findsNothing);
    });

    testWidgets('the same for a missing quality or metadata profile', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.open(options: _options(metadata: const []));

      expect(find.text('Lidarr has no metadata profile yet.'), findsOneWidget);
      expect(find.byType(ShelfOpenIn), findsOneWidget);
      expect(_addButton, findsNothing);
    });
  });

  group('when Lidarr refuses the add', () {
    testWidgets('the sheet stays, in Lidarr’s own words', (tester) async {
      final harness = _Harness(tester);
      harness.client.postException = DioException.badResponse(
        statusCode: 400,
        requestOptions: RequestOptions(path: '/api/v1/artist'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/artist'),
          statusCode: 400,
          data: [
            {'errorMessage': 'This artist has already been added'},
          ],
        ),
      );
      await harness.open();

      await harness.tapAdd();

      expect(harness.closed, isFalse);
      expect(find.text('Could not add Elbow to Lidarr.'), findsOneWidget);
      expect(find.text('This artist has already been added'), findsOneWidget);
      // Still there to try again.
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
    });

    testWidgets('a refusal says why in the classified words when Lidarr gave '
        'none', (tester) async {
      final harness = _Harness(tester);
      harness.client.postException = DioException.badResponse(
        statusCode: 401,
        requestOptions: RequestOptions(path: '/api/v1/artist'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/artist'),
          statusCode: 401,
        ),
      );
      await harness.open();

      await harness.tapAdd();

      expect(find.text('Could not add Elbow to Lidarr.'), findsOneWidget);
      expect(
        find.textContaining('Lidarr answered but refused the key'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing changed'), findsOneWidget);
    });
  });

  group('while the add is out', () {
    testWidgets('the button is busy and nothing closes the sheet', (
      tester,
    ) async {
      final slow = _Slow();
      final harness = _Harness(tester);
      slow.copyFrom(harness.client);
      final overrides = await settingsScopeOverrides(
        customize: (settings) => settings.copyWithInstance(_home),
      );
      LidarrAddedArtist? added;
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides,
            lidarrAddOptionsProvider.overrideWith(
              (ref, id) async => _options(),
            ),
            lidarrServiceForProvider.overrideWith(
              (ref, id) => LidarrService(slow),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => added = await showLidarrAddArtistSheet(
                    context,
                    artist: _elbow(),
                    connections: const [_home],
                    name: _name,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(_addButton);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );

      // A tap on the barrier and the system's back both bounce off.
      await tester.tapAt(const Offset(195, 20));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LidarrAddArtistSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LidarrAddArtistSheet), findsOneWidget);

      slow.release.complete();
      await tester.pumpAndSettle();

      expect(find.byType(LidarrAddArtistSheet), findsNothing);
      expect(added!.artist.id, 12);
    });

    testWidgets('an idle sheet closes by its Close button and returns '
        'nothing', (tester) async {
      final harness = _Harness(tester);
      await harness.open();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(LidarrAddArtistSheet), findsNothing);
      expect(harness.closed, isTrue);
      expect(harness.added, isNull);
      expect(harness.client.postCallCount, 0);
    });
  });
}

/// A Lidarr whose add waits to be let go.
class _Slow extends FakeApiClient {
  final release = Completer<void>();

  void copyFrom(FakeApiClient other) =>
      postResponseData = other.postResponseData;

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    await release.future;
    return super.post(
      path,
      data: data,
      queryParameters: queryParameters,
      receiveTimeout: receiveTimeout,
    );
  }
}
