import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';

/// Where a wall's search looks: in what the library already holds, or by
/// asking the service.
enum MediaFindScope {
  /// Instant, local, no network. The default.
  library,

  /// The service's own lookup, on request.
  service,
}

/// What a library wall gives [MediaBrowseScaffold] to find with: while the
/// field holds text, the body under it is the wall's own, and where the wall
/// has a service to ask (every wall but Readarr's) a segmented control under
/// the field chooses the [MediaFindScope] first. The scaffold owns the chrome
/// (the field, the control, the scope that survives the text, Cancel and
/// Back); the wall owns what the results are, because a result is not the
/// wall's item (Lidarr's wall finds artists and albums).
@immutable
class MediaFind {
  /// A wall with a library to find in and a service to ask.
  const MediaFind({
    required StateProvider<MediaFindScope> this.scopeProvider,
    required this.libraryBody,
    required Widget Function(BuildContext context, String query)
    this.serviceBody,
    this.serviceLabel,
  });

  /// A wall with only its library to find in: its service has nothing to ask
  /// (Readarr's metadata host no longer answers), so there is no second scope
  /// and no control.
  const MediaFind.libraryOnly({required this.libraryBody})
    : scopeProvider = null,
      serviceBody = null,
      serviceLabel = null;

  /// Whether there is a second scope: a service to ask.
  bool get hasService => scopeProvider != null;

  /// The chosen scope. A provider rather than the scaffold's own state, so a
  /// link into the wall (Discover's `Show all music for …`) can arrive on the
  /// service scope. The scaffold sets it back to [MediaFindScope.library]
  /// when the field is emptied: the next search starts in the library. Null
  /// for a wall with only its library.
  final StateProvider<MediaFindScope>? scopeProvider;

  /// The second segment's label: the connection's name. The scaffold's
  /// `serviceName` when null.
  final String? serviceLabel;

  /// The library's results for the text as typed, with no debounce: matching
  /// what is already in hand costs nothing.
  final Widget Function(BuildContext context, String query) libraryBody;

  /// The service's results for the query once typing has paused (the same
  /// 400ms every lookup waits).
  /// Null for a wall with only its library.
  final Widget Function(BuildContext context, String query)? serviceBody;
}

/// The two scopes as a segmented control, under the field: `Your library` and
/// the service. Two cells on the quiet fill; the chosen one on the strong fill
/// with an edge, a 44pt cell each.
class MediaFindScopeControl extends StatelessWidget {
  const MediaFindScopeControl({
    super.key,
    required this.serviceLabel,
    required this.selected,
    required this.onSelected,
  });

  /// What the library segment reads.
  static const libraryLabel = 'Your library';

  final String serviceLabel;
  final MediaFindScope selected;
  final ValueChanged<MediaFindScope> onSelected;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: room.fillQuiet,
          borderRadius: AppRadius.borderRadiusPill,
          border: Border.all(color: room.hair),
        ),
        child: Row(
          spacing: 2,
          children: [
            for (final (scope, label) in [
              (MediaFindScope.library, libraryLabel),
              (MediaFindScope.service, serviceLabel),
            ])
              Expanded(
                child: _Cell(
                  label: label,
                  selected: scope == selected,
                  onTap: () => onSelected(scope),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusPill,
        child: Container(
          constraints: const BoxConstraints(minHeight: DesignTokens.sizeTouch),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? room.fillStrong : null,
            borderRadius: AppRadius.borderRadiusPill,
            border: Border.all(
              color: selected ? room.edge : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppType.label.copyWith(
              color: selected ? room.ink : room.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
