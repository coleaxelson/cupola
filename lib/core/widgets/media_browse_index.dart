import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/theme.dart';

/// The A–Z strip on the right edge of a lettered wall: tap or drag on it and
/// the wall jumps to that letter's section.
///
/// **One adjustable control.** The letters are not 27 buttons: the strip is
/// `Jump to letter`, its value the letter last jumped to, and a screen reader
/// moves it with increment and decrement, one present letter at a time.
///
/// **A letter with no section is dimmed and is not a target.** A finger on it
/// lands on the nearest present letter at or after it (or the last one, when
/// none follows), so every position on the strip does something and no
/// position promises a section the wall does not have. Letters are `A`–`Z`
/// with `#` first, which is where the wall heads a digit or anything that is
/// not a Latin letter (it sorts before the letters): the strip runs in the
/// wall's own order, so dragging down is always scrolling down.
///
/// **Larger text collapses it, the way iOS does.** The letters take their
/// line height at the reading size; when all 27 no longer fit the strip's
/// height, every other slot is a dot for the letters left out. Dragging still
/// reaches every present letter, because a position on the strip means the
/// same letter whether or not that letter is drawn.
///
/// **While a finger is down** the letter it landed on shows large in a bubble
/// to the left of the strip, centred on that letter, and a selection haptic
/// fires on each letter change on iOS and Android.
///
/// It paints only inside its own box (28 wide) and the bubble beside it; the
/// wall gives it the margin it needs ([width]) so no tile sits under it.
class MediaBrowseIndex extends StatefulWidget {
  const MediaBrowseIndex({
    super.key,
    required this.present,
    required this.onJump,
  });

  /// The letters (as [letters] spells them) the wall has a section for.
  final Set<String> present;

  /// A letter in [present] was chosen: the wall jumps to its section.
  final ValueChanged<String> onJump;

  /// The strip's width, and the margin the wall gives up on its right while the
  /// strip shows.
  static const double width = 28;

  /// The bubble's diameter.
  static const double bubbleSize = 72;

  /// Between the bubble and the strip.
  static const double bubbleGap = AppSpacing.lg + AppSpacing.sm;

  /// The fewest titles a wall has before it grows a strip.
  ///
  /// Forty is about fourteen rows of three: a few screens of wall. Under that
  /// the whole wall is a flick away and 27 letters beside it are furniture;
  /// over it, a letter is quicker than a long scroll. A wall that gets here
  /// by a chip (Wanted) counts what that chip shows.
  static const int minTitles = 40;

  /// The strip, top to bottom, in the order of the wall's sections.
  static const List<String> letters = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  /// The letter a finger [fraction] of the way down the strip (0 at the top,
  /// 1 at the bottom) lands on: the nearest one in [present] at or after the
  /// letter under it, or the last one when none follows. Null when [present]
  /// is empty.
  @visibleForTesting
  static String? letterAt(double fraction, Set<String> present) {
    final under = (fraction * letters.length).floor().clamp(
      0,
      letters.length - 1,
    );
    for (var index = under; index < letters.length; index++) {
      if (present.contains(letters[index])) return letters[index];
    }
    for (var index = under - 1; index >= 0; index--) {
      if (present.contains(letters[index])) return letters[index];
    }
    return null;
  }

  /// Which of the 27 letters are drawn in [height] when each takes [cell]: all
  /// of them when they fit, otherwise evenly spread ones with a dot between
  /// each pair (so at most `2k - 1` slots for the `k` letters), always
  /// including `#`, `A` and `Z`. The indexes into [letters].
  @visibleForTesting
  static List<int> drawnIndexes(double height, double cell) {
    if (height >= letters.length * cell) {
      return List<int>.generate(letters.length, (index) => index);
    }
    final slots = (height / cell).floor();
    final count = math.max(2, (slots + 1) ~/ 2);
    if (count == 2) return [0, letters.length - 1];
    // `#` and then `count - 1` letters spread from `A` to `Z`.
    return [
      0,
      for (var i = 0; i < count - 1; i++)
        1 + (i * (letters.length - 2) / (count - 2)).round(),
    ];
  }

  @override
  State<MediaBrowseIndex> createState() => _MediaBrowseIndexState();
}

class _MediaBrowseIndexState extends State<MediaBrowseIndex> {
  /// The letter last jumped to, which is the control's value.
  String? _current;

  /// The letter under the finger while it is down, for the bubble.
  String? _touching;

  /// The strip's height, as last laid out: a drag position is a fraction of it.
  double _height = 0;

  String? get _value => _current ?? _firstPresent;

  String? get _firstPresent {
    for (final letter in MediaBrowseIndex.letters) {
      if (widget.present.contains(letter)) return letter;
    }
    return null;
  }

  void _touch(double dy) {
    if (_height <= 0) return;
    final letter = MediaBrowseIndex.letterAt(dy / _height, widget.present);
    if (letter == null || letter == _touching) return;
    _fire(letter);
    setState(() {
      _touching = letter;
      _current = letter;
    });
  }

  void _release() {
    if (_touching == null) return;
    setState(() => _touching = null);
  }

  /// Moves the control one present letter [by] (+1 or -1), as a screen
  /// reader's increment and decrement do.
  void _step(int by) {
    final present = [
      for (final letter in MediaBrowseIndex.letters)
        if (widget.present.contains(letter)) letter,
    ];
    if (present.isEmpty) return;
    final at = present.indexOf(_value ?? present.first);
    final next = present[(at + by).clamp(0, present.length - 1)];
    if (next == _current) return;
    widget.onJump(next);
    setState(() => _current = next);
  }

  void _fire(String letter) {
    widget.onJump(letter);
    // Only the two platforms with a taptic engine to speak of.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final style = Theme.of(context).textTheme.labelSmall!;
    final cell = _cellHeight(context, style);
    final value = _value;
    final present = [
      for (final letter in MediaBrowseIndex.letters)
        if (widget.present.contains(letter)) letter,
    ];
    final at = value == null ? -1 : present.indexOf(value);

    return Semantics(
      container: true,
      excludeSemantics: true,
      slider: true,
      label: 'Jump to letter',
      value: value,
      increasedValue: at >= 0 && at < present.length - 1
          ? present[at + 1]
          : null,
      decreasedValue: at > 0 ? present[at - 1] : null,
      onIncrease: at >= 0 && at < present.length - 1 ? () => _step(1) : null,
      onDecrease: at > 0 ? () => _step(-1) : null,
      child: SizedBox(
        width: MediaBrowseIndex.width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            _height = height;
            final drawn = MediaBrowseIndex.drawnIndexes(height, cell);
            final band = height / MediaBrowseIndex.letters.length;
            double centreOf(int index) => (index + 0.5) * band;
            // Where each drawn letter sits: over its own band, but never
            // closer to the one above than a line. When letters are left out
            // `#` and `A` are still neighbours, one band apart and less than a
            // line, so `A` is nudged down to clear `#`.
            final centres = <double>[];
            for (final index in drawn) {
              final own = centreOf(index);
              centres.add(
                centres.isEmpty ? own : math.max(own, centres.last + cell),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Down, not tap: a letter answers the moment the finger
                      // lands, and goes on answering as it moves.
                      onVerticalDragDown: (details) =>
                          _touch(details.localPosition.dy),
                      onVerticalDragUpdate: (details) =>
                          _touch(details.localPosition.dy),
                      onVerticalDragEnd: (_) => _release(),
                      onVerticalDragCancel: _release,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                for (final (position, index) in drawn.indexed) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: centres[position] - cell / 2,
                    height: cell,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          MediaBrowseIndex.letters[index],
                          maxLines: 1,
                          softWrap: false,
                          style: style.copyWith(
                            color:
                                widget.present.contains(
                                  MediaBrowseIndex.letters[index],
                                )
                                ? room.ink
                                : room.inkDisabled,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The letters left out between this one and the next.
                  if (position < drawn.length - 1 &&
                      drawn[position + 1] - index > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      top:
                          (centres[position] + centres[position + 1]) / 2 -
                          cell / 2,
                      height: cell,
                      child: IgnorePointer(
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: room.inkTertiary,
                            ),
                            child: const SizedBox.square(dimension: 3),
                          ),
                        ),
                      ),
                    ),
                ],
                if (_touching case final letter?)
                  Positioned(
                    right: MediaBrowseIndex.width + MediaBrowseIndex.bubbleGap,
                    top: _bubbleTop(
                      centreOf(MediaBrowseIndex.letters.indexOf(letter)),
                      height,
                    ),
                    width: MediaBrowseIndex.bubbleSize,
                    height: MediaBrowseIndex.bubbleSize,
                    child: _Bubble(letter: letter),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The bubble's top: centred on its letter, kept inside the strip's height
  /// where the strip is tall enough to hold it.
  static double _bubbleTop(double centre, double height) {
    final top = centre - MediaBrowseIndex.bubbleSize / 2;
    final lowest = math.max(0.0, height - MediaBrowseIndex.bubbleSize);
    return top.clamp(0.0, lowest);
  }

  /// One letter's line at the reading size, measured.
  static double _cellHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

/// The letter under the finger, large, to its left.
///
/// Decoration: the letter is already the strip's spoken value, so the bubble
/// says nothing. Its glyph ignores the reading size: a 36pt letter in a 72pt
/// disc is the whole of its design, and at twice the size it would not fit it.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: MediaQuery.withNoTextScaling(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: room.menu,
              border: Border.all(color: room.edge),
              boxShadow: AppElevation.float(Theme.of(context).colorScheme),
            ),
            child: Center(
              child: Text(
                letter,
                style: AppType.screen.copyWith(color: room.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
