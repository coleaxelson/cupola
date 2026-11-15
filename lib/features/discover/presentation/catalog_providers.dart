import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

// The atrium's reads. Each throws when Seerr did not answer or answered with
// a failure, and none retries on its own (`noProviderRetry`): the atrium says
// what happened once, and Retry or a pull is the user's call.

/// Trending this week: the atrium's shelf, its door's artwork, and the
/// canary that says whether Seerr answered at all.
final atriumTrendingProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final page = await ref
      .watch(seerrServiceProvider)
      .getCatalogPage(const CatalogQuery.trending());
  return page.items;
}, retry: noProviderRetry);

/// The best you're missing: titles TMDB scores 7 or more over a hundred
/// votes, the most popular first, with what the server holds taken out.
///
/// No count beside it, ever: what is left after the subtraction is a page's
/// worth, not a figure about the catalogue (F-on-server).
final bestMissingProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  final numbering = await ref.watch(seerrNumberingProvider.future);
  final pages = await Future.wait([
    for (final kind in CatalogKind.values)
      service.getCatalogPage(CatalogQuery.all(kind).withRated(true)),
  ]);
  return interleave([
    for (final page in pages)
      page.items
          .where((item) => !seerrHolds(item.mediaInfo, numbering: numbering))
          .toList(growable: false),
  ]);
}, retry: noProviderRetry);

/// Coming soon: films and series not out yet, the two lists woven together.
/// No region is claimed; TMDB's dates are the world's.
final comingSoonProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  final pages = await Future.wait([
    for (final kind in CatalogKind.values)
      service.getCatalogPage(CatalogQuery.upcoming(kind)),
  ]);
  return interleave([for (final page in pages) page.items]);
}, retry: noProviderRetry);

/// What is coming out that nobody has asked for yet, the calendar's last
/// shelf: Coming soon without anything Seerr holds a record of (asked for,
/// on its way, on the server) and without anything whose day has come
/// (TMDB's upcoming lists keep a title a while after it opens). A removed
/// title can be asked for again, and stays.
final comingOutProvider = FutureProvider.autoDispose<List<MediaPreview>>((
  ref,
) async {
  final numbering = await ref.watch(seerrNumberingProvider.future);
  final soon = await ref.watch(comingSoonProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  bool asked(MediaPreview item) {
    final code = intOrNull(item.mediaInfo?['status']);
    if (code == null) return false;
    return switch (SeerrMediaAvailability.fromCode(
      code,
      numbering: numbering,
    )) {
      SeerrMediaAvailability.unknown || SeerrMediaAvailability.deleted => false,
      _ => true,
    };
  }

  return [
    for (final item in soon)
      if (!asked(item) &&
          (arrCalendarDate(item.releaseDate)?.isAfter(today) ?? false))
        item,
  ];
}, retry: noProviderRetry);

/// The genres of one kind, each with a few backdrops to light its tile.
final catalogGenresProvider =
    FutureProvider.family<List<SeerrGenre>, CatalogKind>((ref, kind) {
      final service = ref.watch(seerrServiceProvider);
      return kind == CatalogKind.movie
          ? service.getMovieGenres()
          : service.getTvGenres();
    }, retry: noProviderRetry);

/// Someone behind a trending title: who directed or created it, or who leads
/// its cast.
typedef CatalogPerson = ({
  int id,
  String name,
  String? profilePath,
  String role,
  String title,
});

/// The faces on the atrium's People door: who leads the cast of the first
/// trending title, and who directed or created it, those with a photo, three
/// at most.
///
/// One read, of the one title, where the index reads ten: a door is a glance,
/// and three faces from one title say what is behind it as well as ten.
final atriumFacesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final first = (await ref.watch(atriumTrendingProvider.future)).firstOrNull;
  if (first == null) return const [];
  final service = ref.watch(seerrServiceProvider);
  final detail = first.mediaType == 'tv'
      ? await service.getTv(first.id)
      : await service.getMovie(first.id);
  final credits = detail['credits'];
  final cast = credits is Map ? credits['cast'] : null;
  final crew = credits is Map ? credits['crew'] : null;
  final people = [
    if (cast is List) ...cast.take(4),
    if (crew is List)
      ...crew.where((member) => member is Map && member['job'] == 'Director'),
    if (detail['createdBy'] case final List creators) ...creators,
  ];
  return <String>{
    for (final person in people)
      if (person is Map)
        if (person['profilePath'] case final String path when path.isNotEmpty)
          path,
  }.take(3).toList(growable: false);
}, retry: noProviderRetry);

/// How many trending titles the People index reads the credits of.
const int _peopleTitles = 10;

/// The people behind this week's trending titles: for each, who directed it
/// (who created it, for a series) and the first two names of its cast, once
/// each, in the order the titles trend.
///
/// Seerr has no list of popular people (lab, 06/10: no `/person/popular`,
/// and TMDB's trending no longer carries people), so the index is built from
/// the titles that are. One read per title, ten at most, made only when the
/// index opens.
final trendingPeopleProvider = FutureProvider.autoDispose<List<CatalogPerson>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  final titles = (await ref.watch(
    atriumTrendingProvider.future,
  )).take(_peopleTitles).toList(growable: false);
  final details = await Future.wait([
    for (final title in titles)
      (title.mediaType == 'tv'
              ? service.getTv(title.id)
              : service.getMovie(title.id))
          .then<Map<String, dynamic>?>((value) => value)
          // One title Seerr could not read costs its people, not the index.
          .catchError((Object _) => null),
  ]);
  if (titles.isNotEmpty && details.every((detail) => detail == null)) {
    throw StateError('Seerr gave none of the trending titles');
  }

  final seen = <int>{};
  final people = <CatalogPerson>[];
  void add(Object? raw, String role, String title) {
    if (raw is! Map) return;
    final id = intOrNull(raw['id']);
    final name = raw['name'];
    if (id == null || name is! String || name.isEmpty || !seen.add(id)) {
      return;
    }
    final profile = raw['profilePath'];
    people.add((
      id: id,
      name: name,
      profilePath: profile is String && profile.isNotEmpty ? profile : null,
      role: role,
      title: title,
    ));
  }

  for (var i = 0; i < titles.length; i++) {
    final detail = details[i];
    if (detail == null) continue;
    final title = titles[i].title;
    final credits = detail['credits'];
    final crew = credits is Map ? credits['crew'] : null;
    final cast = credits is Map ? credits['cast'] : null;
    if (titles[i].mediaType == 'tv') {
      final creators = detail['createdBy'];
      if (creators is List) {
        for (final creator in creators.take(1)) {
          add(creator, 'Created', title);
        }
      }
    } else if (crew is List) {
      for (final member in crew) {
        if (member is Map && member['job'] == 'Director') {
          add(member, 'Director', title);
          break;
        }
      }
    }
    if (cast is List) {
      for (final member in cast.take(2)) {
        add(member, 'Cast', title);
      }
    }
  }
  return people;
}, retry: noProviderRetry);

/// [lists] woven one title from each in turn, a title that appears twice
/// kept where it first came.
List<MediaPreview> interleave(List<List<MediaPreview>> lists) {
  final seen = <String>{};
  final woven = <MediaPreview>[];
  final longest = lists.fold<int>(
    0,
    (max, list) => list.length > max ? list.length : max,
  );
  for (var i = 0; i < longest; i++) {
    for (final list in lists) {
      if (i >= list.length) continue;
      final item = list[i];
      if (seen.add('${item.mediaType}:${item.id}')) woven.add(item);
    }
  }
  return woven;
}

/// "Hide what I have": one choice for the whole catalogue and the atrium,
/// kept across launches (one global switch, not one per shelf).
///
/// The person's own choice when there is one. Until they make it, the lens's
/// Seerr says: its `hideAvailable`, read from `/settings/public` the way
/// every other Seerr fact is ([seerrServerFactsProvider]). With no Seerr, or
/// one that did not answer, off. Resolved before anything is drawn from it,
/// so a shelf never shows posters and then takes some away.
final catalogHideOwnedProvider =
    AsyncNotifierProvider<CatalogHideOwnedNotifier, bool>(
      CatalogHideOwnedNotifier.new,
      retry: noProviderRetry,
    );

class CatalogHideOwnedNotifier extends AsyncNotifier<bool> {
  static const _key = 'catalog_hide_owned';

  /// What the person chose, or null if they never touched the switch: `set`
  /// always writes a value.
  bool? _stored() {
    // Guarded like the recent searches: a test or a screen built without
    // the preferences still draws, with the switch off.
    try {
      return ref.watch(sharedPreferencesProvider).getBool(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> build() async {
    final stored = _stored();
    if (stored != null) return stored;
    // Checked before watching, so a Seerr nobody set up is never read.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.seerr),
      ),
    );
    final lens = ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id;
    if (!configured || lens == null) return false;
    try {
      return (await ref.watch(
        seerrServerFactsProvider(lens).future,
      )).hideAvailable;
    } catch (_) {
      return false;
    }
  }

  void set(bool value) {
    state = AsyncData(value);
    try {
      ref.read(sharedPreferencesProvider).setBool(_key, value);
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}

/// How many titles a shelf with the switch on tries to keep.
const atriumShelfFill = 12;

/// What the atrium's filtered shelves do to a page of titles: nothing with
/// the switch off, otherwise take off what the server holds. Resolved from
/// the switch and Seerr's numbering together, so a shelf waits for both.
final atriumShelfKeeperProvider =
    FutureProvider<List<MediaPreview> Function(List<MediaPreview>)>((
      ref,
    ) async {
      final hide = await ref.watch(catalogHideOwnedProvider.future);
      if (!hide) return (List<MediaPreview> items) => items;
      // A numbering that did not come is no reason to lose the shelves:
      // without it the standard codes apply, as on the catalogue page.
      final numbering = await ref
          .watch(seerrNumberingProvider.future)
          .catchError((_) => null);
      return (List<MediaPreview> items) => [
        for (final item in items)
          if (!seerrHolds(item.mediaInfo, numbering: numbering)) item,
      ];
    }, retry: noProviderRetry);

/// Trending this week as the atrium's shelf draws it. With the switch off,
/// [atriumTrendingProvider] whole. On, without what the server holds, and
/// if fewer than [atriumShelfFill] are left, the second page read once to
/// fill it: never a third. Trending itself stays whole: it is the canary,
/// the doors' artwork and People's faces.
final atriumTrendingShelfProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final keep = await ref.watch(atriumShelfKeeperProvider.future);
  final first = await ref.watch(atriumTrendingProvider.future);
  final kept = keep(first);
  if (identical(kept, first) || kept.length >= atriumShelfFill) return kept;
  try {
    final more = await ref
        .watch(seerrServiceProvider)
        .getCatalogPage(const CatalogQuery.trending(), page: 2);
    // Trending moves between the two reads: a title already there is not
    // listed again.
    final seen = {for (final item in kept) '${item.mediaType}:${item.id}'};
    return [
      ...kept,
      for (final item in keep(more.items))
        if (seen.add('${item.mediaType}:${item.id}')) item,
    ];
  } catch (_) {
    // The second page is only a refill: what the first gave stands.
    return kept;
  }
}, retry: noProviderRetry);

/// Coming soon as the atrium's shelf draws it: the switch's filter over
/// [comingSoonProvider], with no refill.
final atriumComingSoonShelfProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final keep = await ref.watch(atriumShelfKeeperProvider.future);
  return keep(await ref.watch(comingSoonProvider.future));
}, retry: noProviderRetry);
