import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/media/presentation/issue_files_provider.dart';

/// The title an issue is about, at the head of its page: poster, name, and
/// where in it the problem is. Tapped whole, it opens the title's own page.
class IssueTitleCard extends StatelessWidget {
  const IssueTitleCard({
    super.key,
    required this.title,
    required this.sub,
    required this.posterUrl,
    required this.heroTag,
    this.onTap,
  });

  final String title;

  /// `Movie · 2012 · on your server`, `S2 E3 · The Second Cycle`.
  final String sub;
  final String? posterUrl;
  final String heroTag;

  /// Opens the title; null while the issue names none.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final body = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.row,
      ),
      decoration: BoxDecoration(
        color: room.door,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 60,
            child: MediaPosterCard(
              heroTag: heroTag,
              imageUrl: posterUrl,
              borderRadius: BorderRadius.circular(AppRadius.thumb),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.row.copyWith(color: room.ink)),
                Text(
                  sub,
                  style: AppType.meta
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkSecondary),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: room.inkTertiary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        container: true,
        label: '$title, $sub',
        excludeSemantics: true,
        child: body,
      );
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: '$title, $sub',
      semanticHint: 'Opens its page',
      excludeChildSemantics: true,
      child: body,
    );
  }
}

/// A line of the page that says what a control does or who reads it, in the
/// quiet ink: the caption under a composer or a button.
class IssueCaption extends StatelessWidget {
  const IssueCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      text,
      style: AppType.caption
          .weight(FontWeight.w400)
          .copyWith(color: CupolaRoom.of(context).inkTertiary),
    ),
  );
}

/// What a reply's menu offers.
enum IssueReplyAction { edit, delete }

/// One message of the conversation. [own] is the reader's: it reads `You`,
/// on a plate a step brighter, and may carry a menu ([menu]) to edit or
/// delete it.
///
/// The words are one sentence to a screen reader (`Luca, today 08:12: The
/// normal one.`); the menu stays its own control.
class IssueReplyBubble extends StatelessWidget {
  const IssueReplyBubble({
    super.key,
    required this.author,
    required this.when,
    required this.text,
    this.own = false,
    this.menu,
  });

  /// `You` for one's own, the person's name otherwise.
  final String author;
  final String when;
  final String text;
  final bool own;

  /// The ⋯ of one's own reply; null for anybody else's.
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final initial = author.isEmpty ? '?' : author.characters.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: own ? room.fillControl : room.fillStrong,
              border: Border.all(color: room.edge),
            ),
            child: own
                ? Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: room.inkSecondary,
                  )
                : Text(
                    initial.toUpperCase(),
                    style: AppType.label.copyWith(color: room.ink),
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 20),
                child: Row(
                  children: [
                    Flexible(
                      child: ExcludeSemantics(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          children: [
                            Text(
                              author,
                              style: AppType.label.copyWith(color: room.ink),
                            ),
                            Text(
                              when,
                              style: AppType.caption
                                  .weight(FontWeight.w400)
                                  .copyWith(color: room.inkTertiary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (menu != null) ...[const Spacer(), menu!],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                container: true,
                label: '$author, $when: $text',
                excludeSemantics: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.row,
                  ),
                  decoration: BoxDecoration(
                    color: own ? room.fillControl : room.fillQuiet,
                    border: Border.all(color: room.hair),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: Text(
                    text,
                    style: AppType.body.copyWith(color: room.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The ⋯ of one's own reply: `Edit reply` and `Delete reply`, each as the
/// gate says. A dimmed one stays in the menu with its reason as the hint and,
/// chosen, as the toast; an absent one is not offered.
class IssueReplyMenu extends StatelessWidget {
  const IssueReplyMenu({
    super.key,
    required this.edit,
    required this.delete,
    required this.onSelected,
  });

  final GateVerdict edit;
  final GateVerdict delete;
  final ValueChanged<IssueReplyAction> onSelected;

  @override
  Widget build(BuildContext context) {
    if (edit is Absent && delete is Absent) return const SizedBox.shrink();
    final room = CupolaRoom.of(context);
    Widget label(GateVerdict verdict, IconData icon, String text) =>
        GatedAffordance.annotateFor(
          enabled: verdict.acts,
          hint: verdict.reason,
          child: Row(
            children: [
              Icon(icon, size: 20, color: room.ink),
              const SizedBox(width: AppSpacing.md),
              Text(text, style: AppType.row.copyWith(color: room.ink)),
            ],
          ),
        );
    return PopupMenuButton<IssueReplyAction>(
      tooltip: 'Edit or delete your reply',
      position: PopupMenuPosition.under,
      // A 44pt target in the 20pt line, without growing it.
      padding: EdgeInsets.zero,
      iconSize: 20,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(DesignTokens.sizeTouch),
        visualDensity: VisualDensity.standard,
      ),
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: room.inkSecondary),
      onSelected: (action) {
        final verdict = action == IssueReplyAction.edit ? edit : delete;
        if (verdict.acts) {
          onSelected(action);
        } else if (verdict.reason case final reason?) {
          SnackBarHelper.info(context, reason);
        }
      },
      itemBuilder: (context) => [
        if (edit is! Absent)
          PopupMenuItem(
            value: IssueReplyAction.edit,
            child: label(edit, Icons.edit_outlined, 'Edit reply'),
          ),
        if (delete is! Absent)
          PopupMenuItem(
            value: IssueReplyAction.delete,
            child: label(delete, Icons.delete_outline_rounded, 'Delete reply'),
          ),
      ],
    );
  }
}

/// Editing one's own reply where it stands: a field holding the words,
/// `Cancel` and `Save`.
class IssueReplyEditor extends StatelessWidget {
  const IssueReplyEditor({
    super.key,
    required this.controller,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;

  /// The save is out: the button keeps its look and ignores a second tap.
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: room.fillControl,
              border: Border.all(color: room.edge),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 20,
              color: room.inkSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Editing your reply',
                style: AppType.label.copyWith(color: room.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(hintText: 'Your reply'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(0, DesignTokens.sizeTouch),
                      ),
                      // Sending keeps the look and ignores the tap: a button
                      // with no handler would draw as disabled.
                      onPressed: saving ? () {} : onSave,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the reader answers: a field and a send button, as the gate says.
///
/// [Dimmed] keeps both, drained, as one 44pt+ target that answers a tap with
/// the reason; [Absent] is not drawn. While a reply is out, send keeps its
/// look and ignores a second tap, and the words stay in the field until the
/// server has taken them.
class IssueComposer extends StatelessWidget {
  const IssueComposer({
    super.key,
    required this.label,
    required this.controller,
    required this.verdict,
    required this.sending,
    required this.onSend,
  });

  /// `Reply to Luca`, `Add a detail`: the field's hint and its name.
  final String label;
  final TextEditingController controller;
  final GateVerdict verdict;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget row({required bool live}) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: live,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: label,
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _SendButton(
          sending: sending,
          // Dimmed: the whole composer is the one target.
          onTap: live ? onSend : null,
          room: room,
        ),
      ],
    );
    return RoleGatedAction.builder(
      verdict: verdict,
      onTap: onSend,
      builder: (context, onPressed, annotate) {
        if (verdict.acts) return row(live: true);
        return PressableScale(
          onTap: onPressed,
          semanticLabel: label,
          semanticHint: verdict.reason,
          excludeChildSemantics: true,
          haptic: false,
          child: annotate(IgnorePointer(child: row(live: false))),
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.sending,
    required this.onTap,
    required this.room,
  });

  final bool sending;
  final VoidCallback? onTap;
  final CupolaRoom room;

  @override
  Widget build(BuildContext context) {
    final glyph = sending
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: room.inkSecondary,
            ),
          )
        : Icon(Icons.send_rounded, size: 22, color: room.ink);
    final plate = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: room.fillControl,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: room.edge),
      ),
      child: Center(child: glyph),
    );
    if (onTap == null) return plate;
    return Semantics(
      container: true,
      button: true,
      label: 'Send reply',
      child: PressableScale(onTap: sending ? () {} : onTap, child: plate),
    );
  }
}

/// One file the arrs hold that the problem could be about: its quality and
/// size, its name in the mono face, and which connection holds it and when it
/// came. Tapped whole, it opens the title's page, where the file is managed.
class IssueFileRow extends StatelessWidget {
  const IssueFileRow({
    super.key,
    required this.file,
    required this.now,
    required this.onTap,
  });

  final IssueFile file;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final imported = file.importedAt;
    final day = imported == null
        ? null
        : switch (formatPastDay(imported, now: now)) {
            null => 'today',
            final past => past,
          };
    final line = [
      file.connectionName,
      if (day != null) 'imported $day',
    ].join(dotSeparator);
    final headline = file.headline.isEmpty ? file.fileName : file.headline;
    final spoken = [
      headline,
      if (file.headline.isNotEmpty) file.fileName,
      line,
    ].join('. ');
    return PressableScale(
      onTap: onTap,
      semanticLabel: spoken,
      semanticHint: 'Opens its page',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: room.fillQuiet,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  file.episode ? Icons.tv_outlined : Icons.movie_outlined,
                  size: 19,
                  color: room.inkSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                    if (file.headline.isNotEmpty)
                      // Whole, as the arr wrote it: a name that is cut is a
                      // different name.
                      Text(
                        file.fileName,
                        style: AppType.mono.copyWith(color: room.inkTertiary),
                      ),
                    Text(
                      line,
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: room.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
