import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/count_format.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';

/// Whether a library is in selection mode, for the chrome that has to step
/// aside while it is.
///
/// A wall that selects ([LibrarySelectionController.claim]) takes the floating
/// navigation bar's place on a phone and the service's band and tab bar from
/// the top, and none of those is the wall's to hide: they are drawn above the
/// navigator the wall lives in. They ask [LibrarySelectionScope] instead, so
/// the wall never reaches into the shell, and the shell never learns which
/// library it is.
///
/// One owner at a time: the wall that claimed it. A second claim (another
/// tab's wall, kept alive offstage) never happens, because a wall that is not
/// on screen ends its selection.
class LibrarySelectionController extends ChangeNotifier {
  Object? _owner;
  VoidCallback? _onCancel;
  var _disposed = false;

  /// A library is selecting.
  bool get isSelecting => _owner != null;

  /// [owner] is selecting now. [onCancel] is what ends its selection when
  /// something outside it asks (a Back that belongs to a route above the wall).
  void claim(Object owner, {VoidCallback? onCancel}) {
    _onCancel = onCancel;
    if (identical(_owner, owner)) return;
    _owner = owner;
    _signal();
  }

  /// Asks the library that is selecting to end its selection. Nothing when none
  /// is, and nothing while it has a write out: that is its own to refuse.
  void cancel() => _onCancel?.call();

  /// [owner] is done. A release by anyone but the owner is no word at all.
  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onCancel = null;
    _signal();
  }

  /// Tells the listeners, outside a frame: a wall that is torn down releases
  /// from `dispose`, which runs while the tree is locked, and a listener is
  /// free to mark itself dirty.
  void _signal() {
    // The window may be gone before the wall that was selecting in it.
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Hands [controller] to everything under it: the shell holds one for the
/// window, and the library wall, the navigation bar and a service's band
/// find it here.
///
/// Optional everywhere: no scope means no shell to coordinate with (a wall
/// under test, a screen outside the shell), and the wall selects on its own.
class LibrarySelectionScope
    extends InheritedNotifier<LibrarySelectionController> {
  const LibrarySelectionScope({
    super.key,
    required LibrarySelectionController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The window's controller, or null outside a shell. Not a dependency: the
  /// wall that claims it does not rebuild when someone else's claim moves.
  static LibrarySelectionController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibrarySelectionScope>()?.notifier;

  /// Whether a library is selecting, as a dependency: the caller is built
  /// again when that changes.
  static bool selectingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LibrarySelectionScope>()
          ?.notifier
          ?.isSelecting ??
      false;
}

/// Back, for a route above the wall: while a library selects, the route this
/// is in cannot be popped, by the swipe or by the key, and Back ends the
/// selection instead.
///
/// A wall's own `PopScope` belongs to the nearest route, which for a library
/// inside a service's tabs is a route of the tabs' nested navigator; the swipe
/// is the gesture of the outer route that holds the whole service page, and
/// never asks anything under the inner navigator. So the page puts this above
/// its navigator, where that route's `popDisposition` can hear it.
class LibrarySelectionBackGuard extends StatelessWidget {
  const LibrarySelectionBackGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !LibrarySelectionScope.selectingOf(context),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) LibrarySelectionScope.maybeOf(context)?.cancel();
    },
    child: child,
  );
}

/// How long the bars take to change places: the room's one standard
/// duration, and under Reduce Motion a fade of [AppAnimation.reducedFade].
Duration _swapDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AppAnimation.reducedFade
    : AppAnimation.standard;

/// One of the two floating bars: slides down out of sight while [shown] is
/// false and up into place while it is true, over `motion.standard`, and
/// under Reduce Motion fades over 150 ms instead.
///
/// The navigation bar and the selection bar are two of these with opposite
/// [shown], so one goes down while the other comes up. A hidden bar keeps its
/// place in the layout (the shell's bottom slot does not change size, and the
/// page above it does not move), takes no touch and says nothing to a screen
/// reader.
///
/// [holdsLast] is for a bar that is built only while it has something to say
/// (the selection bar, whose counts are gone with the selection): it keeps
/// drawing the last [child] it was given until it has gone, then draws
/// nothing at all. [enters] plays the entrance when the bar is first built
/// shown.
class LibrarySelectionSwap extends StatefulWidget {
  const LibrarySelectionSwap({
    super.key,
    required this.shown,
    required this.child,
    this.holdsLast = false,
    this.enters = false,
  });

  final bool shown;
  final Widget child;
  final bool holdsLast;
  final bool enters;

  @override
  State<LibrarySelectionSwap> createState() => _LibrarySelectionSwapState();
}

class _LibrarySelectionSwapState extends State<LibrarySelectionSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.shown && !widget.enters ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: AppAnimation.standardCurve,
  );

  /// The child the bar last drew shown, kept for its way out.
  Widget? _held;

  @override
  void initState() {
    super.initState();
    _held = widget.shown ? widget.child : null;
    _controller.addStatusListener(_settled);
  }

  var _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _swapDuration(context);
    if (!_entered && widget.shown && widget.enters) _controller.forward();
    _entered = true;
  }

  @override
  void didUpdateWidget(LibrarySelectionSwap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown) _held = widget.child;
    if (widget.shown == oldWidget.shown) return;
    _controller.duration = _swapDuration(context);
    if (widget.shown) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  /// Once the bar is gone, a held child is let go.
  void _settled(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.holdsLast && mounted) {
      setState(() => _held = null);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.holdsLast ? _held : widget.child;
    if (child == null) return const SizedBox.shrink();
    final fades = MediaQuery.disableAnimationsOf(context);
    final bar = fades
        ? FadeTransition(opacity: _controller, child: child)
        : AnimatedBuilder(
            animation: _curve,
            child: child,
            // Its own height down and back: out of the screen's foot, and
            // nothing of it left at the edge.
            builder: (context, child) => FractionalTranslation(
              translation: Offset(0, 1 - _curve.value),
              child: child,
            ),
          );
    return IgnorePointer(
      ignoring: !widget.shown,
      child: ExcludeSemantics(excluding: !widget.shown, child: bar),
    );
  }
}

/// The navigation bar, which steps down while a library selects and comes
/// back when it is done: [child] is the bar as the shell builds it.
class LibrarySelectionNavSlot extends StatelessWidget {
  const LibrarySelectionNavSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LibrarySelectionSwap(
    shown: !LibrarySelectionScope.selectingOf(context),
    child: child,
  );
}

/// Chrome that is not the wall's to remove, faded out while a library selects
/// and back when it is done: a service's band and tab bar, which the header of
/// the selection stands in for. Takes no touch and says nothing while hidden.
class LibrarySelectionHide extends StatelessWidget {
  const LibrarySelectionHide({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hidden = LibrarySelectionScope.selectingOf(context);
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: _swapDuration(context),
          curve: AppAnimation.standardCurve,
          child: child,
        ),
      ),
    );
  }
}

/// The disc over a tile in selection mode: filled ink with a check when the
/// tile is selected, an empty ring when it is not.
///
/// Decoration only: the tile itself says whether it is selected.
class LibrarySelectionMark extends StatelessWidget {
  const LibrarySelectionMark({
    super.key,
    required this.selected,
    this.size = 28,
  });

  final bool selected;
  final double size;

  /// The ring's width, and the collar of the filled disc.
  static const double _edge = 2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: _swapDuration(context),
        curve: AppAnimation.standardCurve,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? colorScheme.primary
              : room.ground.withValues(alpha: 0.6),
          border: Border.all(
            color: selected ? room.ground : room.inkSecondary,
            width: _edge,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: size * 0.6,
                color: colorScheme.onPrimary,
              )
            : null,
      ),
    );
  }
}

/// The top of the wall in selection mode: `Cancel`, how many are selected,
/// and `Select all 34`.
///
/// The count is a live region, so a screen reader hears it change as tiles are
/// toggled. Titles a chip hides stay selected and are counted: [hidden] says
/// how many, and the chip that hides them ([hiddenBy]).
class LibrarySelectionHeader extends StatelessWidget {
  const LibrarySelectionHeader({
    super.key,
    required this.selected,
    required this.shown,
    required this.hidden,
    required this.hiddenBy,
    required this.allSelected,
    required this.onCancel,
    required this.onToggleAll,
  });

  /// How many titles are selected, shown or not.
  final int selected;

  /// How many titles the current chip and sort show: what `Select all` takes.
  final int shown;

  /// How many of the selected titles the chip hides.
  final int hidden;

  /// The chip that hides them, as it reads (`Wanted`).
  final String hiddenBy;

  /// Every title that is shown is selected.
  final bool allSelected;

  final VoidCallback onCancel;
  final VoidCallback onToggleAll;

  /// `3 selected`, or `None selected`.
  String get count =>
      selected == 0 ? 'None selected' : '${formatCount(selected)} selected';

  /// `1 hidden by Wanted`, or null when the chip hides none of them.
  String? get hiddenLine =>
      hidden == 0 ? null : '${formatCount(hidden)} hidden by $hiddenBy';

  /// What the toggle reads: `Select all 34`, and `Deselect all` once they are.
  String get toggle =>
      allSelected ? 'Deselect all' : 'Select all ${formatCount(shown)}';

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final textTheme = Theme.of(context).textTheme;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

    Widget button(String label, VoidCallback onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: room.inkSecondary,
        // Pinned: the desktop's compact density takes 8 off `minimumSize`.
        visualDensity: VisualDensity.standard,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        textStyle: AppType.label,
      ),
      child: Text(label),
    );

    final title = Semantics(
      liveRegion: true,
      container: true,
      label: [count, ?hiddenLine].join(', '),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              count,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge!.weight(FontWeight.w600),
            ),
            if (hiddenLine case final line?)
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(color: room.inkSecondary),
              ),
          ],
        ),
      ),
    );

    final cancel = button('Cancel', onCancel);
    final toggleAll = shown == 0 ? null : button(toggle, onToggleAll);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: stacked
            // At a large reading size the count goes under the two verbs:
            // beside them it was left a few letters.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [cancel, ?toggleAll],
                  ),
                  title,
                ],
              )
            : Row(
                children: [
                  cancel,
                  Expanded(child: Center(child: title)),
                  // Keeps the count centred when there is nothing to toggle.
                  toggleAll ?? const SizedBox(width: 44),
                ],
              ),
      ),
    );
  }
}

/// One action on the selection bar: a glyph over its name.
@immutable
class LibrarySelectionBarAction {
  const LibrarySelectionBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// The selection bar: the navigation bar's glass and anatomy (a glyph over its
/// name, four columns of one width), holding the actions on what is selected.
///
/// [label] is what the toolbar is to a screen reader (`3 artists selected`).
///
/// With [dimmed] (nothing selected) the actions are quiet but still
/// tappable, and carry [dimmedHint] as their hint: a tap says why it did
/// nothing, so there is never a control that fails without a word. While an
/// action is out ([busy] names it) it shows its progress and the others take
/// no tap.
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({
    super.key,
    required this.label,
    required this.actions,
    this.dimmed = false,
    this.dimmedHint,
    this.busy,
  });

  final String label;
  final List<LibrarySelectionBarAction> actions;
  final bool dimmed;
  final String? dimmedHint;

  /// The action in flight, by its position in [actions].
  final int? busy;

  /// The glyph's size, the navigation bar's.
  static const double iconSize = 20;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: FloatingBarSurface(
        surfaceKey: const ValueKey('library-selection-bar'),
        builder: (context, pill) => Row(
          children: [
            for (final (index, action) in actions.indexed)
              Expanded(
                child: _BarAction(
                  action: action,
                  dimmed: dimmed,
                  hint: dimmed ? dimmedHint : null,
                  working: busy == index,
                  inert: busy != null && busy != index,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.action,
    required this.dimmed,
    required this.hint,
    required this.working,
    required this.inert,
  });

  final LibrarySelectionBarAction action;
  final bool dimmed;
  final String? hint;
  final bool working;
  final bool inert;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    // Quiet, not absent: the disabled ink, and a target as large as ever.
    final ink = dimmed || inert ? room.inkDisabled : colorScheme.onSurface;
    final scaler = FloatingNavBarMetrics.effectiveTextScaler(context);
    final onTap = working || inert ? null : action.onPressed;

    return Semantics(
      key: ValueKey('library-selection-${action.label.toLowerCase()}'),
      button: true,
      container: true,
      excludeSemantics: true,
      label: action.label,
      hint: working ? 'In progress' : hint,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: LibrarySelectionBar.iconSize,
                child: working
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onSurface,
                        ),
                      )
                    : Icon(
                        action.icon,
                        color: ink,
                        size: LibrarySelectionBar.iconSize,
                      ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: scaler,
                  style: Theme.of(context).textTheme.labelMedium!
                      .weight(FontWeight.w500)
                      .copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
