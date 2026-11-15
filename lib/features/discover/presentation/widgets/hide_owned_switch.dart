import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// "Hide what I have": one switch for the whole of Discover, on a catalogue
/// page and on the atrium.
///
/// The row is a phone's at most ([AppBreakpoints.splitList]), at the head of
/// a wider page: across a tablet or a desktop window the switch would sit a
/// thousand points from the words that say what it does.
///
/// [value] is null until the choice is known (the person's, or Seerr's
/// `hideAvailable` for one who never made it): the row keeps its height and
/// its words, the switch is laid out but not drawn and the row takes no tap. A switch
/// that flipped on its own after being drawn would say something the page
/// had not yet decided.
class HideOwnedSwitch extends StatelessWidget {
  const HideOwnedSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool? value;
  final ValueChanged<bool> onChanged;

  /// The row's floor.
  static const double minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final value = this.value;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Hide what I have',
                style: AppType.row
                    .weight(FontWeight.w500)
                    .copyWith(color: room.ink),
              ),
            ),
            if (value == null)
              // The real switch, laid out and drawn by nothing: its own
              // footprint on any platform's theme, so the row cannot move by
              // a pixel when it comes.
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Switch(value: false, onChanged: null),
              )
            else
              Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.splitList),
        child: value == null
            ? ExcludeSemantics(child: row)
            : MergeSemantics(
                child: InkWell(onTap: () => onChanged(!value), child: row),
              ),
      ),
    );
  }
}
