/// Everyone's requests, narrowed by state and by person: the pills, the
/// sheets, `Clear`, the empty narrowed list, and the address the filters
/// live in (`/activity/requests?state=declined`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/widgets/media_value_sheet.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/domain/request_filters.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

const _second = ServiceInstance(
  id: 'seerr-2222222',
  service: ServiceKey.seerr,
  label: 'Anime',
  url: 'https://second.lan:5055',
  credential: 'key-2',
);

/// Seerr's own numbering: request 2 approved, 3 declined; media 3
/// processing, 5 available.
SeerrRequest _request(
  int id, {
  int status = 2,
  int media = 5,
  int user = 1,
  String name = 'Anna',
}) => SeerrRequest.fromJson({
  'id': id,
  'status': status,
  'type': 'movie',
  'createdAt': '2026-08-01T10:00:00.000Z',
  'media': {
    'id': id,
    'tmdbId': 100 + id,
    'mediaType': 'movie',
    'status': media,
    'title': 'Title $id',
  },
  'requestedBy': {'id': user, 'displayName': name},
}, numbering: SeerrNumbering.seerr);

/// Anna's two declined, Ben's one on its way and one on the server, and
/// Cara's, waiting: her request is a decision above the list, not in it.
List<SeerrRequest> _household() => [
  _request(1, status: 3, media: 1),
  _request(2, status: 3, media: 1),
  _request(3, media: 3, user: 2, name: 'Ben'),
  _request(4, media: 5, user: 2, name: 'Ben'),
  _request(5, status: 1, media: 2, user: 3, name: 'Cara'),
];

class _Seerr extends FakeSeerrService {
  _Seerr(this.requests);

  final List<SeerrRequest> requests;

  @override
  Future<List<SeerrRequest>> getRequestRows() async => requests;
}

Future<List<Override>> _overrides({
  required List<SeerrRequest> first,
  List<SeerrRequest>? second,
  bool names = true,
}) async => [
  ...await settingsScopeOverrides(
    configured: const [ServiceKey.seerr],
    customize: (settings) =>
        second == null ? settings : settings.copyWithInstance(_second),
  ),
  activityLivePollProvider.overrideWith((ref, tab) {}),
  seerrServiceProvider.overrideWith((ref) => _Seerr(first)),
  if (second != null)
    seerrServiceForProvider(_second.id).overrideWithValue(_Seerr(second)),
  // A requester's gate: no row names who asked.
  if (!names)
    roleGateOfProvider.overrideWith(
      (ref, id) => const RoleGate(audience: Audience.requester),
    ),
];

late GoRouter _router;

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  String location = '/activity/requests',
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/activity/requests',
        builder: (context, state) => ActivityPage(
          tab: ActivityTab.requests,
          requestsOf: state.uri.queryParameters['i'],
          requestFilters: RequestFilters.fromQuery(state.uri.queryParameters),
        ),
      ),
    ],
  );
  addTearDown(_router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pill(String label) =>
    find.widgetWithText(SelectionPill, label, skipOffstage: false);

bool _lit(WidgetTester tester, String label) =>
    tester.widget<SelectionPill>(_pill(label)).selected;

Finder _option(String label) => find.descendant(
  of: find.byType(MediaValueOptionRow),
  matching: find.text(label),
);

Future<void> _choose(WidgetTester tester, String pill, String option) async {
  await tester.tap(_pill(pill));
  await tester.pumpAndSettle();
  await tester.tap(_option(option));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no filter: every other request, the pills unlit, the '
      'figure the total', (tester) async {
    await _pump(tester, overrides: await _overrides(first: _household()));

    for (final n in [1, 2, 3, 4]) {
      expect(find.text('Title $n'), findsOneWidget);
    }
    expect(find.text('4 total'), findsOneWidget);
    expect(_lit(tester, 'Any state'), isFalse);
    expect(_lit(tester, 'Anyone'), isFalse);
    expect(_pill('Clear'), findsNothing);
  });

  testWidgets('the state sheet lists the groups the list holds, each with '
      'its count, and a pick narrows the rows and the figure', (tester) async {
    await _pump(tester, overrides: await _overrides(first: _household()));

    await tester.tap(_pill('Any state'));
    await tester.pumpAndSettle();
    expect(find.text('State'), findsOneWidget);
    expect(find.text('Currently Any state'), findsOneWidget);
    // Only what the list holds: nothing waiting, removed or blocked here.
    expect(_option('Any state'), findsOneWidget);
    expect(_option('On its way'), findsOneWidget);
    expect(_option('On the server'), findsOneWidget);
    expect(_option('Declined'), findsOneWidget);
    expect(_option('Waiting for approval'), findsNothing);
    expect(_option('Blocked'), findsNothing);
    expect(find.bySemanticsLabel('Declined, 2 requests'), findsOneWidget);

    await tester.tap(_option('Declined'));
    await tester.pumpAndSettle();

    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 2'), findsOneWidget);
    expect(find.text('Title 3'), findsNothing);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(_lit(tester, 'Declined'), isTrue);
    expect(_router.state.uri.toString(), '/activity/requests?state=declined');
  });

  testWidgets('the person sheet names who asked with their count; a pick '
      'narrows, and Clear lifts it', (tester) async {
    await _pump(tester, overrides: await _overrides(first: _household()));

    await tester.tap(_pill('Anyone'));
    await tester.pumpAndSettle();
    expect(find.text('Person'), findsOneWidget);
    expect(_option('Anna'), findsOneWidget);
    expect(_option('Ben'), findsOneWidget);
    // Cara's request waits above the list: she is not among its people.
    expect(_option('Cara'), findsNothing);
    await tester.tap(_option('Ben'));
    await tester.pumpAndSettle();

    expect(find.text('Title 3'), findsOneWidget);
    expect(find.text('Title 4'), findsOneWidget);
    expect(find.text('Title 1'), findsNothing);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(_lit(tester, 'Ben'), isTrue);

    await tester.tap(_pill('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('4 total'), findsOneWidget);
    expect(_pill('Clear'), findsNothing);
    expect(_router.state.uri.toString(), '/activity/requests');
  });

  testWidgets('each sheet counts under the other filter: with Ben chosen, '
      'the state sheet leaves out what he never asked for', (tester) async {
    await _pump(tester, overrides: await _overrides(first: _household()));

    await _choose(tester, 'Anyone', 'Ben');
    await tester.tap(_pill('Any state'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Any state, 2 requests'), findsOneWidget);
    expect(find.bySemanticsLabel('On its way, 1 request'), findsOneWidget);
    expect(find.bySemanticsLabel('On the server, 1 request'), findsOneWidget);
    // Anna's, not his.
    expect(_option('Declined'), findsNothing);

    await tester.tap(_option('On the server'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4'), findsOneWidget);
  });

  testWidgets('a state and a person together; the second pick keeps the '
      'first', (tester) async {
    await _pump(tester, overrides: await _overrides(first: _household()));

    await _choose(tester, 'Any state', 'On the server');
    await _choose(tester, 'Anyone', 'Ben');

    expect(find.text('Title 4'), findsOneWidget);
    expect(find.text('Title 3'), findsNothing);
    expect(find.text('1 of 4'), findsOneWidget);
    final query = _router.state.uri.queryParameters;
    expect(query['state'], 'on-the-server');
    expect(query['by'], endsWith(':2'));
  });

  testWidgets('a filter that leaves nothing keeps the pills and says so, '
      'never that nobody asked', (tester) async {
    await _pump(
      tester,
      overrides: await _overrides(first: _household()),
      location: '/activity/requests?state=blocked',
    );

    expect(find.text('No requests match these filters.'), findsOneWidget);
    expect(find.text('No requests yet'), findsNothing);
    expect(find.text('Title 1'), findsNothing);
    expect(find.text('0 of 4'), findsOneWidget);
    expect(_lit(tester, 'Blocked'), isTrue);
    expect(_pill('Anyone'), findsOneWidget);
    expect(_pill('Clear'), findsOneWidget);
  });

  testWidgets('the address draws what it says: ?state=declined lights the '
      'pill, keeps only the declined rows and counts them', (tester) async {
    await _pump(
      tester,
      overrides: await _overrides(first: _household()),
      location: '/activity/requests?state=declined',
    );

    expect(_lit(tester, 'Declined'), isTrue);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 2'), findsOneWidget);
    expect(find.text('Title 3'), findsNothing);
    expect(find.text('Title 4'), findsNothing);
    expect(find.text('2 of 4'), findsOneWidget);
  });

  testWidgets('a value the address does not know is no filter, and a '
      'person who is not in the list is dropped', (tester) async {
    await _pump(
      tester,
      overrides: await _overrides(first: _household()),
      location: '/activity/requests?state=bogus&by=seerr-gone:9',
    );

    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 4'), findsOneWidget);
    expect(find.text('4 total'), findsOneWidget);
    expect(_pill('Clear'), findsNothing);
  });

  testWidgets('where no row names who asked there is no Anyone, not a '
      'dimmed one', (tester) async {
    await _pump(
      tester,
      overrides: await _overrides(first: _household(), names: false),
    );

    expect(_pill('Any state'), findsOneWidget);
    expect(_pill('Anyone'), findsNothing);
    expect(find.text('Anyone'), findsNothing);
  });

  testWidgets('two Seerrs: a person carries the name of their Seerr', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: await _overrides(
        first: [_request(1, status: 3, media: 1)],
        second: [_request(1, status: 3, media: 1)],
      ),
    );

    await tester.tap(_pill('Anyone'));
    await tester.pumpAndSettle();

    final labels = [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(MediaValueOptionRow),
          matching: find.byType(Text),
        ),
      ))
        text.data,
    ];
    expect(
      labels.where((l) => l != null && l.startsWith('Anna\u00A0· ')),
      hasLength(2),
    );
    expect(labels.any((l) => l?.endsWith('Seerr Anime') ?? false), isTrue);
  });

  testWidgets('another filter starts again at the first page', (tester) async {
    final many = [
      for (var i = 0; i < 32; i++) _request(100 + i, media: 5),
      _request(1, status: 3, media: 1),
      _request(2, status: 3, media: 1),
    ];
    await _pump(tester, overrides: await _overrides(first: many));

    // 34 requests, 30 drawn: the rest are a tap away, and the tap is made.
    await tester.tap(find.text('Show 4 more'));
    await tester.pumpAndSettle();
    expect(find.text('Show 4 more'), findsNothing);

    // The 32 on the server: if the page had been kept, all would be drawn.
    await _choose(tester, 'Any state', 'On the server');
    expect(find.text('Show 2 more'), findsOneWidget);
  });
}
