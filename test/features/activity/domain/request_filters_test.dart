/// Everyone's requests, narrowed: the groups of states in the rows' words,
/// who asked, the counts and their floors, and the address they live in.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/request_filters.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

HouseholdRequest _row(
  int id,
  MyRequestStage stage, {
  String instance = 'a',
  int? user = 1,
  String name = 'Anna',
  String? connection,
  bool namesWho = true,
}) => (
  mine: MyRequest(
    request: SeerrRequest(
      id: id,
      status: RequestStatus.approved,
      type: 'movie',
      createdAt: '2026-08-01T10:00:00.000Z',
      requestedBy: user == null
          ? null
          : RequestedBy(id: user, displayName: name),
    ),
    stage: stage,
  ),
  instanceId: instance,
  connection: connection,
  namesWho: namesWho,
);

void main() {
  group('RequestStateGroup', () {
    test('every stage is in exactly one group, in the rows\' words', () {
      for (final stage in MyRequestStage.values) {
        expect(
          RequestStateGroup.values.where((g) => g.stages.contains(stage)),
          hasLength(1),
          reason: '$stage',
        );
      }
      expect(
        RequestStateGroup.of(MyRequestStage.downloading).label,
        'On its way',
      );
      expect(
        RequestStateGroup.of(MyRequestStage.finishing).label,
        'On its way',
      );
      expect(RequestStateGroup.of(MyRequestStage.onItsWay).label, 'On its way');
      expect(
        RequestStateGroup.of(MyRequestStage.waiting).label,
        'Waiting for approval',
      );
      expect(
        RequestStateGroup.of(MyRequestStage.readyToWatch).label,
        'On the server',
      );
      expect(
        RequestStateGroup.of(MyRequestStage.onTheServer).label,
        'On the server',
      );
      expect(RequestStateGroup.declined.label, 'Declined');
      expect(RequestStateGroup.didNotGoThrough.label, "Didn't go through");
      expect(RequestStateGroup.removed.label, 'Removed from the server');
      expect(RequestStateGroup.blocked.label, 'Blocked');
    });

    test('a slug names one group and a word it does not know names none', () {
      for (final group in RequestStateGroup.values) {
        expect(RequestStateGroup.fromSlug(group.slug), group);
      }
      expect(
        RequestStateGroup.fromSlug('didnt-go-through'),
        RequestStateGroup.didNotGoThrough,
      );
      expect(RequestStateGroup.fromSlug('nonsense'), isNull);
      expect(RequestStateGroup.fromSlug(null), isNull);
    });
  });

  group('censusOf', () {
    final rows = [
      _row(1, MyRequestStage.declined, user: 1, name: 'Anna'),
      _row(2, MyRequestStage.declined, user: 2, name: 'Ben'),
      _row(3, MyRequestStage.downloading, user: 1, name: 'Anna'),
      _row(4, MyRequestStage.onItsWay, user: 1, name: 'Anna'),
      _row(5, MyRequestStage.readyToWatch, user: 2, name: 'Ben'),
      _row(6, MyRequestStage.onTheServer, user: 1, name: 'Anna'),
    ];

    test(
      'counts each group the rows hold, in the sheet\'s order, none empty',
      () {
        final census = censusOf(rows);
        expect(census.states.keys.toList(), [
          RequestStateGroup.onItsWay,
          RequestStateGroup.onTheServer,
          RequestStateGroup.declined,
        ]);
        expect(census.states[RequestStateGroup.onItsWay], 2);
        expect(census.states[RequestStateGroup.onTheServer], 2);
        expect(census.states[RequestStateGroup.declined], 2);
        expect(census.states.containsKey(RequestStateGroup.waiting), isFalse);
      },
    );

    test('waiting appears only when the list holds waiting requests', () {
      expect(censusOf([_row(1, MyRequestStage.waiting)]).states.keys, [
        RequestStateGroup.waiting,
      ]);
      expect(
        censusOf(rows).states.containsKey(RequestStateGroup.waiting),
        isFalse,
      );
    });

    test('counts people by Seerr and user, the one with most first', () {
      final people = censusOf(rows).people;
      expect(
        [for (final p in people) (p.label, p.count)],
        [('Anna', 4), ('Ben', 2)],
      );
      expect(people.first.key, const RequestPersonKey('a', 1));
    });

    test('the same user id on two Seerrs is two people, each with its '
        'connection\'s name', () {
      final census = censusOf([
        _row(1, MyRequestStage.declined, instance: 'a', connection: 'Seerr'),
        _row(
          2,
          MyRequestStage.declined,
          instance: 'b',
          connection: 'Seerr Anime',
        ),
      ]);
      expect(
        [for (final p in census.people) p.label],
        ['Anna\u00A0· Seerr', 'Anna\u00A0· Seerr Anime'],
      );
    });

    test('rows that do not name who asked leave no one to filter by', () {
      final census = censusOf([
        _row(1, MyRequestStage.declined, namesWho: false),
        _row(2, MyRequestStage.declined, user: null),
      ]);
      expect(census.people, isEmpty);
      expect(census.namesPeople, isFalse);
      expect(census.states[RequestStateGroup.declined], 2);
    });
  });

  group('RequestFilters', () {
    final rows = [
      _row(1, MyRequestStage.declined, user: 1),
      _row(2, MyRequestStage.declined, user: 2, name: 'Ben'),
      _row(3, MyRequestStage.downloading, user: 1),
      _row(4, MyRequestStage.declined, instance: 'b', user: 1),
    ];

    List<int> ids(RequestFilters f) => [
      for (final row in f.narrow(rows)) row.mine.request.id,
    ];

    test('none keeps every row, a state keeps its group, a person its '
        'requests, both the rows that are both', () {
      expect(ids(RequestFilters.none), [1, 2, 3, 4]);
      expect(ids(const RequestFilters(state: RequestStateGroup.declined)), [
        1,
        2,
        4,
      ]);
      expect(ids(const RequestFilters(person: RequestPersonKey('a', 1))), [
        1,
        3,
      ]);
      expect(
        ids(
          const RequestFilters(
            state: RequestStateGroup.declined,
            person: RequestPersonKey('a', 1),
          ),
        ),
        [1],
      );
    });

    test('the address round-trips, and a value it does not know is no '
        'filter', () {
      const filters = RequestFilters(
        state: RequestStateGroup.didNotGoThrough,
        person: RequestPersonKey('seerr-2222222', 7),
      );
      expect(filters.query, {
        'state': 'didnt-go-through',
        'by': 'seerr-2222222:7',
      });
      expect(RequestFilters.fromQuery(filters.query), filters);
      expect(RequestFilters.none.query, isEmpty);
      expect(
        RequestFilters.fromQuery({'state': 'x', 'by': 'nope'}),
        RequestFilters.none,
      );
      expect(RequestFilters.fromQuery({'by': 'a:b'}), RequestFilters.none);
      expect(RequestFilters.fromQuery({'by': ':3'}), RequestFilters.none);
    });

    test('a person the list does not hold is dropped, a state stays', () {
      final census = censusOf(rows);
      const gone = RequestFilters(
        state: RequestStateGroup.removed,
        person: RequestPersonKey('a', 99),
      );
      expect(
        gone.within(census),
        const RequestFilters(state: RequestStateGroup.removed),
      );
      const here = RequestFilters(person: RequestPersonKey('a', 2));
      expect(here.within(census), here);
    });
  });

  group('counts', () {
    test('a floor reads `41+`, and is said `41 or more requests`', () {
      expect(requestCountLabel(41, whole: true), '41');
      expect(requestCountLabel(41, whole: false), '41+');
      expect(requestCountSpoken(41, whole: true), '41 requests');
      expect(requestCountSpoken(1, whole: true), '1 request');
      expect(requestCountSpoken(41, whole: false), '41 or more requests');
    });

    test('the section\'s figure is the total until something narrows, then '
        '`41 of 348`, with the floors', () {
      String figure({
        bool totalFloor = false,
        int shown = 41,
        bool narrowed = true,
        bool whole = true,
      }) => requestsFigure(
        listed: 348,
        listedFloor: totalFloor,
        shown: shown,
        narrowed: narrowed,
        whole: whole,
      );
      expect(figure(narrowed: false), '348 total');
      expect(figure(narrowed: false, totalFloor: true), '348+ total');
      expect(figure(), '41 of 348');
      expect(figure(whole: false), '41+ of 348');
      expect(figure(totalFloor: true), '41 of 348+');
      expect(figure(totalFloor: true, whole: false), '41+ of 348+');
      expect(figure(shown: 0), '0 of 348');
    });
  });

  group('facetsOf', () {
    final rows = [
      _row(1, MyRequestStage.declined, user: 1, name: 'Anna'),
      _row(2, MyRequestStage.declined, user: 1, name: 'Anna'),
      _row(3, MyRequestStage.downloading, user: 1, name: 'Anna'),
      _row(4, MyRequestStage.declined, user: 2, name: 'Ben'),
      _row(5, MyRequestStage.readyToWatch, user: 2, name: 'Ben'),
    ];

    Map<String, int> states(RequestFacets f) => {
      for (final e in f.states.entries) e.key.label: e.value,
    };
    Map<String, int> people(RequestFacets f) => {
      for (final e in f.people) e.label: e.count,
    };

    test('with nothing chosen, each option counts the whole list', () {
      final f = facetsOf(rows, RequestFilters.none);
      expect(f.anyState, 5);
      expect(f.anyone, 5);
      expect(states(f), {'On its way': 1, 'On the server': 1, 'Declined': 3});
      expect(people(f), {'Anna': 3, 'Ben': 2});
    });

    test('each sheet counts under the other filter, so the count picked is '
        'the count the heading shows', () {
      const declined = RequestFilters(state: RequestStateGroup.declined);
      final byState = facetsOf(rows, declined);
      // The people sheet, over the declined rows.
      expect(people(byState), {'Anna': 2, 'Ben': 1});
      expect(byState.anyone, 3);
      // The state sheet is not narrowed by the state itself.
      expect(byState.anyState, 5);

      const ben = RequestFilters(person: RequestPersonKey('a', 2));
      final byPerson = facetsOf(rows, ben);
      expect(states(byPerson), {'On the server': 1, 'Declined': 1});
      expect(byPerson.anyState, 2);
      expect(byPerson.anyone, 5);

      for (final person in byState.people) {
        expect(
          RequestFilters(
            state: RequestStateGroup.declined,
            person: person.key,
          ).narrow(rows),
          hasLength(person.count),
        );
      }
    });

    test('an option with nothing under the other filter is left out, except '
        'the chosen one, which keeps its zero', () {
      const chosen = RequestFilters(
        state: RequestStateGroup.onItsWay,
        person: RequestPersonKey('a', 2),
      );
      final f = facetsOf(rows, chosen);
      // Under Ben: nothing is on its way, and the chosen group stays.
      expect(states(f), {'On its way': 0, 'On the server': 1, 'Declined': 1});
      // Under the state: only Anna has one, and the chosen Ben stays.
      expect(people(f), {'Anna': 1, 'Ben': 0});

      final none = facetsOf(
        rows,
        const RequestFilters(state: RequestStateGroup.blocked),
      );
      expect(people(none), isEmpty);
      expect(none.anyone, 0);
    });
  });
}
