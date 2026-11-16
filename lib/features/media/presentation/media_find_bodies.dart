import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/find_index.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// `2 movies`, `1 series`, `12 authors`: a count with its noun, the figure
/// holding to the word.
String findCount(int count, {required String one, required String many}) =>
    '$count$unitSpace${count == 1 ? one : many}';

/// A title's state on the wall as a find row says it: the wall's own word
/// (the one its badge carries, `badgeOverQueue` and all), and whether it is
/// the backlog's ring (neutral, as the state words draw it) or a filled dot.
({({String label, StatusTone tone})? status, bool hollow}) mediaFindState(
  MediaStatusInfo? info,
) {
  if (info == null) return (status: null, hollow: false);
  return (
    status: (label: mediaStatusWord(info) ?? info.label, tone: info.tone),
    hollow: info.tone == StatusTone.neutral,
  );
}

/// The padding under a list of results: the room the floating nav bar takes.
EdgeInsets findListPadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.lg,
  AppSpacing.sm,
  AppSpacing.lg,
  AppSpacing.lg + FloatingNavBarMetrics.getScrollViewBottomPadding(context),
);

/// The connection a wall is reading, as a sentence says it (`Radarr`,
/// `Radarr 4K`).
String watchConnectionName(WidgetRef ref, ServiceKey service) {
  final lens = ref.watch(activeInstanceProvider(service));
  return ref
      .watch(currentSettingsProvider)
      .connectionTitle(lens?.id ?? '', service, joiner: ' ');
}

/// What a library wall's search of its own library draws: one section, headed
/// by how many it found and what they are (`2 movies`), over the rows of what
/// the wall already read, found as it is typed by the start of a word of any
/// of a thing's names, blind to case and accents (see [FindIndex]).
///
/// The rows are built as they scroll in, since a library of thousands matches
/// a short word in thousands. Nothing found is said once, with the way to ask
/// the service when there is one ([onAskService]).
class MediaFindLibraryBody<T> extends ConsumerStatefulWidget {
  const MediaFindLibraryBody({
    super.key,
    required this.query,
    required this.library,
    required this.service,
    required this.namesOf,
    required this.heading,
    required this.rowOf,
    this.onAskService,
  });

  /// The text as typed.
  final String query;

  /// What the wall read. Must fail when the read fails, as the wall's does.
  final FutureProvider<List<T>> library;

  final ServiceKey service;

  /// The names a thing is found by; the first orders the list.
  final List<String> Function(T item) namesOf;

  /// The section's heading for [count] of them: `2 movies`.
  final String Function(int count) heading;

  final Widget Function(BuildContext context, T item) rowOf;

  /// Moves the search to the service, with the same words. Null where there is
  /// no service to ask (Readarr's).
  final VoidCallback? onAskService;

  @override
  ConsumerState<MediaFindLibraryBody<T>> createState() =>
      _MediaFindLibraryBodyState<T>();
}

class _MediaFindLibraryBodyState<T>
    extends ConsumerState<MediaFindLibraryBody<T>> {
  /// The index of the list it was built from: a keystroke searches it, and
  /// only a new library builds another.
  FindIndex<T>? _index;
  List<T>? _indexed;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final configured = ref.watch(
      currentSettingsProvider.select((s) => s.isServiceConfigured(service)),
    );
    if (!configured) return NotConfiguredPlaceholder.forService(service);
    final library = ref.watch(widget.library);
    if (!library.hasValue) {
      if (library.hasError) {
        return AppErrorState(
          error: library.error!,
          service: service,
          instanceId: ref.watch(activeInstanceProvider(service))?.id,
          onRetry: () => ref.invalidate(widget.library),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final items = library.requireValue;
    if (_index == null || !identical(items, _indexed)) {
      _indexed = items;
      _index = FindIndex<T>(items, widget.namesOf);
    }
    final found = _index!.find(widget.query);
    if (found.isEmpty) {
      final asked = widget.query.trim();
      final ask = widget.onAskService;
      final name = watchConnectionName(ref, service);
      return ListView(
        padding: findListPadding(context),
        children: [
          SearchNothing(
            title: 'Nothing in your library called “$asked”',
            message: ask == null ? null : '${service.title} can look further.',
            action: ask == null
                ? null
                : OutlinedButton.icon(
                    onPressed: ask,
                    icon: const Icon(Icons.search_rounded),
                    label: Text('Search $name for “$asked”'),
                  ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: findListPadding(context),
      itemCount: found.length + 1,
      itemBuilder: (context, index) => index == 0
          ? SearchHeading(widget.heading(found.length), top: AppSpacing.lg)
          : widget.rowOf(context, found[index - 1]),
    );
  }
}

/// What a library wall's search of its service draws: the rows of its lookup
/// under a heading that counts them, `Asking Radarr` over plates while it is
/// asked, the service's own failure state when it did not answer, and a line
/// when it found nothing.
class MediaFindLookupBody<T> extends ConsumerWidget {
  const MediaFindLookupBody({
    super.key,
    required this.query,
    required this.results,
    required this.service,
    required this.heading,
    required this.rowOf,
  });

  /// What was asked, as the field holds it once typing has paused.
  final String query;

  /// The wall's lookup: null for an empty query.
  final FutureProvider<List<T>?> results;

  final ServiceKey service;
  final String Function(int count) heading;
  final Widget Function(BuildContext context, T item) rowOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select((s) => s.isServiceConfigured(service)),
    );
    if (!configured) return NotConfiguredPlaceholder.forService(service);
    final name = watchConnectionName(ref, service);
    final answer = ref.watch(results);
    // Asked again after an add, the rows stay where they are while it is: a
    // new question (the words changed) shows the plates.
    if (answer.isLoading && !answer.isRefreshing) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          ExcludeSemantics(
            child: SearchHeading('Asking $name', top: AppSpacing.lg),
          ),
          SearchRowsPending(label: 'Asking $name', rows: 4),
        ],
      );
    }
    if (answer.hasError) {
      return AppErrorState(
        error: answer.error!,
        service: service,
        instanceId: ref.watch(activeInstanceProvider(service))?.id,
        serviceName: name,
        onRetry: () => ref.invalidate(results),
      );
    }
    final rows = answer.value ?? <T>[];
    if (rows.isEmpty) {
      return ListView(
        children: [
          SearchNothing(
            icon: Icons.search_rounded,
            title: '$name found nothing called “${query.trim()}”',
          ),
        ],
      );
    }
    return ListView.builder(
      padding: findListPadding(context),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) => index == 0
          ? SearchHeading(heading(rows.length), top: AppSpacing.lg)
          : rowOf(context, rows[index - 1]),
    );
  }
}
