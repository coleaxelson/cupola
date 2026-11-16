import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/sheet_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_write_reach.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart'
    show SeerrAbility;
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/domain/media_series.dart'
    show MediaEpisodeFacts;
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/media_report_row.dart'
    show mediaReportFiledLine, reportAccountName;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Opens the sheet a problem is reported from, and once it is filed reads
/// the title's Seerr record and the Issues list again and says so
/// (`Problem reported`).
///
/// [season] and [episode] open it on that episode (0, every one). A title's
/// page opens it on the whole title.
Future<void> showReportProblemSheet(
  BuildContext context, {
  required MediaReportScope scope,
  required MediaReportSource source,
  int season = 0,
  int episode = 0,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final filed = await SheetUtils.showCupolaModalSheet<SeerrIssue>(
    context: context,
    // A form with a text field: a drag would fight its scroll, and the sheet
    // is closed by its own Close and the barrier, never while it sends.
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportProblemSheet(
      scope: scope,
      source: source,
      season: season,
      episode: episode,
    ),
  );
  if (filed == null) return;
  readReportsAgain(container, key: scope.key, connectionId: source.seerr.id);
  if (context.mounted) SnackBarHelper.success(context, 'Problem reported');
}

/// What went wrong with the last attempt to send, and so what the sheet says.
enum _Outcome { failed, signedOut, refused, gone }

/// The sheet a problem with a title is reported from: what is wrong, where
/// (a series' season and episode), and in the person's words.
///
/// Every failure is told in the sheet, and the draft survives each of them:
/// the type, the place and the words stay where they were.
class ReportProblemSheet extends ConsumerStatefulWidget {
  const ReportProblemSheet({
    super.key,
    required this.scope,
    required this.source,
    this.season = 0,
    this.episode = 0,
  });

  final MediaReportScope scope;
  final MediaReportSource source;
  final int season;
  final int episode;

  @override
  ConsumerState<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends ConsumerState<ReportProblemSheet> {
  final _text = TextEditingController();
  SeerrIssueType? _type;
  late int _season = widget.season > 0
      ? widget.season
      : widget.source.seasons.length == 1
      ? widget.source.seasons.single.number
      : 0;
  late int _episode = widget.season > 0 ? widget.episode : 0;

  /// Whether Submit was pressed once: the missing fields say so from then on.
  bool _tried = false;
  bool _sending = false;
  _Outcome? _outcome;
  Object? _error;

  /// The report may have reached the server and reading it back failed too:
  /// the failure cannot say that nothing was sent.
  bool _unsure = false;

  bool get _movie => widget.scope.key.isMovie;
  String get _connection => widget.source.seerr.id;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  SeerrIssueDraft get _draft => _movie
      ? SeerrIssueDraft.movie(
          type: _type,
          message: _text.text,
          mediaId: widget.source.mediaId,
        )
      : SeerrIssueDraft.series(
          type: _type,
          message: _text.text,
          mediaId: widget.source.mediaId,
          problemSeason: _season,
          problemEpisode: _episode,
        );

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _tried = true);
    final draft = _draft;
    if (!draft.isValid) return;
    setState(() {
      _sending = true;
      _outcome = null;
      _error = null;
      _unsure = false;
    });
    try {
      final filed = await ref
          .read(seerrServiceForProvider(_connection))
          .reportIssue(draft);
      if (mounted) Navigator.of(context).pop(filed);
    } catch (error) {
      if (!mounted) return;
      var unsure = false;
      if (seerrWriteMayHaveLanded(error)) {
        // Seerr takes no key that makes a second send harmless: what it holds
        // is read before the report is offered again.
        try {
          final held = await ref
              .read(seerrServiceForProvider(_connection))
              .findReportedIssue(
                draft,
                userId: ref.read(seerrActingUserIdProvider(_connection)),
                known: {for (final issue in widget.source.issues) issue.id},
              );
          if (!mounted) return;
          if (held != null) {
            Navigator.of(context).pop(held);
            return;
          }
        } catch (_) {
          unsure = true;
        }
        if (!mounted) return;
      }
      setState(() {
        _unsure = unsure;
        _sending = false;
        _error = error;
        _outcome = switch (seerrRefusalOf(error)) {
          SeerrRefusal.mediaGone => _Outcome.gone,
          SeerrRefusal.sessionEnded => _Outcome.signedOut,
          SeerrRefusal.endpointRefused ||
          SeerrRefusal.permissionDenied => _Outcome.refused,
          _ =>
            classifyConnectionFailure(error) ==
                    ServiceFailureReason.sessionEnded
                ? _Outcome.signedOut
                : _Outcome.failed,
        };
      });
    }
  }

  /// The way back into the account's form. The draft stays; the note goes,
  /// so a sheet seen again after signing in offers Submit.
  void _signIn() {
    FailureRemedy.forReason(
      ServiceKey.seerr,
      ServiceFailureReason.sessionEnded,
      instanceId: _connection,
    )?.open(context);
    setState(() {
      _outcome = null;
      _error = null;
    });
  }

  /// `Cosmos Laundromat · S2 E3`: the title, and the place the report names.
  String get _subtitle => [
    widget.source.title,
    if (_season > 0)
      _episode > 0
          ? formatEpisodeCode(_season, _episode)
          : formatSeasonCode(_season),
  ].where((part) => part.isNotEmpty).join(dotSeparator);

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final gate = ref.watch(roleGateProvider(_connection));
    var verdict = gate.reportIssueAction();
    // A refusal the server just made: the grant is read again, and until it
    // says so the control already stands as refused.
    if (_outcome == _Outcome.refused && verdict is Live) {
      verdict = Dimmed(
        gate.faultVoice == FaultVoice.brief
            ? RoleGateCopy.youCannot(SeerrAbility.reportIssue)
            : RoleGateCopy.accountCannot(
                SeerrAbility.reportIssue,
                server: _serverName(gate),
              ),
      );
    }
    final draft = _draft;
    final missingType =
        _tried && draft.problem == SeerrIssueDraftProblem.noType;
    final missingText = _tried && _text.text.trim().isEmpty;

    return PopScope(
      // A tap on the barrier, Back and Close wait for the answer.
      canPop: !_sending,
      child: AppBottomSheet(
        title: 'Report a problem',
        subtitle: _subtitle,
        showClose: true,
        bodyPadding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(
              "What's wrong?",
              top: 0,
              error: missingType ? "Choose what's wrong." : null,
            ),
            _Padded(
              MediaGroup(
                children: [
                  for (final type in SeerrIssueType.values)
                    _TypeRow(
                      type: type,
                      hint: _hintOf(type),
                      selected: _type == type,
                      onSelected: () => setState(() => _type = type),
                    ),
                ],
              ),
            ),
            if (!_movie && widget.source.seasons.isNotEmpty) ...[
              const _Label('Where'),
              _Padded(MediaGroup(children: _where())),
            ],
            const _Label('Describe it'),
            _Padded(
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText:
                      'What happens, and when? For example: the audio drifts '
                      'after 8 minutes.',
                  errorText: missingText ? 'Say what happens.' : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _foot(context, room, gate),
            const SizedBox(height: AppSpacing.lg),
            _Padded(_button(context, verdict)),
          ],
        ),
      ),
    );
  }

  String _serverName(RoleGate gate) => gate.server?.title ?? 'Seerr';

  /// The caption under the words, or what went wrong sending them.
  Widget _foot(BuildContext context, CupolaRoom room, RoleGate gate) {
    final scheme = Theme.of(context).colorScheme;
    final brief = gate.faultVoice == FaultVoice.brief;
    final stays = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg + AppSpacing.xl,
        0,
        AppSpacing.lg,
        0,
      ),
      child: Text(
        // Reading it back failed as well: nothing here says it was not sent.
        _unsure
            ? 'Your report is still here. We can’t tell if it arrived.'
            : 'Your report is still here.',
        style: AppType.meta
            .weight(FontWeight.w400)
            .copyWith(color: room.inkSecondary),
      ),
    );
    switch (_outcome) {
      case null:
        return _Padded(
          Text(
            brief
                ? 'Whoever runs the server sees it and can reply here.'
                : '${mediaReportFiledLine(serverTitle: gate.server?.title, accountName: reportAccountName(widget.source))}.',
            style: AppType.caption
                .weight(FontWeight.w400)
                .copyWith(color: room.inkTertiary),
          ),
        );
      case _Outcome.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InlineErrorRetry(
              message: _operatorLine(),
              error: _error,
              service: ServiceKey.seerr,
              instanceId: _connection,
              onRetry: _submit,
            ),
            stays,
          ],
        );
      case _Outcome.signedOut:
        return _Padded(
          _Note(
            icon: Icons.info_rounded,
            tone: StatusTone.info,
            text: brief
                ? Lexicon.youWereSignedOut
                : failureHeadline(
                    ServiceFailureReason.sessionEnded,
                    subject: _connectionTitle(),
                  ),
            sub: 'Sign in again to send your report. It stays here.',
          ),
        );
      case _Outcome.refused:
        return _Padded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaultNote.fault(
                message: gate.reportIssueAction().reason ?? _refusedLine(gate),
                surface: scheme.surfaceContainer,
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xl),
                child: Text(
                  'The server changed what your account may do.',
                  style: AppType.meta
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkSecondary),
                ),
              ),
            ],
          ),
        );
      case _Outcome.gone:
        return _Padded(
          const _Note(
            icon: Icons.info_rounded,
            tone: StatusTone.neutral,
            text: 'This title is no longer on the server.',
          ),
        );
    }
  }

  String _refusedLine(RoleGate gate) => gate.faultVoice == FaultVoice.brief
      ? RoleGateCopy.youCannot(SeerrAbility.reportIssue)
      : RoleGateCopy.accountCannot(
          SeerrAbility.reportIssue,
          server: _serverName(gate),
        );

  String _connectionTitle() => ref
      .read(currentSettingsProvider)
      .connectionTitle(_connection, ServiceKey.seerr);

  /// The operator's sentence in full, with since when it stopped answering
  /// when the app saw it. The requester's own line is built by the failure
  /// widget, and never names the service.
  String _operatorLine() {
    final reason = classifyConnectionFailure(_error);
    final headline = describeFailureOf(
      ServiceKey.seerr,
      _error,
      subject: _connectionTitle(),
    ).headline;
    final since = failureDidNotAnswer(reason)
        ? ref
              .read(silenceClockProvider)
              .since(silenceKey(ServiceKey.seerr, _connection))
        : null;
    return since == null
        ? '$headline.'
        : '$headline since ${formatClockTime(since)}.';
  }

  /// Season, and once one is chosen, episode.
  List<Widget> _where() {
    final seasons = widget.source.seasons;
    final tvId = widget.scope.key.tmdbId;
    final facts = _season > 0 && tvId != null
        ? ref
              .watch(
                mediaSeasonFactsProvider((
                  connectionId: _connection,
                  tvId: tvId,
                  season: _season,
                )),
              )
              .value
        : null;
    // The names TMDB gives the season's episodes, or the numbers alone while
    // it has not answered or did not.
    final names = {
      for (final fact in facts ?? const <MediaEpisodeFacts>[])
        fact.number: fact.name,
    };
    final count = widget.source.episodeCountOf(_season);
    final numbers = names.isNotEmpty
        ? (names.keys.toList()..sort())
        : [for (var n = 1; n <= count; n++) n];
    String episodeLabel(int number) => switch (names[number]) {
      final name? => '${formatEpisodeOrdinal(number)}$dotSeparator$name',
      null => formatEpisodeOrdinal(number),
    };

    return [
      _PickRow<int>(
        label: 'Season',
        value: _season == 0 ? 'All seasons' : 'Season $_season',
        selected: _season,
        options: [
          (0, 'All seasons'),
          for (final season in seasons)
            (season.number, 'Season ${season.number}'),
        ],
        onSelected: (season) => setState(() {
          _season = season;
          _episode = 0;
        }),
      ),
      if (_season > 0)
        _PickRow<int>(
          label: 'Episode',
          value: _episode == 0 ? 'All episodes' : episodeLabel(_episode),
          selected: _episode,
          options: [
            (0, 'All episodes'),
            for (final number in numbers) (number, episodeLabel(number)),
          ],
          onSelected: (episode) => setState(() => _episode = episode),
        ),
    ];
  }

  Widget _button(BuildContext context, GateVerdict verdict) {
    switch (_outcome) {
      case _Outcome.signedOut:
        return FilledButton(
          style: AppTheme.primaryButtonStyle(context),
          onPressed: _signIn,
          child: const Text(Lexicon.signInAgain),
        );
      case _Outcome.gone:
        return OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        );
      case _Outcome.failed || _Outcome.refused || null:
        return RoleGatedAction.builder(
          verdict: verdict,
          onTap: _submit,
          builder: (context, onPressed, annotate) => FilledButton(
            style: AppTheme.primaryButtonStyle(context),
            // Sending keeps the look and ignores the tap: a button with no
            // handler would draw as disabled.
            onPressed: _sending ? () {} : onPressed,
            child: _sending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text('Submitting'),
                    ],
                  )
                : annotate(const Text('Submit report')),
          ),
        );
    }
  }

  /// What each type is for, as the options say it.
  String _hintOf(SeerrIssueType type) => switch (type) {
    SeerrIssueType.video =>
      _movie
          ? 'Wrong movie, poor quality, or the picture breaks up'
          : 'Wrong episode, poor quality, or the picture breaks up',
    SeerrIssueType.audio => 'Out of sync, missing, or the wrong language',
    SeerrIssueType.subtitles => 'Missing, out of sync, or the wrong language',
    SeerrIssueType.other => 'Anything else',
  };
}

/// A block of the sheet on the screen gutter: the sheet's body runs edge to
/// edge so that a failure line, which keeps a gutter of its own, lines up.
class _Padded extends StatelessWidget {
  const _Padded(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: child,
  );
}

/// The label over a block, and what is missing from it.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.top = AppSpacing.lg, this.error});

  final String text;
  final double top;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final errorStyle = Theme.of(context).inputDecorationTheme.errorStyle;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        top,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text,
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Semantics(liveRegion: true, child: Text(error!, style: errorStyle)),
          ],
        ],
      ),
    );
  }
}

/// One type of problem, a radio of a group: nothing is preselected.
class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.hint,
    required this.selected,
    required this.onSelected,
  });

  final SeerrIssueType type;
  final String hint;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${type.label}, $hint',
      excludeSemantics: true,
      onTap: onSelected,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: onSelected,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? primary : room.inkSecondary,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      Text(
                        hint,
                        style: AppType.meta
                            .weight(FontWeight.w400)
                            .copyWith(color: room.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that picks one of a few values from a menu: `Season  Season 2  ⌄`.
class _PickRow<T> extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PopupMenuButton<T>(
      tooltip: '$label: $value',
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final (option, text) in options)
          PopupMenuItem<T>(
            value: option,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: AppType.row.copyWith(color: room.ink),
                  ),
                ),
                if (option == selected)
                  Icon(Icons.check_rounded, size: 20, color: room.ink),
              ],
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: AppType.meta
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: AppType.row.copyWith(color: room.ink),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: room.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sentence the sheet says of its own state, with no verb of its own: the
/// tone on one glyph, the sentence in the sheet's ink. For what is the
/// person's to do (signed out, blue) and what only is (gone, neutral).
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.tone,
    required this.text,
    this.sub,
  });

  final IconData icon;
  final StatusTone tone;
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 16,
              color: statusToneColor(scheme, tone, surface: room.raised),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppType.label.copyWith(color: room.ink)),
                if (sub != null)
                  Text(
                    sub!,
                    style: AppType.meta
                        .weight(FontWeight.w400)
                        .copyWith(color: room.inkSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
