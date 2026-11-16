import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// One of the household's requests that waits on nobody here, with the
/// Seerr it lives on: its id is per server, and so is its delete.
typedef HouseholdRequest = ({
  MyRequest mine,
  String instanceId,
  String? connection,

  /// Whether its row names who asked: where the connection sees everyone's
  /// requests, never to the requester.
  bool namesWho,
});

/// The states a request list is filtered by, in the words its rows say:
/// stages that read alike are one group.
enum RequestStateGroup {
  onItsWay('on-its-way', [
    MyRequestStage.downloading,
    MyRequestStage.finishing,
    MyRequestStage.onItsWay,
  ]),
  waiting('waiting', [MyRequestStage.waiting]),
  onTheServer('on-the-server', [
    MyRequestStage.readyToWatch,
    MyRequestStage.onTheServer,
  ]),
  declined('declined', [MyRequestStage.declined]),
  didNotGoThrough('didnt-go-through', [MyRequestStage.didNotGoThrough]),
  removed('removed', [MyRequestStage.removed]),
  blocked('blocked', [MyRequestStage.blocked]);

  const RequestStateGroup(this.slug, this.stages);

  /// What the address says: `?state=declined`.
  final String slug;
  final List<MyRequestStage> stages;

  /// The row's own word for the group.
  String get label => switch (this) {
    onItsWay => Lexicon.onItsWayState,
    waiting => StateWord.waitingForApproval.label,
    onTheServer => Lexicon.onTheServer,
    declined => Lexicon.declined,
    didNotGoThrough => Lexicon.requestDidNotGoThrough,
    removed => Lexicon.removedFromServer,
    blocked => Lexicon.blocked,
  };

  static RequestStateGroup of(MyRequestStage stage) =>
      values.firstWhere((group) => group.stages.contains(stage));

  /// The group an address names, or null for a word it does not know.
  static RequestStateGroup? fromSlug(String? slug) {
    for (final group in values) {
      if (group.slug == slug) return group;
    }
    return null;
  }
}

/// Who asked: a user of one Seerr, whose ids are per server.
@immutable
class RequestPersonKey {
  const RequestPersonKey(this.instanceId, this.userId);

  final String instanceId;
  final int userId;

  /// What the address says: `?by=<connection>:<user>`.
  String get slug => '$instanceId:$userId';

  /// The person an address names, or null for one it does not.
  static RequestPersonKey? fromSlug(String? slug) {
    if (slug == null) return null;
    final cut = slug.lastIndexOf(':');
    if (cut <= 0) return null;
    final id = int.tryParse(slug.substring(cut + 1));
    return id == null ? null : RequestPersonKey(slug.substring(0, cut), id);
  }

  @override
  bool operator ==(Object other) =>
      other is RequestPersonKey &&
      other.instanceId == instanceId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(instanceId, userId);
}

/// What narrows the household's requests: a state and a person, either
/// absent. Lives in the address, never remembered.
@immutable
class RequestFilters {
  const RequestFilters({this.state, this.person});

  static const none = RequestFilters();

  /// Reads the address's query. A value it does not know is no filter.
  factory RequestFilters.fromQuery(Map<String, String> query) => RequestFilters(
    state: RequestStateGroup.fromSlug(query['state']),
    person: RequestPersonKey.fromSlug(query['by']),
  );

  final RequestStateGroup? state;
  final RequestPersonKey? person;

  bool get isNarrowed => state != null || person != null;

  /// The query that says it, to go beside the address's other parameters.
  Map<String, String> get query => {'state': ?state?.slug, 'by': ?person?.slug};

  RequestFilters withState(RequestStateGroup? state) =>
      RequestFilters(state: state, person: person);

  RequestFilters withPerson(RequestPersonKey? person) =>
      RequestFilters(state: state, person: person);

  /// The filters the list can honour: a person it does not hold (a link
  /// outlives the people, and a connection that does not name who asked
  /// offers none) is no filter.
  RequestFilters within(RequestCensus census) =>
      person == null || census.people.any((entry) => entry.key == person)
      ? this
      : withPerson(null);

  @override
  bool operator ==(Object other) =>
      other is RequestFilters && other.state == state && other.person == person;

  @override
  int get hashCode => Object.hash(state, person);

  /// The rows these filters keep, in their order.
  List<HouseholdRequest> narrow(List<HouseholdRequest> rows) => isNarrowed
      ? [
          for (final row in rows)
            if ((state == null ||
                    RequestStateGroup.of(row.mine.stage) == state) &&
                (person == null || _keyOf(row) == person))
              row,
        ]
      : rows;
}

RequestPersonKey? _keyOf(HouseholdRequest row) {
  final id = row.mine.request.requestedBy?.id;
  return row.namesWho && id != null
      ? RequestPersonKey(row.instanceId, id)
      : null;
}

/// Who is in the list, and how many requests each state and each person has.
@immutable
class RequestCensus {
  const RequestCensus({required this.states, required this.people});

  /// The groups the rows hold, in the sheet's order; none with nothing in it.
  final Map<RequestStateGroup, int> states;

  /// The people the rows name, the one with most requests first.
  final List<({RequestPersonKey key, String label, int count})> people;

  /// Whether the list names who asked: the `Anyone` pill exists only then.
  bool get namesPeople => people.isNotEmpty;
}

/// Counts [rows]. A person's label is their name, with the Seerr's when the
/// list holds two.
RequestCensus censusOf(List<HouseholdRequest> rows) {
  final states = <RequestStateGroup, int>{};
  final counts = <RequestPersonKey, int>{};
  final labels = <RequestPersonKey, String>{};
  for (final row in rows) {
    final group = RequestStateGroup.of(row.mine.stage);
    states[group] = (states[group] ?? 0) + 1;
    final key = _keyOf(row);
    if (key == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    labels.putIfAbsent(key, () {
      final name = row.mine.request.requestedBy!.displayName;
      return switch (row.connection) {
        final connection? => '$name\u00A0· $connection',
        null => name,
      };
    });
  }
  return RequestCensus(
    states: {
      for (final group in RequestStateGroup.values)
        if (states.containsKey(group)) group: states[group]!,
    },
    people:
        [
          for (final entry in counts.entries)
            (key: entry.key, label: labels[entry.key]!, count: entry.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.label.compareTo(b.label);
        }),
  );
}

/// What each sheet offers, counted with the other filter applied: the
/// count of an option is the count the heading shows once it is picked
/// (`Declined 3` leads to `3 of 348`).
@immutable
class RequestFacets {
  const RequestFacets({
    required this.anyState,
    required this.states,
    required this.anyone,
    required this.people,
  });

  /// `Any state`: the rows under the chosen person, or all of them.
  final int anyState;

  /// The groups with rows under the chosen person, in the sheet's order,
  /// and the chosen one even when it has none.
  final Map<RequestStateGroup, int> states;

  /// `Anyone`: the rows under the chosen state, or all of them.
  final int anyone;

  /// The people with rows under the chosen state, the one with most first,
  /// and the chosen one even when they have none.
  final List<({RequestPersonKey key, String label, int count})> people;
}

/// Counts [rows] for each sheet, given what [filters] already choose.
RequestFacets facetsOf(List<HouseholdRequest> rows, RequestFilters filters) {
  final everyone = censusOf(rows);
  final underPerson = filters.withState(null).narrow(rows);
  final underState = filters.withPerson(null).narrow(rows);
  final states = censusOf(underPerson).states;
  final named = {
    for (final entry in censusOf(underState).people) entry.key: entry.count,
  };
  return RequestFacets(
    anyState: underPerson.length,
    states: {
      for (final group in RequestStateGroup.values)
        if ((states[group] ?? 0) > 0 || group == filters.state)
          group: states[group] ?? 0,
    },
    anyone: underState.length,
    people:
        [
          for (final entry in everyone.people)
            if ((named[entry.key] ?? 0) > 0 || entry.key == filters.person)
              (
                key: entry.key,
                label: entry.label,
                count: named[entry.key] ?? 0,
              ),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.label.compareTo(b.label);
        }),
  );
}

/// A count as the list says it: `41`, or `41+` where the rows are not whole.
String requestCountLabel(int count, {required bool whole}) =>
    '$count${whole ? '' : '+'}';

/// A count as a screen reader says it: `41 requests`, `41 or more requests`.
String requestCountSpoken(int count, {required bool whole}) {
  final noun = count == 1 && whole ? 'request' : 'requests';
  return whole ? '$count $noun' : '$count or more requests';
}

/// The section's figure. [listed] is the household's count less the requests
/// waiting above, and [listedFloor] says it is only what arrived. While
/// nothing narrows the list it reads `348 total` (`348+ total`); once
/// something does, `41 of 348`, where [shown] is the rows that are kept
/// (`41+ of 348` when the rows are not [whole]; the total keeps its own `+`).
String requestsFigure({
  required int listed,
  required bool listedFloor,
  required int shown,
  required bool narrowed,
  required bool whole,
}) {
  final total = '$listed${listedFloor ? '+' : ''}';
  if (!narrowed) return '$total total';
  return '${requestCountLabel(shown, whole: whole)} of $total';
}
