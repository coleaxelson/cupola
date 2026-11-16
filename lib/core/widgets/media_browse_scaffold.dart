import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/find_match.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/media_poster_caption.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/library_selection.dart';
import 'package:cupola/core/widgets/media_bulk.dart';
import 'package:cupola/core/widgets/media_find.dart';
import 'package:cupola/core/widgets/media_browse_index.dart';
import 'package:cupola/core/widgets/media_browse_wanted.dart';
import 'package:cupola/core/widgets/media_grid.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What the grid keys its artwork on: the address the connection is reached
/// at, its credential and that address's access
/// ([SettingsModel.artworkKeyOf]). The access is in the key so a changed
/// token rebuilds the posters with it at once, and the address so the route
/// moving does.
typedef SettingsSelector =
    (String, String, ConnectionAccess) Function(SettingsModel settings);
typedef MediaBrowseItemTap<T> =
    void Function(BuildContext context, T item, String heroTag);
typedef MediaBrowseTextExtractor<T> = String Function(T item);
typedef MediaBrowseRefreshCallback = void Function(WidgetRef ref);

enum MediaBrowseFilter {
  all,
  available,
  missing,

  /// A wall's own answer to what it is short of, in the place of [missing]
  /// (see [MediaBrowseWanted]). Never offered beside it.
  wanted,
  inQueue,

  /// On disk, but not at the quality the profile asks for. Its own chip rather
  /// than a shade of Missing: the file is there, so nothing is absent. What is
  /// outstanding is an upgrade, and the operator who wants one is not the
  /// operator hunting a gap.
  cutoffUnmet,

  /// Tracked by the service but not watched by it. Orthogonal to every other
  /// chip, and the only one that says nothing about the file.
  unmonitored,
}

/// What an empty grid says under a chip that hides every title.
@visibleForTesting
String mediaBrowseFilterEmptyTitle(MediaBrowseFilter filter) =>
    switch (filter) {
      MediaBrowseFilter.all => 'Nothing to show',
      MediaBrowseFilter.available => 'Nothing is available yet',
      MediaBrowseFilter.missing => 'Nothing is missing',
      MediaBrowseFilter.wanted => 'Nothing is wanted',
      MediaBrowseFilter.inQueue => 'Nothing is in the queue',
      MediaBrowseFilter.cutoffUnmet => 'Nothing is below its cutoff',
      MediaBrowseFilter.unmonitored => 'Everything is monitored',
    };

/// Which library chip a resolved status belongs under.
///
/// Three buckets rather than two predicates, and that is the whole point: a pair
/// of independent predicates is how [MediaAvailability.unknown] and
/// [MediaAvailability.deleted] came to match *neither* Available nor Missing, so
/// a freshly added Sonarr series (`sonarrSeriesAvailability` returns `unknown`
/// whenever the server omits `statistics`), was visible under `All` and under
/// nothing else. A bucket is exhaustive over [MediaAvailability] by
/// construction, so a state added later cannot silently fall out of the library.
enum MediaBrowseBucket {
  /// Something is on disk: Available, Upgrade available, Partial.
  onDisk,

  /// Something the user can act on is not on disk.
  gap,

  /// Not out yet: the one state that deliberately answers to no chip but
  /// `All`, because an unreleased title is not a gap anyone can close.
  unreleased,
}

/// The bucket for [status], exhaustively.
///
/// A null status means the screen supplied no extractor, or the feature could
/// not resolve one: it lands in [MediaBrowseBucket.gap], which is what the
/// pre-refactor `_browseStatusFor` did with its terminal `_ => missing` case.
MediaBrowseBucket mediaBrowseBucketOf(MediaStatusInfo? status) {
  if (status == null) return MediaBrowseBucket.gap;

  return switch (status.availability) {
    MediaAvailability.available ||
    MediaAvailability.upgradable ||
    // Partial counts as on disk: part of it genuinely is, and the page shows
    // the count. It is deliberately not also a gap: a title cannot answer to
    // two chips or the two lists stop being a partition.
    MediaAvailability.partial => MediaBrowseBucket.onDisk,
    MediaAvailability.missing ||
    // Not tracked, gone from the service, or never reported: nothing is on
    // disk, so the operator finds it where they look for what is not there.
    MediaAvailability.notTracked ||
    MediaAvailability.deleted ||
    MediaAvailability.unknown => MediaBrowseBucket.gap,
    MediaAvailability.unavailable => MediaBrowseBucket.unreleased,
  };
}

/// Whether an item with [status] is shown under [filter].
///
/// Pure and top-level so the partition can be asserted rung by rung instead of
/// only through a pumped scaffold.
///
/// [belowCutoff] is the one fact the status cannot carry: whether *this* item
/// is in the service's own `wanted/cutoff` set. It arrives as a plain bool so
/// this function stays a function of its arguments: the caller owns the id
/// set and the lookup, and a screen with no cutoff source passes `false` and
/// does not offer the chip at all. [isWanted] is the same kind of fact for the
/// Wanted chip: whether the item is in the wall's own wanted set.
bool mediaBrowseFilterMatches(
  MediaBrowseFilter filter,
  MediaStatusInfo? status, {
  bool belowCutoff = false,
  bool isWanted = false,
}) {
  return switch (filter) {
    MediaBrowseFilter.all => true,
    MediaBrowseFilter.available =>
      mediaBrowseBucketOf(status) == MediaBrowseBucket.onDisk,
    MediaBrowseFilter.missing =>
      mediaBrowseBucketOf(status) == MediaBrowseBucket.gap,
    // The service's own list, not a reading of the status: it is what the
    // chip exists for (see `MediaBrowseWanted`).
    MediaBrowseFilter.wanted => isWanted,
    // Orthogonal to the buckets on purpose: what is moving is a different
    // question from what is on disk, and a downloading title belongs in both
    // In queue and Missing.
    MediaBrowseFilter.inQueue => status?.isInPipeline ?? false,
    // Also orthogonal: a below-cutoff file is on disk, so it answers to
    // Available too. Neither of these two may join the bucket partition or the
    // two exhaustive lists stop being lists.
    MediaBrowseFilter.cutoffUnmet => belowCutoff,
    MediaBrowseFilter.unmonitored => status?.unmonitored ?? false,
  };
}

/// What the browse wall draws an item as.
///
/// Not a style flag: a poster and an artist portrait are different claims. A
/// 2:3 crop of a band photograph is a worse lie than a circle: it invents a
/// poster that does not exist and crops a face to do it, so Lidarr's wall is
/// circular and says so here rather than tuning a radius at the call site.
enum MediaBrowseTileShape {
  /// The 2:3 poster, with the status dot painted over its lower-left corner.
  poster,

  /// The circular portrait, centred, with the status carried by the caption
  /// instead of a dot: a circle has no corner to put one in, and `LidarrArtists`
  /// draws the completeness in words (`6 albums · complete`).
  circle,
}

/// One order the browse wall can be read in.
///
/// A sort is a label, a comparator and a claim about headings, not an enum the
/// scaffold switches on, because the scaffold is generic over `T` and cannot
/// read a release date or a file size. Each service declares the orders its own
/// model can actually answer, which is also why there is no dead `Size` entry on
/// a screen whose model has no size.
@immutable
class MediaBrowseSort<T> {
  /// What the control reads after `Sort · `.
  final String label;

  final Comparator<T> compare;

  /// Whether the A–Z letter headings belong over this order.
  ///
  /// They belong over exactly one: an alphabetical wall is what a letter
  /// heading describes. Over a date-added order the same headings are a lie
  /// told once per section: `LidarrArtists` says so in the board itself
  /// ("letter headings appear only in Name A–Z sort") and `RadarrLibrary`,
  /// sorted by date added, draws none.
  final bool lettered;

  const MediaBrowseSort({
    required this.label,
    required this.compare,
    this.lettered = false,
  });

  /// Newest first, and anything the service did not date goes last.
  ///
  /// The arrs hand `added` back as an ISO string. Parsing it rather than
  /// comparing the strings is not pedantry: a server that answers a local
  /// offset sorts wrongly under a string compare, and a row the server never
  /// dated sorts *first* under one, the loudest position in the list for the
  /// item we know least about.
  factory MediaBrowseSort.dateAdded(String? Function(T item) addedOf) {
    return MediaBrowseSort<T>(
      label: 'Date added',
      compare: (left, right) {
        final leftAt = DateTime.tryParse(addedOf(left) ?? '');
        final rightAt = DateTime.tryParse(addedOf(right) ?? '');
        if (leftAt == null && rightAt == null) return 0;
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        return rightAt.compareTo(leftAt);
      },
    );
  }

  /// Largest first. A zero is an honest answer here (nothing on disk), so it
  /// sorts to the bottom rather than being held out.
  factory MediaBrowseSort.size(int Function(T item) bytesOf) {
    return MediaBrowseSort<T>(
      label: 'Size',
      compare: (left, right) => bytesOf(right).compareTo(bytesOf(left)),
    );
  }

  /// Newest first; an unknown year (the arrs write 0) sorts last rather than
  /// claiming to be the oldest title in the library.
  factory MediaBrowseSort.year(int Function(T item) yearOf) {
    return MediaBrowseSort<T>(
      label: 'Year',
      compare: (left, right) {
        final leftYear = yearOf(left);
        final rightYear = yearOf(right);
        if (leftYear == 0 && rightYear == 0) return 0;
        if (leftYear == 0) return 1;
        if (rightYear == 0) return -1;
        return rightYear.compareTo(leftYear);
      },
    );
  }
}

/// The fewest columns the browse wall drops to, matching the three the phone
/// boards draw. Below this the floor stops being the binding constraint: two
/// posters across a 390pt phone would be enormous, not better.
const int _minBrowseColumns = 3;

/// A sort key whose first character is a Latin letter, and therefore gets its
/// own section heading rather than landing under `#`.
///
/// Top level because the section pass runs it once per library item: built
/// inline, the pattern was recompiled for every row on every rebuild.
final RegExp _sectionLetter = RegExp(r'^[A-Z]$');

/// Shared scaffold for media library browse screens.
///
/// Provides the shared AppBar, search bar, navigation refresh listener,
/// library refresh flow, and search results layout used by the Movies, Series,
/// Music and Authors screens.
///
/// What a screen cannot answer it leaves out rather than faking: no
/// [cutoffUnmetIds] draws no Cutoff unmet chip, and no [statusExtractor] draws
/// none of the chips that put a question to a status.
///
class MediaBrowseScaffold<T> extends ConsumerStatefulWidget {
  final String title;
  final String searchHint;
  final String activityRoute;
  final NavigationSection navigationSection;
  final String serviceName;

  /// Whose library this is. When set, a load that failed with nothing to keep
  /// is that service's `ServiceOfflineState.failure`: the cause in plain
  /// words, its address and a way to its connection form, rather than the
  /// generic error state, which can name no address and no form.
  final ServiceKey? service;
  final Color? accentColor;
  final String heroTagPrefix;

  /// The whole library, which **must fail when the fetch fails**.
  ///
  /// The wall has nothing but this list to show, so a provider that swallows
  /// its error into `[]` reaches the wall as an empty library and it says "No
  /// items found" about a server that never answered. Thrown, it lands on
  /// `AsyncValueWidget`'s fault states with a Retry.
  final FutureProvider<List<T>> libraryProvider;
  final StateProvider<String> searchQueryProvider;

  /// What the field finds, and where it looks. See [MediaFind].
  final MediaFind find;
  final MediaBrowseTextExtractor<T> titleExtractor;
  final MediaBrowseTextExtractor<T> subtitleExtractor;
  final MediaBrowseTextExtractor<T>? sortTitleExtractor;
  final List<dynamic>? Function(T item) imagesExtractor;
  final int Function(T item) idExtractor;
  final StatusExtractor<T>? statusExtractor;
  final MediaBrowseRefreshCallback? onRefresh;
  final SettingsSelector settingsSelector;
  final MediaBrowseItemTap<T> onItemTap;
  final List<String>? coverTypes;
  final bool showAppBar;
  final double topPadding;

  /// Optional KPI peek rail shown under the search bar (hidden while searching).
  final Widget? kpiPeek;

  /// Orders this service can offer beyond the built-in Title A–Z, which is
  /// always first and always the default.
  final List<MediaBrowseSort<T>> sorts;

  /// What a tile is drawn as: see [MediaBrowseTileShape].
  final MediaBrowseTileShape tileShape;

  /// The glyph on a poster tile with no artwork: the film's clapper unless the
  /// library holds something else (a series passes the television).
  final IconData posterFallbackIcon;

  /// The glyph over an empty library: the film strip unless the library holds
  /// something else (Readarr's passes the book).
  final IconData emptyIcon;

  /// A line under `Your <service> library is empty`, for a library the app
  /// cannot fill itself: where its items come from. Null says nothing more.
  /// Only the empty library reads it; a chip that hides every title does not.
  final String? emptyMessage;

  /// The ids the service reported under `wanted/cutoff`, or null when this
  /// screen has no cutoff source.
  ///
  /// Null and empty are different answers and the chip strip treats them so: an
  /// empty set means the service answered "none below cutoff" and the chip is
  /// offered reading zero, while null means nothing was asked and the chip is
  /// not drawn at all. A chip that cannot be told apart from an unasked
  /// question is a claim the screen cannot honour.
  final Set<int>? cutoffUnmetIds;

  /// The wall's own Wanted chip, which takes the Missing chip's place, or null
  /// for a wall that keeps Missing. See [MediaBrowseWanted].
  final MediaBrowseWanted? wanted;

  /// What this library can do to several of its titles at once, or null for a
  /// wall that cannot: it then offers no `Select` and no long press into
  /// selection, rather than a control with nothing behind it. See [MediaBulk].
  final MediaBulk<T>? bulk;

  const MediaBrowseScaffold({
    super.key,
    required this.title,
    required this.searchHint,
    required this.activityRoute,
    required this.navigationSection,
    required this.serviceName,
    this.service,
    this.accentColor,
    required this.heroTagPrefix,
    required this.libraryProvider,
    required this.searchQueryProvider,
    required this.find,
    required this.titleExtractor,
    required this.subtitleExtractor,
    this.sortTitleExtractor,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    this.onRefresh,
    required this.settingsSelector,
    required this.onItemTap,
    this.coverTypes,
    this.showAppBar = true,
    this.topPadding = 0,
    this.kpiPeek,
    this.sorts = const [],
    this.cutoffUnmetIds,
    this.wanted,
    this.bulk,
    this.tileShape = MediaBrowseTileShape.poster,
    this.posterFallbackIcon = Icons.movie_outlined,
    this.emptyIcon = Icons.video_library_outlined,
    this.emptyMessage,
  });

  @override
  ConsumerState<MediaBrowseScaffold<T>> createState() =>
      _MediaBrowseScaffoldState<T>();
}

class _MediaBrowseScaffoldState<T>
    extends ConsumerState<MediaBrowseScaffold<T>> {
  MediaBrowseFilter _selectedFilter = MediaBrowseFilter.all;

  /// Index into [_sortOptions]. Zero (Title A–Z) is the default order on
  /// every service, which is also the only order the wall had before.
  int _sortIndex = 0;

  /// The library list the cached order was computed from, and that order.
  ///
  /// The comparator does not read [_selectedFilter], so the sort is invariant
  /// across a chip tap and across every other rebuild of this element, of
  /// which the soft keyboard alone produces one per frame. [FutureProvider]
  /// hands back the same `List` instance until it is invalidated, so identity
  /// is a sound key; the filter itself still runs on every build.
  ///
  /// It is *not* invariant across a sort change, so the chosen order is part of
  /// the key too: without it, picking a new sort would hand back the old one.
  List<T>? _sortedSource;
  List<T>? _sorted;
  int? _sortedUnder;

  /// The text in the field as typed, trimmed, with no debounce: what a
  /// [MediaFind] library scope answers from. The query provider holds the same
  /// text once typing has paused, which is what the service scope asks for.
  String _liveText = '';

  /// The outer scroll position of the wall's `NestedScrollView`: the header
  /// (field, peek, chips). How much of it is still showing is what a jump to a
  /// letter has to count in (see [_jumpToLetter]).
  final ScrollController _outer = ScrollController();

  /// The window's selection controller, when there is a shell to coordinate
  /// with: the one the navigation bar and a service's band listen to.
  LibrarySelectionController? _scope;

  /// Whether the wall is in selection mode: see [MediaBrowseScaffold.bulk].
  var _selecting = false;

  /// The ids selected, whether or not the current chip shows them.
  final Set<int> _selected = <int>{};

  /// The action in flight, by its place on the bar; -1 for a retry from the
  /// notice. While one is out the others are inert and Back is not heard.
  int? _running;

  /// Which connection the wall is showing, counted: it moves when the wall is
  /// handed another connection's titles. An action that began under an earlier
  /// count paints nothing when it ends, since its ids and its words are
  /// another connection's.
  int _connection = 0;

  /// What the last action left undone for some titles, over the chips.
  _BulkNotice<T>? _notice;

  /// Why the last action did nothing at all: the selection stays under it.
  ({String message, Object error, VoidCallback retry})? _failure;

  /// Where the keys of selection mode (Esc, Cmd or Ctrl A) are heard.
  final FocusNode _keys = FocusNode(debugLabel: 'library selection');

  @override
  void initState() {
    super.initState();
    _liveText = ref.read(widget.searchQueryProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LibrarySelectionScope.maybeOf(context);
    if (!identical(scope, _scope)) {
      if (_selecting) _scope?.release(this);
      _scope = scope;
      if (_selecting) scope?.claim(this, onCancel: _cancelSelecting);
    }
  }

  @override
  void dispose() {
    _scope?.release(this);
    _keys.dispose();
    _outer.dispose();
    super.dispose();
  }

  /// Takes [text] as what the field holds. An emptied field ends the search,
  /// and the next one starts in the library.
  void _setLiveText(String text) {
    if (text == _liveText) return;
    // A word typed from outside (a link that opens the wall on a search) is
    // the end of selecting: the wall is showing something else now.
    if (text.isNotEmpty && _selecting && _running == null) _endSelecting();
    setState(() => _liveText = text);
    if (text.isEmpty) {
      final scope = widget.find.scopeProvider;
      if (scope != null) {
        ref.read(scope.notifier).state = MediaFindScope.library;
      }
    }
  }

  void _selectScope(
    StateProvider<MediaFindScope> provider,
    MediaFindScope scope,
  ) {
    // The service asks about the text as it is now, not as it was 400ms ago.
    if (scope == MediaFindScope.service) {
      ref.read(widget.searchQueryProvider.notifier).state = _liveText;
    }
    ref.read(provider.notifier).state = scope;
  }

  @override
  void didUpdateWidget(MediaBrowseScaffold<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No cache reset on a new closure. The four screens that use this widget
    // pass extractors and sort comparators that read only the item's own fields
    // and capture nothing, so a rebuild that re-creates them computes the same
    // order. The cache is keyed on the library list and the chosen order (see
    // `_sortedItems`), and a rebuild that keeps both reuses the sort; before
    // this, every parent rebuild re-sorted the whole library.
    // A service that offered five orders and now offers two must not stay
    // parked on an index that no longer exists.
    if (_sortIndex >= _sortOptions.length) {
      _sortIndex = 0;
    }
    // Likewise a chip the screen no longer offers.
    if (_selectedFilter == MediaBrowseFilter.wanted && widget.wanted == null) {
      _selectedFilter = MediaBrowseFilter.all;
    }
    // The ids are one connection's: a selection that outlives the lens would
    // name other titles, and Remove would take them from the wrong server. It
    // ends as it does on leaving the tab, and what it left (a notice, a
    // failure whose retry carries the old ids) goes with it.
    if (widget.bulk != null &&
        oldWidget.bulk != null &&
        widget.bulk!.instanceId != oldWidget.bulk!.instanceId) {
      _connection++;
      _running = null;
      if (_selecting) {
        _selecting = false;
        _scope?.release(this);
      }
      _selected.clear();
      _notice = null;
      _failure = null;
    }
    // A wall that can no longer do anything to its titles does not select.
    if (widget.bulk == null) {
      if (_selecting) {
        _selecting = false;
        _selected.clear();
        _scope?.release(this);
      }
      _notice = null;
      _failure = null;
    }
  }

  // === Selection ============================================================

  /// Enters selection mode, with [id] selected when a long press began it.
  void _beginSelecting({int? id}) {
    if (widget.bulk == null || _selecting) return;
    if (id != null) HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selected.clear();
      if (id != null) _selected.add(id);
      _failure = null;
    });
    _scope?.claim(this, onCancel: _cancelSelecting);
    // The keys of selection are heard where the focus is: put it in the wall,
    // unless a control in it already holds it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selecting && !_keys.hasFocus) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null || !_keys.descendants.contains(focus)) {
          _keys.requestFocus();
        }
      }
    });
  }

  /// Leaves selection mode and forgets what was selected.
  void _endSelecting() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
      _failure = null;
    });
    _scope?.release(this);
  }

  /// Cancel, Back and Esc. Not while a write is out: it would answer to
  /// nobody, and the titles would change under a wall that said it had stopped.
  void _cancelSelecting() {
    if (_running != null) return;
    _endSelecting();
  }

  void _toggle(int id) {
    if (_running != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      _failure = null;
    });
  }

  /// `Select all` takes what the chip and sort show; `Deselect all` lets go of
  /// every title, shown or not.
  void _toggleAll(List<T> items, {required bool deselect}) {
    if (_running != null) return;
    setState(() {
      if (deselect) {
        _selected.clear();
      } else {
        for (final item in _filteredItems(items)) {
          _selected.add(widget.idExtractor(item));
        }
      }
      _failure = null;
    });
  }

  /// The selected titles, in the wall's order. Ids the library no longer
  /// holds (a title removed since) are not titles.
  List<T> _chosen(List<T> items) => [
    for (final item in _sortedItems(items))
      if (_selected.contains(widget.idExtractor(item))) item,
  ];

  /// What the header says: how many are selected, how many the chip shows,
  /// how many of the selected it hides, and whether all that is shown is
  /// selected.
  ({int selected, int shown, int hidden, bool all}) _selectionFacts(
    List<T> items,
  ) {
    final shown = {
      for (final item in _filteredItems(items)) widget.idExtractor(item),
    };
    final held = {for (final item in items) widget.idExtractor(item)};
    final selected = _selected.where(held.contains).length;
    final shownSelected = _selected.where(shown.contains).length;
    return (
      selected: selected,
      shown: shown.length,
      hidden: selected - shownSelected,
      all: shown.isNotEmpty && shownSelected == shown.length,
    );
  }

  /// What the selection header clears at the top: nothing under the wall's own
  /// bar; the tab row a desktop window keeps as the service's header; and the
  /// status bar alone where the service's band and tab bar have stepped aside.
  double _selectionTopInset(BuildContext context) {
    if (widget.showAppBar) return 0;
    if (AppBreakpoints.isDesktopShell(context)) return _chromeInset(context);
    return MediaQuery.paddingOf(context).top;
  }

  /// Whether the navigation bar is at the foot of the window: the phone
  /// layout, where the selection bar takes its place. The rail and the
  /// desktop shell have none.
  bool _hasNavBar(BuildContext context) =>
      !AppBreakpoints.isDesktopShell(context) &&
      MediaQuery.sizeOf(context).width < AppBreakpoints.touchRail;

  /// The room a wall keeps at its foot while selecting: the navigation bar's
  /// is already kept on a phone, and the other layouts keep the selection
  /// bar's own.
  double _selectionClearance(BuildContext context) =>
      _selecting && !_hasNavBar(context)
      ? FloatingNavBarMetrics.barHeightFor(context) + _railBarGap
      : 0;

  /// How far the selection bar floats above the foot of the list on a layout
  /// with no navigation bar.
  static const double _railBarGap = AppSpacing.xl;

  /// Taps on an action with nothing selected.
  void _toastNone(BuildContext context) {
    final hint = widget.bulk!.noneHint;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    // On a phone the shell's Scaffold already lifts a toast over its bottom
    // slot, which is where the selection bar is; elsewhere it is lifted here.
    messenger.showSnackBar(
      SnackBar(
        content: Text(hint),
        margin: _hasNavBar(context)
            ? null
            : EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                FloatingNavBarMetrics.barHeightFor(context) +
                    _railBarGap +
                    AppSpacing.md,
              ),
      ),
    );
  }

  /// Taps on an action that takes only what the chip shows, when the chip
  /// shows none of the selection.
  void _toastHidden(BuildContext context) {
    final bulk = widget.bulk!;
    final chip = _filterLabel(_selectedFilter, widget.wanted?.label);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('None of the selected ${bulk.plural} show under $chip'),
        margin: _hasNavBar(context)
            ? null
            : EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                FloatingNavBarMetrics.barHeightFor(context) +
                    _railBarGap +
                    AppSpacing.md,
              ),
      ),
    );
  }

  Future<void> _tapAction(int index, List<T> items) async {
    final bulk = widget.bulk;
    if (bulk == null || _running != null) return;
    final action = bulk.actions[index];
    final selected = _chosen(items);
    if (selected.isEmpty) {
      _toastNone(context);
      return;
    }
    // An action that takes only what the chip shows leaves the rest selected.
    final shown = {
      for (final item in _filteredItems(items)) widget.idExtractor(item),
    };
    final chosen = action.shownOnly
        ? [
            for (final item in selected)
              if (shown.contains(widget.idExtractor(item))) item,
          ]
        : selected;
    if (chosen.isEmpty) {
      _toastHidden(context);
      return;
    }
    final keep = action.shownOnly
        ? {
            for (final item in selected)
              if (!shown.contains(widget.idExtractor(item)))
                widget.idExtractor(item),
          }
        : const <int>{};
    final connection = _connection;
    final job = await action.prepare(context, chosen);
    if (!mounted || job == null || connection != _connection) return;
    await _perform(job, chosen, running: index, keep: keep);
  }

  /// Leaves selection mode, unless [keep] (the titles an action did not take
  /// because the chip hides them) is not empty: those stay selected.
  void _finishSelecting(Set<int> keep) {
    if (keep.isEmpty) {
      _endSelecting();
      return;
    }
    setState(() {
      _selected.retainAll(keep);
      _failure = null;
    });
  }

  /// Runs [job] for [items] and says what became of each title.
  ///
  /// [retrying] is the notice being run again for the titles it names: the
  /// outcome then folds into it rather than starting a new one.
  Future<void> _perform(
    MediaBulkJob<T> job,
    List<T> items, {
    required int running,
    _BulkNotice<T>? retrying,
    Set<int> keep = const {},
  }) async {
    final bulk = widget.bulk;
    final connection = _connection;
    setState(() {
      _running = running;
      _failure = null;
    });
    MediaBulkOutcome? outcome;
    Object? thrown;
    try {
      outcome = await job.run(items);
    } catch (error) {
      thrown = error;
    }
    if (!mounted) return;
    if (connection != _connection) {
      // The wall moved to another connection while this ran: what became of
      // these titles is the old connection's to hear, and nothing of it may
      // be drawn over the new one's titles. The library is read again.
      if (bulk != null && (thrown != null || outcome!.done.isNotEmpty)) {
        bulk.onChanged?.call(ref);
      }
      return;
    }
    setState(() => _running = null);

    if (thrown != null) {
      final unknown = _mayHaveApplied(thrown);
      // A write that may have gone through is read back, so the wall shows
      // what the server holds and a retry is for what is still to do.
      if (unknown && bulk != null) bulk.onChanged?.call(ref);
      _fail(
        thrown,
        retrying: retrying != null,
        unknown: unknown,
        again: () {
          if (connection != _connection) return;
          final ids = {for (final item in items) widget.idExtractor(item)};
          final held = ref.read(widget.libraryProvider).value;
          final left = unknown && held != null
              ? [
                  for (final item in held)
                    if (ids.contains(widget.idExtractor(item))) item,
                ]
              : items;
          if (left.isEmpty) {
            // The library no longer holds any of them: the write had gone
            // through.
            setState(() => _notice = null);
            _finishSelecting(keep);
            return;
          }
          _perform(job, left, running: running, retrying: retrying, keep: keep);
        },
      );
      return;
    }
    final result = outcome!;
    if (result.done.isNotEmpty && bulk != null) bulk.onChanged?.call(ref);

    final total = retrying?.total ?? items.length;
    final done = (retrying?.done ?? 0) + result.done.length;
    if (result.isWhole) {
      setState(() => _notice = null);
      _finishSelecting(keep);
      SnackBarHelper.success(context, job.doneLine(total));
      return;
    }
    if (retrying == null && result.isNone) {
      // Nothing took it: the selection stays, with why, so the same titles
      // can be tried again or let go.
      final first = result.failures.first;
      setState(
        () => _failure = (
          message: _failureLines(result.failures).join(' '),
          error: first.error,
          retry: () => _perform(job, items, running: running, keep: keep),
        ),
      );
      return;
    }
    _finishSelecting(keep);
    setState(
      () => _notice = _BulkNotice<T>(
        job: job,
        total: total,
        done: done,
        failures: result.failures,
      ),
    );
  }

  /// A failure that is no title's own (nothing answered, the key was
  /// refused): the selection stays, and a retry from a notice is told.
  void _fail(
    Object error, {
    required bool retrying,
    required bool unknown,
    required VoidCallback again,
  }) {
    final bulk = widget.bulk;
    if (bulk == null) return;
    final message = sectionFailureMessage(
      bulk.service,
      error,
      consequence: unknown
          ? 'some of these ${bulk.plural} may have changed'
          : 'nothing was changed',
    );
    if (retrying) {
      SnackBarHelper.error(context, message, cause: error, onRetry: again);
      return;
    }
    setState(() => _failure = (message: message, error: error, retry: again));
  }

  /// Whether [error] leaves it unknown if the write was carried out: the
  /// request was sent and nothing readable came back (a timeout after the
  /// connection was made, a reply that broke off, a 5xx). A request that
  /// certainly never arrived (refused, unresolved, not set up, refused by the
  /// key or the address) changed nothing.
  static bool _mayHaveApplied(Object error) {
    if (unwrapFailure(error) is ServiceNotConfigured) return false;
    return switch (classifyConnectionFailure(error)) {
      ServiceFailureReason.timeout ||
      ServiceFailureReason.serverError ||
      ServiceFailureReason.invalidResponse ||
      ServiceFailureReason.unknown => true,
      _ => false,
    };
  }

  /// Each refusal in the service's words, up to three, then how many more.
  static List<String> _failureLines(List<MediaBulkFailure> failures) => [
    for (final failure in failures.take(3)) failure.line,
    if (failures.length > 3) 'And ${failures.length - 3} more.',
  ];

  /// Runs the notice's action again for the titles it names, and no others.
  Future<void> _retryNotice() async {
    final notice = _notice;
    if (notice == null || _running != null) return;
    final items = ref.read(widget.libraryProvider).value;
    if (items == null) return;
    final ids = {for (final failure in notice.failures) failure.id};
    final again = [
      for (final item in items)
        if (ids.contains(widget.idExtractor(item))) item,
    ];
    if (again.isEmpty) {
      setState(() => _notice = null);
      return;
    }
    await _perform(
      notice.job,
      again,
      running: -1,
      retrying: notice,
      keep: {..._selected},
    );
  }

  /// Whether the wall is the thing on screen: not under another route, not in
  /// another tab. A selection does not outlive its wall being left.
  bool _isShowing(BuildContext context) =>
      BranchActivityScope.isActiveOf(context) &&
      (TickerMode.valuesOf(context).enabled || SidePaneScope.hostsOf(context));

  /// Title A–Z first, then whatever the service declared.
  ///
  /// The built-in order cannot be a const in [MediaBrowseScaffold.sorts]
  /// because it closes over this widget's own title extractors.
  List<MediaBrowseSort<T>> get _sortOptions => [
    MediaBrowseSort<T>(
      label: 'Title A–Z',
      lettered: true,
      compare: (left, right) {
        final leftKey = _sortKeyFor(left);
        final rightKey = _sortKeyFor(right);
        // The `#` section is one run, first: whatever is not a Latin letter
        // (digits, symbols, Cyrillic) goes before A whatever its code units
        // say, so a name past `z` cannot make a second `#` after Z.
        final leftHashed = _headedHash(leftKey);
        if (leftHashed != _headedHash(rightKey)) return leftHashed ? -1 : 1;
        final bySortTitle = leftKey.compareTo(rightKey);
        if (bySortTitle != 0) {
          return bySortTitle;
        }
        return foldForFind(
          widget.titleExtractor(left),
        ).compareTo(foldForFind(widget.titleExtractor(right)));
      },
    ),
    ...widget.sorts,
  ];

  /// The chips this screen can honestly offer.
  ///
  /// Cutoff unmet is conditional on a source; see
  /// [MediaBrowseScaffold.cutoffUnmetIds]. Wanted stands where Missing would
  /// ([MediaBrowseScaffold.wanted]). Available, Missing, In queue and
  /// Unmonitored are questions put to each title's status, so they are
  /// conditional on [MediaBrowseScaffold.statusExtractor]: a title with no
  /// status reads as a gap, which would answer Missing for the whole library
  /// and Available and In queue for none of it. A screen that cannot resolve
  /// a status says nothing rather than that.
  List<MediaBrowseFilter> get _filterOptions {
    final hasStatus = widget.statusExtractor != null;
    return [
      MediaBrowseFilter.all,
      if (hasStatus) ...[
        MediaBrowseFilter.available,
        // Wanted where the wall can say what it is short of, Missing where a
        // title's own status is the answer.
        if (widget.wanted != null)
          MediaBrowseFilter.wanted
        else
          MediaBrowseFilter.missing,
        MediaBrowseFilter.inQueue,
      ],
      if (widget.cutoffUnmetIds != null) MediaBrowseFilter.cutoffUnmet,
      if (hasStatus) MediaBrowseFilter.unmonitored,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final find = widget.find;
    // The library answers from the first keystroke, not after the debounce
    // that spares a server; and the search ends the moment the field is
    // empty, not 400ms later.
    final isSearching = _liveText.isNotEmpty;
    final wantedLine = isSearching ? null : _wantedSummary();
    final scopeProvider = find.scopeProvider;
    final scope = scopeProvider == null
        ? MediaFindScope.library
        : ref.watch(scopeProvider);

    // The query set from outside (a link that opens the wall on a word, Back,
    // a tap on the tab) is the field's text too.
    ref.listen<String>(widget.searchQueryProvider, (previous, next) {
      if (next != _liveText) _setLiveText(next);
    });

    ref.listen<int>(navigationRefreshProvider(widget.navigationSection), (
      previous,
      next,
    ) {
      ref.read(widget.searchQueryProvider.notifier).state = '';
      ref.invalidate(widget.libraryProvider);
      widget.onRefresh?.call(ref);
      if (_selectedFilter != MediaBrowseFilter.all) {
        setState(() {
          _selectedFilter = MediaBrowseFilter.all;
        });
      }
    });

    // What selection mode needs of the library: it is only entered over one.
    final library = ref.watch(widget.libraryProvider).value;
    final facts = _selecting && library != null
        ? _selectionFacts(library)
        : null;
    final showing = _isShowing(context);
    if (_selecting && !showing) {
      // Left for another tab or covered by a route: the selection does not
      // wait for the wall to come back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _endSelecting();
      });
    }
    final canSelect = widget.bulk != null && (library?.isNotEmpty ?? false);

    final scaffold = AmbientScaffold(
      accent: widget.accentColor,
      // The token, not a number tuned against it. This used to be 1160, argued
      // as "eight 130pt posters and their gaps", an off-token well chosen to
      // make a gap-blind column calculation come out right. Both halves of that
      // are gone: `MediaGrid.columnsFor` now resolves the count from the
      // constraints it is actually handed and accounts for the gaps, so the
      // well is free to be the same width as every other main well in the app.
      // `AppBreakpoints.contentWell` is the widest the main well is allowed to
      // grow on any shell, and a browse grid is not an exception to it.
      contentWellWidth: AppBreakpoints.contentWell,
      // Stays while selecting: a body under a bar is wrapped differently from
      // one with none ([AmbientScaffold]), and taking the bar away would
      // build the wall again from nothing and lose its place.
      appBar: widget.showAppBar
          ? GlassAppBar(
              leading: isSearching
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () {
                        ref.read(widget.searchQueryProvider.notifier).state =
                            '';
                      },
                      tooltip: 'Exit search',
                    )
                  : null,
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => context.push(widget.activityRoute),
                  tooltip: 'Activity',
                ),
              ],
            )
          : null,
      // The header (search + KPI + filters) lives in the NestedScrollView
      // header slivers as non-pinned adapters, so it scrolls away with the
      // content instead of staying fixed above the list.
      body: NestedScrollView(
        controller: _outer,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (_selecting)
            // `Cancel · 3 selected · Select all 34` in place of the band, the
            // field and the peek: the service's chrome has stepped aside
            // (`LibrarySelectionHide`), so only the status bar is cleared. A
            // wall with a bar of its own keeps it, and the header sits under.
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: _selectionTopInset(context)),
                  LibrarySelectionHeader(
                    selected: facts?.selected ?? 0,
                    shown: facts?.shown ?? 0,
                    hidden: facts?.hidden ?? 0,
                    hiddenBy: _filterLabel(
                      _selectedFilter,
                      widget.wanted?.label,
                    ),
                    allSelected: facts?.all ?? false,
                    onCancel: _cancelSelecting,
                    onToggleAll: () {
                      if (library != null) {
                        _toggleAll(library, deselect: facts?.all ?? false);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            )
          else if (widget.topPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: _chromeInset(context))),
          if (!_selecting)
            SliverToBoxAdapter(
              child: SearchBarHeader(
                hintText: widget.searchHint,
                // A word the Discover tab sends here ("Search Lidarr for …")
                // shows in the field it searches.
                initialQuery: ref.watch(widget.searchQueryProvider),
                onQueryChanged: (query) {
                  ref.read(widget.searchQueryProvider.notifier).state = query;
                },
                onTextChanged: _setLiveText,
              ),
            ),
          if (isSearching && scopeProvider != null)
            SliverToBoxAdapter(
              child: MediaFindScopeControl(
                serviceLabel: find.serviceLabel ?? widget.serviceName,
                selected: scope,
                onSelected: (next) => _selectScope(scopeProvider, next),
              ),
            ),
          if (!isSearching && !_selecting && widget.kpiPeek != null)
            SliverToBoxAdapter(child: widget.kpiPeek!),
          if (!isSearching)
            SliverToBoxAdapter(
              child: _MediaBrowseFilterChips(
                filters: _filterOptions,
                selectedFilter: _selectedFilter,
                // The brand book's chip: the ink fill when selected, whichever service
                // owns the library.
                color: Theme.of(context).colorScheme.primary,
                onSelected: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                wantedLabel: widget.wanted?.label,
                // Only a wall that can do something to its titles, once it
                // has some, and not while it is already selecting.
                onSelect: canSelect && !_selecting ? _beginSelecting : null,
                sortLabel: _sortOptions[_sortIndex].label,
                sortOptions: [for (final sort in _sortOptions) sort.label],
                selectedSort: _sortIndex,
                onSortSelected: (index) {
                  setState(() {
                    _sortIndex = index;
                  });
                },
              ),
            ),
          if (_failure case final failure?)
            SliverToBoxAdapter(
              child: InlineErrorRetry(
                message: failure.message,
                error: failure.error,
                service: widget.bulk!.service,
                instanceId: widget.bulk!.instanceId,
                // The same action for the same titles: the selection never
                // left.
                onRetry: () {
                  setState(() => _failure = null);
                  failure.retry();
                },
              ),
            ),
          if (_notice case final notice?)
            SliverToBoxAdapter(
              child: _BulkNoticeCard<T>(
                notice: notice,
                bulk: widget.bulk!,
                busy: _running != null,
                onRetry: _retryNotice,
                onDismiss: () => setState(() => _notice = null),
                lines: _failureLines(notice.failures),
              ),
            ),
          if (wantedLine != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  wantedLine,
                  style: AppType.meta.copyWith(
                    color: CupolaRoom.of(context).inkSecondary,
                  ),
                ),
              ),
            ),
        ],
        body: !isSearching
            ? _buildLibraryContent(context)
            : switch (scope) {
                MediaFindScope.library => find.libraryBody(context, _liveText),
                MediaFindScope.service => find.serviceBody!(
                  context,
                  ref.watch(widget.searchQueryProvider),
                ),
              },
      ),
    );

    final bulk = widget.bulk;
    if (bulk == null) return scaffold;

    // Back leaves the selection, not the wall: with a write out it is heard
    // and ignored, since nothing may cancel it.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelSelecting();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _withSelectionKeys(scaffold, library),
          // The selection bar floats at the foot of the wall: where the
          // navigation bar was on a phone, at the foot of the list elsewhere.
          // Kept built while it leaves, so it goes out with what it said.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LibrarySelectionSwap(
              shown: _selecting,
              holdsLast: true,
              enters: true,
              child: _selecting
                  ? _selectionBar(context, bulk, library, facts?.selected ?? 0)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// Esc cancels and Cmd A (Ctrl A off Apple platforms) selects all: the keys
  /// of a window with a keyboard, heard anywhere in the wall while it selects.
  ///
  /// Always in the tree, with no keys to hear until the wall selects: the
  /// wall under it must not be rebuilt from nothing when selection starts.
  Widget _withSelectionKeys(Widget child, List<T>? library) {
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return CallbackShortcuts(
      bindings: {
        if (_selecting) ...{
          const SingleActivator(LogicalKeyboardKey.escape): _cancelSelecting,
          SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: apple,
            control: !apple,
          ): () {
            if (library != null) _toggleAll(library, deselect: false);
          },
        },
      },
      child: Focus(focusNode: _keys, skipTraversal: true, child: child),
    );
  }

  /// The bar, at the foot: the navigation bar's own place and padding on a
  /// phone, and floating over the list's foot where there is a rail.
  Widget _selectionBar(
    BuildContext context,
    MediaBulk<T> bulk,
    List<T>? library,
    int count,
  ) {
    final phone = _hasNavBar(context);
    final bar = LibrarySelectionBar(
      label: count == 0
          ? 'No ${bulk.plural} selected'
          : '${bulk.countOf(count)} selected',
      dimmed: count == 0,
      dimmedHint: bulk.noneHint,
      busy: _running != null && _running! >= 0 ? _running : null,
      actions: [
        for (final (index, action) in bulk.actions.indexed)
          LibrarySelectionBarAction(
            icon: action.icon,
            label: action.label,
            onPressed: () {
              if (library != null) _tapAction(index, library);
            },
          ),
      ],
    );
    final padded = Padding(
      // The navigation bar's, to the point: the same margins over the same
      // foot. A phone's foot is the shell's bottom slot, which the page is
      // handed in its bottom padding (the home indicator and the bar, once),
      // so the bar stands as far above the foot as the navigation bar does.
      // The other layouts have no slot, and the bar floats the list's own
      // distance clear of the foot.
      padding: phone
          ? EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: math.max(
                MediaQuery.viewPaddingOf(context).bottom +
                    FloatingNavBarMetrics.bottomPadding,
                MediaQuery.paddingOf(context).bottom -
                    FloatingNavBarMetrics.topPadding -
                    FloatingNavBarMetrics.barHeightFor(context),
              ),
            )
          // The list's own side margins, so the bar lines up with the tiles.
          : const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: _railBarGap,
            ),
      child: bar,
    );
    // A desktop window draws the wall in a well (`DesktopContentWell`), and
    // the bar belongs to the list it acts on: at the foot of the well, no wider
    // than it and centred with it. A tablet's list column is as wide as the
    // list, so the bar already is.
    if (phone || !AppBreakpoints.isDesktopShell(context)) return padded;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentWell),
        child: padded,
      ),
    );
  }

  /// The line under the chips while Wanted is on: how many of the wall's titles
  /// the service wants something for, and what *wanted* means. Null while the
  /// answer or the library is out, and when nothing is wanted: the empty wall
  /// says that on its own.
  ///
  /// Counted over the library the wall shows, not the service's set: an id the
  /// library does not hold is not a tile.
  String? _wantedSummary() {
    final wanted = widget.wanted;
    if (wanted == null || _selectedFilter != MediaBrowseFilter.wanted) {
      return null;
    }
    final answer = wanted.answer.value;
    final items = ref.watch(widget.libraryProvider).value;
    if (answer == null || items == null) return null;
    final count = items
        .where((item) => answer.countById.containsKey(widget.idExtractor(item)))
        .length;
    return count == 0 ? null : wanted.summaryOf(count, answer.isFloor);
  }

  Widget _buildLibraryContent(BuildContext context) {
    final libraryAsync = ref.watch(widget.libraryProvider);
    final (url, apiKey, _) = ref.watch(
      currentSettingsProvider.select(widget.settingsSelector),
    );

    final service = widget.service;
    // A cold failure of a known service goes to its offline leaf. "Not
    // configured" keeps AsyncValueWidget's placeholder, and a failure over a
    // retained wall keeps its FaultBand over the last wall drawn.
    if (service != null &&
        libraryAsync.hasError &&
        !libraryAsync.hasValue &&
        libraryAsync.error is! ServiceNotConfigured) {
      return ServiceOfflineState.failure(
        service: service,
        error: libraryAsync.error!,
        onRetry: () {
          ref.invalidate(widget.libraryProvider);
          widget.onRefresh?.call(ref);
        },
      );
    }

    return RefreshIndicator(
      color: _spinnerInk(context),
      onRefresh: () async {
        ref.invalidate(widget.libraryProvider);
        widget.onRefresh?.call(ref);
      },
      child: AsyncValueWidget<List<T>>(
        value: libraryAsync,
        serviceName: widget.serviceName,
        silentService: service,
        loadingWidget: Center(
          child: CircularProgressIndicator(color: _spinnerInk(context)),
        ),
        onRetry: () {
          ref.invalidate(widget.libraryProvider);
          widget.onRefresh?.call(ref);
        },
        data: (items) => _buildBrowseContent(
          context: context,
          items: items,
          baseUrl: url,
          apiKey: apiKey,
        ),
      ),
    );
  }

  /// The ink for this screen's progress spinners: the room's primary ink
  /// (the lamp that [accentColor] carries resolves to it through
  /// `ServiceTheme.onTint`), or the theme's own when no service owns the page.
  Color? _spinnerInk(BuildContext context) {
    final accent = widget.accentColor;
    if (accent == null) return null;
    return ServiceTheme.onTint(
      accent,
      surface: Theme.of(context).colorScheme.surface,
      tintAlpha: 0,
    );
  }

  Widget _buildBrowseContent({
    required BuildContext context,
    required List<T> items,
    required String baseUrl,
    required String apiKey,
  }) {
    // The wall's own Wanted answer is not in yet, or never came: the wall
    // says which, rather than filter itself down to nothing on a question
    // nobody answered.
    final wanted = widget.wanted;
    if (_selectedFilter == MediaBrowseFilter.wanted &&
        wanted != null &&
        !wanted.answer.hasValue) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _stateListPadding(context),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          if (wanted.answer.error case final error?)
            InlineErrorRetry.flush(
              message: sectionFailureMessage(
                wanted.service,
                error,
                consequence: wanted.failureConsequence,
              ),
              error: error,
              service: wanted.service,
              instanceId: wanted.instanceId,
              onRetry: wanted.onRetry,
            )
          else
            Center(
              child: CircularProgressIndicator(color: _spinnerInk(context)),
            ),
        ],
      );
    }

    final visibleItems = _filteredItems(items);

    if (visibleItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _stateListPadding(context),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          // The two absences are different facts: a library with nothing in
          // it, and a chip that hides everything there is. The second one
          // says which chip and offers the way back.
          if (_selectedFilter == MediaBrowseFilter.all)
            AppEmptyState.compact(
              icon: widget.emptyIcon,
              title: 'Your ${widget.serviceName} library is empty',
              message: widget.emptyMessage,
            )
          else
            AppEmptyState.compact(
              icon: Icons.filter_list_off_rounded,
              title: mediaBrowseFilterEmptyTitle(_selectedFilter),
              action: TextButton(
                onPressed: () =>
                    setState(() => _selectedFilter = MediaBrowseFilter.all),
                child: const Text('Show all'),
              ),
            ),
        ],
      );
    }

    final sections = _buildSections(visibleItems);
    // The strip belongs to the alphabetical order alone, which is the one
    // that has headings, and only to a wall long enough to need it.
    final showIndex =
        !_selecting &&
        sections.isNotEmpty &&
        sections.first.label.isNotEmpty &&
        visibleItems.length >= MediaBrowseIndex.minTitles;
    // The strip sits in the right margin; the wall gives it that margin so no
    // tile is ever under a finger meant for a letter.
    final rightMargin = showIndex ? MediaBrowseIndex.width : AppSpacing.lg;

    // **Built a row at a time, as the rows scroll in.** This used to be one
    // `ListView` item per section with every tile of the section in a `Wrap`,
    // which is lazy only across sections, and any order but Title A–Z is ONE
    // section, so a 2 000-title library built 2 000 tiles and started 2 000
    // poster loads the moment the wall appeared. A `SliverGrid` is not the
    // answer either: it gives every cell one fixed extent, and a tile's height
    // is its own content: the caption lines grow with the reading size and an
    // empty subtitle takes no line, so a grid would clip at 2x or leave air
    // under a caption-less row. What the `Wrap` drew is kept exactly: a run is
    // a top-aligned `Row` as tall as its tallest tile, `gridGap` between
    // columns and `space-lg` between rows, `space-xl` after a section's last
    // row. Only the building is lazy.
    //
    // The scroll view is the Stack's first child whether or not the strip
    // shows, so a chip that takes the wall across the strip's threshold keeps
    // its scroll position.
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The tiles are what a screen reader counts ("items 13 to 24 of
          // 60"), not the rows or the headings the list happens to be built
          // from.
          semanticChildCount: visibleItems.length,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: rightMargin,
                top: _wallTopPadding,
                bottom:
                    AppSpacing.lg +
                    FloatingNavBarMetrics.getScrollViewBottomPadding(context) +
                    _selectionClearance(context),
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  // One column math for the whole app, and the tiles fill the
                  // row they are given.
                  //
                  // This used to pin a 96pt tile, under the 130pt floor every
                  // other grid is held to, and then compute a spacing to
                  // distribute the leftover, only to `.clamp(0, gridGap)` that
                  // spacing away again. The slack it had just measured came
                  // back as a ragged right edge: at 390pt, three 96pt tiles
                  // and two 12pt gaps are 312 inside 358, so 46pt of dead
                  // space sat at the end of every row. The boards draw
                  // `repeat(N, minmax(0, 1fr))`: the count is resolved first,
                  // then the tiles take what is left.
                  final width = constraints.crossAxisExtent;
                  // What a jump to a letter measures its offsets against: the
                  // very extent this layout was given.
                  _wallExtent = width;
                  final (:columns, :tileWidth) = _gridFor(width);
                  final entries = _browseEntries(sections, columns);

                  return SliverList.builder(
                    itemCount: entries.length,
                    // Indexed per tile inside each row instead; see
                    // `semanticChildCount` above.
                    addSemanticIndexes: false,
                    itemBuilder: (context, index) => _buildBrowseEntry(
                      context: context,
                      entry: entries[index],
                      items: visibleItems,
                      tileWidth: tileWidth,
                      baseUrl: baseUrl,
                      apiKey: apiKey,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (showIndex)
          _buildIndexLayer(
            context: context,
            items: visibleItems,
            sections: sections,
          ),
      ],
    );
  }

  /// The padding of a body that is not a wall of tiles (a wait, a failure, an
  /// empty chip): the wall's own margins, and room above the bar.
  EdgeInsets _stateListPadding(BuildContext context) => EdgeInsets.only(
    left: AppSpacing.lg,
    right: AppSpacing.lg,
    top: AppSpacing.lg,
    bottom:
        AppSpacing.lg +
        FloatingNavBarMetrics.getScrollViewBottomPadding(context) +
        _selectionClearance(context),
  );

  /// The air over the first heading of the wall.
  static const double _wallTopPadding = AppSpacing.sm;

  /// What the wall's column count and tile width come out as for a cross-axis
  /// extent: the one math the layout and a jump to a letter share.
  static ({int columns, double tileWidth}) _gridFor(double crossAxisExtent) {
    final columns = MediaGrid.columnsFor(crossAxisExtent, _minBrowseColumns);
    return (
      columns: columns,
      tileWidth: math.max(
        1.0,
        (crossAxisExtent - (AppSpacing.gridGap * (columns - 1))) / columns,
      ),
    );
  }

  /// The cross-axis extent the wall's grid was last laid out in, for the
  /// offsets of [_jumpToLetter]. Written by the layout itself, which is the
  /// only thing that knows it: the wall's width less its margins, and the
  /// strip's.
  double? _wallExtent;

  /// How far the room above the body reaches: the tab bar and the status bar
  /// that a service tab lays over the top of the page ([topPadding]). Zero on
  /// a page with a bar of its own, whose body begins under it.
  double _chromeInset(BuildContext context) => widget.topPadding > 0
      ? widget.topPadding + MediaQuery.paddingOf(context).top
      : 0;

  /// How much of the header (field, peek, chips) is still showing over the
  /// body, or null when its scroll position has not been laid out yet.
  ///
  /// The body is exactly what the header leaves of the page, so this is how
  /// far the body's top is from the page's: it grows by that much when the
  /// header folds away.
  double? _headerShowing() {
    if (!_outer.hasClients) return null;
    final position = _outer.position;
    if (!position.hasContentDimensions) return null;
    return math.max(0.0, position.maxScrollExtent - position.pixels);
  }

  /// The strip, over the right margin of the body: from under the header (and
  /// under the chrome of a service tab, once the header has gone) to above
  /// the floating bar.
  Widget _buildIndexLayer({
    required BuildContext context,
    required List<T> items,
    required List<_MediaBrowseSection> sections,
  }) {
    final inset = _chromeInset(context);
    final bottom = FloatingNavBarMetrics.getScrollViewBottomPadding(context);
    final present = {
      for (final section in sections)
        if (section.label.isNotEmpty) section.label,
    };
    return Positioned.fill(
      // Built again whenever the body's height changes, which is what the
      // header folding away does to it: only the strip, never the wall.
      child: LayoutBuilder(
        builder: (body, _) {
          // The body starts `showing` below the page's top; the chrome covers
          // `inset` of it from the top.
          final clearance = math.max(0.0, inset - (_headerShowing() ?? inset));
          return Padding(
            padding: EdgeInsets.only(
              top: clearance + AppSpacing.xs,
              bottom: bottom,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: MediaBrowseIndex(
                present: present,
                onJump: (letter) => _jumpToLetter(
                  // The wall is measured from the context that built it, the
                  // scroll position is the body's.
                  measuredFrom: context,
                  body: body,
                  letter: letter,
                  items: items,
                  sections: sections,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The air between the top of the body and a heading a jump lands on: the
  /// chrome a service tab lays over it, or the fade a bar casts on it, so the
  /// heading is whole and in the clear, and a little of the wall's own top
  /// margin.
  double _landingAir(BuildContext context) {
    final inset = _chromeInset(context);
    final cover = inset > 0
        ? inset
        : (widget.showAppBar ? ScrollEdgeFade.height : 0.0);
    return cover + _wallTopPadding;
  }

  /// Jumps the wall to the heading of [letter]: at once, no animation, with
  /// the heading at the top of what the body shows (see [_landingAir]).
  ///
  /// The wall is lazy, so a section that is not built has no key and no box to
  /// ask: its offset is the sum of everything before it, from the same grid
  /// the layout uses ([_gridFor], [_browseEntries]) and the heights its rows
  /// come out at ([_measureWall]).
  ///
  /// The scroll position is the nested one, whose offset counts the header
  /// first: a jump folds the header away (the body is then as tall as the page)
  /// and lands the heading under its top. So the wall may not be asked for more
  /// than it can scroll once the header is gone, or it would be sent back by
  /// the position's own ballistics a frame later. That limit is the measured
  /// wall less the page, not the position's `maxScrollExtent`: a lazy list
  /// only *estimates* its end from the rows it has built, and an estimate from
  /// the top of a long wall would stop a jump to its last letters short.
  void _jumpToLetter({
    required BuildContext measuredFrom,
    required BuildContext body,
    required String letter,
    required List<T> items,
    required List<_MediaBrowseSection> sections,
  }) {
    final context = measuredFrom;
    final extent = _wallExtent;
    final controller = PrimaryScrollController.maybeOf(body);
    if (extent == null || controller == null || !controller.hasClients) return;
    final wall = _measureWall(context, items, sections, extent);
    final heading = wall.headings[letter];
    if (heading == null) return;
    final position = controller.position;
    final showing = _headerShowing() ?? 0;
    final furthest = math.max(
      0.0,
      wall.extent - (position.viewportDimension + showing),
    );
    position.jumpTo((heading - _landingAir(context)).clamp(0.0, furthest));
  }

  /// Where each heading starts in the body's scroll extent, and how long the
  /// whole of it is, with its padding.
  ///
  /// The same walk the layout makes, over the same entries, with each row as
  /// tall as its tallest tile: the artwork, the gap, the title, and the
  /// subtitle when any tile of the run has one.
  ({Map<String, double> headings, double extent}) _measureWall(
    BuildContext context,
    List<T> items,
    List<_MediaBrowseSection> sections,
    double crossAxisExtent,
  ) {
    final (:columns, :tileWidth) = _gridFor(crossAxisExtent);
    final lines = MediaPosterCaption.lineHeightsOf(context);
    final heading = _headingExtent(context);
    final artwork = widget.tileShape == MediaBrowseTileShape.circle
        ? tileWidth
        : tileWidth * 3 / 2;

    final headings = <String, double>{};
    var offset = _wallTopPadding;
    for (final entry in _browseEntries(sections, columns)) {
      if (entry.label case final label?) {
        headings[label] = offset;
        offset += heading;
        continue;
      }
      var anySubtitle = false;
      for (var index = entry.start; index < entry.end; index++) {
        if (_subtitleFor(items[index]).isNotEmpty) {
          anySubtitle = true;
          break;
        }
      }
      offset +=
          artwork +
          MediaPosterCaption.gap +
          lines.title +
          (anySubtitle ? lines.subtitle : 0) +
          entry.gapBelow;
    }
    return (
      headings: headings,
      extent:
          offset +
          AppSpacing.lg +
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    );
  }

  /// A section heading's style: the room's section title.
  TextStyle _headingStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.weight(FontWeight.w600);

  /// A section heading's height at the reading size: its line and the gap
  /// under it ([_buildBrowseEntry]).
  double _headingExtent(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: _headingStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height + AppSpacing.md;
  }

  /// What the tile of [item] says under its title: the screen's own caption,
  /// or the Wanted count while that chip is on.
  String _subtitleFor(T item) {
    final wanted = widget.wanted;
    if (wanted != null && _selectedFilter == MediaBrowseFilter.wanted) {
      final answer = wanted.answer.value;
      final count = answer?.countById[widget.idExtractor(item)];
      if (answer != null && count != null) {
        return wanted.captionOf(count, answer.isFloor);
      }
    }
    return widget.subtitleExtractor(item);
  }

  /// The wall flattened into headings and rows for [columns] across.
  ///
  /// Cheap on purpose: a few integers per row, no widget and no extractor
  /// call, because it runs over the whole library whenever the width changes.
  /// Everything that costs anything is deferred to [_buildBrowseEntry], which
  /// runs only for the rows on or near the screen.
  static List<_BrowseEntry> _browseEntries(
    List<_MediaBrowseSection> sections,
    int columns,
  ) {
    final entries = <_BrowseEntry>[];
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      // The section's key rides on its first entry: the heading, or the first
      // row of an unheaded run, so a section is still findable by the key it
      // has always had, and still only once it has been built.
      final sectionKey = ValueKey<String>(
        'media-browse-section-${section.label.isEmpty ? 'flat' : section.label}',
      );
      if (section.label.isNotEmpty) {
        entries.add(_BrowseEntry.heading(section.label, key: sectionKey));
      }
      final isLastSection = sectionIndex == sections.length - 1;
      for (var start = section.start; start < section.end; start += columns) {
        final end = math.min(start + columns, section.end);
        final isLastRow = end == section.end;
        entries.add(
          _BrowseEntry.row(
            start,
            end,
            // `runSpacing` inside a section, then the section's own foot:
            // `space-xl` to the next heading, `space-lg` after the last one.
            gapBelow: !isLastRow
                ? AppSpacing.lg
                : (isLastSection ? AppSpacing.lg : AppSpacing.xl),
            key: section.label.isEmpty && start == section.start
                ? sectionKey
                : null,
          ),
        );
      }
    }
    return entries;
  }

  Widget _buildBrowseEntry({
    required BuildContext context,
    required _BrowseEntry entry,
    required List<T> items,
    required double tileWidth,
    required String baseUrl,
    required String apiKey,
  }) {
    final label = entry.label;
    if (label != null) {
      return Column(
        key: entry.key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _headingStyle(context)),
          const SizedBox(height: AppSpacing.md),
        ],
      );
    }

    return Padding(
      key: entry.key,
      padding: EdgeInsets.only(bottom: entry.gapBelow),
      // Top-aligned and as tall as its tallest tile: exactly one `Wrap` run.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.gridGap,
        children: [
          for (var index = entry.start; index < entry.end; index++)
            IndexedSemantics(
              index: index,
              child: _buildTile(
                context: context,
                item: items[index],
                // The index in the visible list, as it always was: it keeps
                // two rows with one id (search results can carry id 0) from
                // sharing a Hero tag.
                heroTag:
                    '${widget.heroTagPrefix}_${widget.idExtractor(items[index])}_$index',
                tileWidth: tileWidth,
                baseUrl: baseUrl,
                apiKey: apiKey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required T item,
    required String heroTag,
    required double tileWidth,
    required String baseUrl,
    required String apiKey,
  }) {
    final id = widget.idExtractor(item);
    final selecting = _selecting;
    return _BrowsePosterTile(
      width: tileWidth,
      shape: widget.tileShape,
      fallbackIcon: widget.posterFallbackIcon,
      title: widget.titleExtractor(item),
      subtitle: _subtitleFor(item),
      imageSource: ImageUtils.extractPosterUrl(
        widget.imagesExtractor(item),
        baseUrl: baseUrl,
        apiKey: apiKey,
        coverTypes: widget.coverTypes ?? const ['poster', 'cover'],
      ),
      status: widget.statusExtractor?.call(item),
      heroTag: heroTag,
      selecting: selecting,
      selected: _selected.contains(id),
      // A tap toggles while selecting, and opens the title otherwise.
      onTap: selecting
          ? () => _toggle(id)
          : () => widget.onItemTap(context, item, heroTag),
      // The long press that starts selecting, on a wall that can.
      onLongPress: widget.bulk != null && !selecting
          ? () => _beginSelecting(id: id)
          : null,
    );
  }

  List<T> _filteredItems(List<T> items) {
    final cutoff = widget.cutoffUnmetIds;
    final wanted = widget.wanted?.answer.value;
    return _sortedItems(items)
        .where(
          (item) => mediaBrowseFilterMatches(
            _selectedFilter,
            widget.statusExtractor?.call(item),
            belowCutoff:
                cutoff != null && cutoff.contains(widget.idExtractor(item)),
            isWanted:
                wanted != null &&
                wanted.countById.containsKey(widget.idExtractor(item)),
          ),
        )
        .toList(growable: false);
  }

  /// [items] in display order, computed once per (library list, chosen order),
  /// see [_sortedSource]. The result is never mutated afterwards.
  List<T> _sortedItems(List<T> items) {
    final cached = _sorted;
    if (cached != null &&
        identical(items, _sortedSource) &&
        _sortedUnder == _sortIndex) {
      return cached;
    }

    final sortedItems = [...items]..sort(_sortOptions[_sortIndex].compare);

    _sortedSource = items;
    _sorted = sortedItems;
    _sortedUnder = _sortIndex;
    return sortedItems;
  }

  List<_MediaBrowseSection> _buildSections(List<T> items) {
    // One unlabelled run under any order but Title A–Z. The headings used to be
    // unconditional, so a date-added wall printed "A" over a section whose
    // first title happened to start with one.
    if (!_sortOptions[_sortIndex].lettered) {
      return [_MediaBrowseSection(label: '', start: 0, end: items.length)];
    }

    final sections = <_MediaBrowseSection>[];
    var start = 0;
    String? label;
    for (var index = 0; index < items.length; index++) {
      final itemLabel = _sectionLabelFor(items[index]);
      if (label != null && itemLabel != label) {
        sections.add(
          _MediaBrowseSection(label: label, start: start, end: index),
        );
        start = index;
      }
      label = itemLabel;
    }
    if (label != null) {
      sections.add(
        _MediaBrowseSection(label: label, start: start, end: items.length),
      );
    }
    return sections;
  }

  /// The key the wall sorts and sections by: the sort title, folded the way
  /// the field matches (`foldForFind`), so `Édith Piaf` sorts and is headed
  /// with the Es and `Øyvind` with the Os, not after Z under `#`.
  String _sortKeyFor(T item) => foldForFind(
    (widget.sortTitleExtractor?.call(item) ?? widget.titleExtractor(item))
        .trim(),
  );

  /// Whether a sort key is headed `#`: empty, or not starting with A–Z.
  static bool _headedHash(String sortKey) =>
      sortKey.isEmpty ||
      !_sectionLetter.hasMatch(sortKey.characters.first.toUpperCase());

  String _sectionLabelFor(T item) {
    final sortKey = _sortKeyFor(item);
    return _headedHash(sortKey) ? '#' : sortKey.characters.first.toUpperCase();
  }
}

/// One run of the visible list, `[start, end)`, under one heading or under
/// none, when [label] is empty.
///
/// Indices rather than a copy of the items: the rows are cut from the same
/// list the tiles read, so a library is never held twice.
class _MediaBrowseSection {
  final String label;
  final int start;
  final int end;

  const _MediaBrowseSection({
    required this.label,
    required this.start,
    required this.end,
  });
}

/// One entry of the lazily built wall: a section heading, or one row of tiles
/// `[start, end)` of the visible list.
class _BrowseEntry {
  /// The heading's text; null for a row.
  final String? label;

  final int start;
  final int end;

  /// The space under a row: the run spacing inside a section, the section gap
  /// after its last row.
  final double gapBelow;

  final Key? key;

  const _BrowseEntry.heading(String this.label, {this.key})
    : start = 0,
      end = 0,
      gapBelow = 0;

  const _BrowseEntry.row(
    this.start,
    this.end, {
    required this.gapBelow,
    this.key,
  }) : label = null;
}

class _MediaBrowseFilterChips extends StatelessWidget {
  final List<MediaBrowseFilter> filters;
  final MediaBrowseFilter selectedFilter;
  final Color color;
  final ValueChanged<MediaBrowseFilter> onSelected;
  final String? wantedLabel;

  /// Starts selecting, or null where the wall has nothing to do to its titles
  /// (or is selecting already): then there is no `Select`.
  final VoidCallback? onSelect;
  final String sortLabel;
  final List<String> sortOptions;
  final int selectedSort;
  final ValueChanged<int> onSortSelected;

  const _MediaBrowseFilterChips({
    required this.filters,
    required this.selectedFilter,
    required this.color,
    required this.onSelected,
    required this.wantedLabel,
    required this.onSelect,
    required this.sortLabel,
    required this.sortOptions,
    required this.selectedSort,
    required this.onSortSelected,
  });

  @override
  Widget build(BuildContext context) {
    // One chip is no choice, any more than one order is: a lone `All` filters
    // nothing and only says that the screen has no question to put.
    final hasChips = filters.length > 1;
    final hasSort = sortOptions.length > 1;
    if (!hasChips && !hasSort && onSelect == null) {
      return const SizedBox.shrink();
    }

    // At a large reading size the sort control and `Select` no longer fit one
    // line beside the chips: `Select` goes under them, at the end.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;
    final selectBeside = onSelect != null && !stacked;
    final strip = Row(
      children: [
        if (hasChips)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in filters)
                    MediaBrowseFilterChip(
                      label: _filterLabel(filter, wantedLabel),
                      color: color,
                      selected: selectedFilter == filter,
                      onTap: () => onSelected(filter),
                    ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        if (hasSort)
          MediaBrowseSortControl(
            label: sortLabel,
            options: sortOptions,
            selected: selectedSort,
            onSelected: onSortSelected,
          ),
        if (selectBeside) _MediaBrowseSelectButton(onTap: onSelect!),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      // The chips scroll; the sort control does not. It is the one instrument
      // on this strip that has to stay reachable no matter how many chips a
      // service declares, and a control that scrolls off the end of a strip it
      // does not belong to is a control nobody finds.
      child: onSelect != null && stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                strip,
                _MediaBrowseSelectButton(onTap: onSelect!),
              ],
            )
          : strip,
    );
  }
}

/// A chip's name, as the strip prints it and the selection header names the
/// chip that hides some of what is selected.
String _filterLabel(MediaBrowseFilter filter, String? wantedLabel) =>
    switch (filter) {
      MediaBrowseFilter.all => 'All',
      MediaBrowseFilter.available => 'Available',
      MediaBrowseFilter.missing => 'Missing',
      MediaBrowseFilter.wanted => wantedLabel ?? 'Wanted',
      MediaBrowseFilter.inQueue => 'In queue',
      MediaBrowseFilter.cutoffUnmet => 'Cutoff unmet',
      MediaBrowseFilter.unmonitored => 'Unmonitored',
    };

/// `Select`, at the end of the chips: the way into selection mode with
/// nothing selected, for a pointer that has no long press and a hand that
/// would rather not.
class _MediaBrowseSelectButton extends StatelessWidget {
  const _MediaBrowseSelectButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Select',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusPill,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            alignment: Alignment.center,
            child: Text(
              'Select',
              style: AppTheme.chrome(
                context,
                weight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the last bulk action left undone: the action to run again, how many
/// titles it was for, how many took it so far, and the ones that were refused.
class _BulkNotice<T> {
  const _BulkNotice({
    required this.job,
    required this.total,
    required this.done,
    required this.failures,
  });

  final MediaBulkJob<T> job;
  final int total;
  final int done;
  final List<MediaBulkFailure> failures;
}

/// The amber notice over the wall after an action some titles refused:
/// `2 of 3 artists updated`, the refusals in the service's words, and a
/// remedy that runs the same action again for the titles that were refused.
class _BulkNoticeCard<T> extends StatelessWidget {
  const _BulkNoticeCard({
    required this.notice,
    required this.bulk,
    required this.busy,
    required this.onRetry,
    required this.onDismiss,
    required this.lines,
  });

  final _BulkNotice<T> notice;
  final MediaBulk<T> bulk;

  /// The action is out again: its verb shows progress and takes no tap.
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final title = notice.job.partialLine(notice.done, notice.total);
    final failures = notice.failures;
    final again = failures.length == 1
        ? 'Try ${failures.first.name} again'
        : 'Try ${bulk.countOf(failures.length)} again';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: room.toneAmberWash,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        // Announced when it appears, which is when it matters.
        liveRegion: true,
        label: [title, ...lines].join('. '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The tone is one dot, on the first line.
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs + AppSpacing.xxs,
                      right: AppSpacing.sm,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: room.toneAmber,
                      ),
                      child: const SizedBox.square(dimension: 7),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                  ),
                ],
              ),
            ),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: ExcludeSemantics(
                  child: Text(
                    line,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: busy ? null : onRetry,
                  style: remedyFillStyle(context, compact: true),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(again),
                ),
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  style: retryInkStyle(colorScheme),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `Sort · <label>`, opening the orders this service declared.
///
/// One order is not a choice, so the control is only built when there are two:
/// a menu whose every opening shows the same single item is a control that
/// cannot fail and cannot help either.
class MediaBrowseSortControl extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;

  const MediaBrowseSortControl({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<int>(
      tooltip: 'Change sort order',
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (var index = 0; index < options.length; index++)
          PopupMenuItem<int>(value: index, child: Text(options[index])),
      ],
      // The hint rides on the child, never on the button: a button is a
      // semantic boundary and an annotation wrapped around one is dropped.
      child: Semantics(
        hint: 'Sorted by $label',
        child: Container(
          // 44, and no `VisualDensity.compact` anywhere near it, since compact
          // silently overrides a declared minimum and lands the real target at
          // 40.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTheme.chrome(
                  context,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaBrowseFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const MediaBrowseFilterChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      // `AppRadius.pill`, not a repeated literal 20: a change to the token has
      // to reach this chip too.
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.borderRadiusPill,
            child: Container(
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusPill,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .weight(FontWeight.w600)
                    .copyWith(
                      // Unselected, the label sits on the fill's own 12% wash,
                      // so it is measured against that composite.
                      color: selected
                          ? ServiceTheme.foregroundOn(color)
                          : ServiceTheme.onTint(
                              color,
                              surface: Theme.of(context).colorScheme.surface,
                              tintAlpha: 0.12,
                            ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowsePosterTile extends StatelessWidget {
  /// Resolved by the row, not by the tile: the column count is decided against
  /// [MediaGrid.tileWidthFloor] first and the tiles then fill what is left, so
  /// a tile never has an opinion about how wide it is.
  final double width;

  final MediaBrowseTileShape shape;
  final IconData fallbackIcon;

  final String title;
  final String subtitle;
  final ImageSource imageSource;
  final MediaStatusInfo? status;
  final String heroTag;
  final VoidCallback onTap;

  /// The wall is in selection mode: the tile wears its disc, and is a toggle.
  final bool selecting;

  /// The tile is among the selected.
  final bool selected;

  /// Starts selecting with this tile, or null where it cannot.
  final VoidCallback? onLongPress;

  const _BrowsePosterTile({
    required this.width,
    required this.shape,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.imageSource,
    required this.status,
    required this.heroTag,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
    this.onLongPress,
  });

  bool get isCircle => shape == MediaBrowseTileShape.circle;

  /// The portrait or the poster, sized from the width the row resolved.
  Widget _artwork(BuildContext context) {
    if (isCircle) {
      // Square, so the circle is a circle at any column count, and
      // `MediaPosterCard.circular` brings its own Hero; the rectangular path
      // has to supply one because `ContentCard` does not.
      //
      // No status dot: a circle has no corner to hold one without overlapping
      // the face, and the caption carries the completeness in words instead.
      return AspectRatio(
        aspectRatio: 1,
        child: _selectable(
          context,
          MediaPosterCard.circular(
            heroTag: heroTag,
            imageUrl: imageSource.url,
            imageHeaders: imageSource.headers,
            fallbackIcon: Icons.person_outline_rounded,
          ),
          markInset: 2,
          markSize: 28,
        ),
      );
    }

    // 2:3 of whatever width the row resolved, rather than a 96×138 pair that
    // only held at one column count.
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: _selectable(
        context,
        Stack(
          children: [
            Positioned.fill(
              child: Hero(
                tag: heroTag,
                transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
                child: ContentCard(
                  imageUrl: imageSource.url,
                  httpHeaders: imageSource.headers,
                  paneTag: heroTag,
                  fallbackIcon: fallbackIcon,
                ),
              ),
            ),
            if (status != null)
              Positioned(
                left: 6,
                bottom: 6,
                // Redundant against the parent's `excludeSemantics`, but it keeps
                // the invariant local: the tile speaks the status, the dot does
                // not.
                child: StatusBadge(
                  info: status!,
                  iconOnly: true,
                  excludeFromSemantics: true,
                ),
              ),
          ],
        ),
        markInset: 6,
        markSize: 26,
      ),
    );
  }

  /// How far an unselected tile's artwork dims in selection mode: the
  /// selected ones stand out by being whole.
  static const double _unselectedOpacity = 0.55;

  /// [artwork] as selection mode draws it: dimmed unless it is selected, with
  /// the disc in its top right corner. Outside selection mode it is the
  /// artwork alone.
  Widget _selectable(
    BuildContext context,
    Widget artwork, {
    required double markInset,
    required double markSize,
  }) {
    if (!selecting) return artwork;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: selected ? 1 : _unselectedOpacity,
          duration: MediaQuery.disableAnimationsOf(context)
              ? AppAnimation.reducedFade
              : AppAnimation.standard,
          curve: AppAnimation.standardCurve,
          child: artwork,
        ),
        Positioned(
          right: markInset,
          top: markInset,
          child: LibrarySelectionMark(selected: selected, size: markSize),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The status is painted inside the excluded subtree, or, on the circular
    // shape, not painted at all, so it has to be spoken here or it is lost
    // entirely.
    final spokenValue = joinDisplayParts([
      subtitle,
      status?.semanticLabel,
    ], separator: ', ');

    return SizedBox(
      width: width,
      // Labelled as one button: the visible title is truncated to a single line,
      // so a screen reader would otherwise announce a clipped name.
      child: Semantics(
        // A button that opens the title; a toggle, with its state, while the
        // wall is selecting.
        button: !selecting,
        checked: selecting ? selected : null,
        container: true,
        excludeSemantics: true,
        label: title,
        value: spokenValue.isEmpty ? null : spokenValue,
        onTap: onTap,
        onLongPress: onLongPress,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppRadius.borderRadiusMd,
          child: Column(
            crossAxisAlignment: isCircle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _artwork(context),
              const SizedBox(height: MediaPosterCaption.gap),
              MediaPosterCaption(
                title: title,
                subtitle: subtitle,
                centered: isCircle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
