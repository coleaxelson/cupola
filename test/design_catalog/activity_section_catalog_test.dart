@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/everyone_request_row.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

import 'catalog.dart';

/// A row of words, as the page's rows are: a title and what it says.
class _Row extends StatelessWidget {
  const _Row(this.title, this.line, {this.divided = false});

  final String title;
  final String line;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppType.row.copyWith(color: room.ink)),
            Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// The filter pills as the board draws them.
class _Pills extends StatelessWidget {
  const _Pills({this.state, this.person});

  final String? state;
  final String? person;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      IntrinsicWidth(
        child: SelectionPill(
          label: state ?? 'Any state',
          selected: state != null,
          onTap: () {},
          trailing: Icons.expand_more_rounded,
        ),
      ),
      IntrinsicWidth(
        child: SelectionPill(
          label: person ?? 'Anyone',
          selected: person != null,
          onTap: () {},
          trailing: Icons.expand_more_rounded,
        ),
      ),
      if (state != null || person != null)
        IntrinsicWidth(
          child: SelectionPill(label: 'Clear', selected: false, onTap: () {}),
        ),
    ],
  );
}

/// The slab's one line when the filters keep no request.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Text(
      'No requests match these filters.',
      textAlign: TextAlign.center,
      style: AppType.body.copyWith(color: CupolaRoom.of(context).inkSecondary),
    ),
  );
}

final _now = DateTime(2026, 10, 10, 20, 30);

/// A declined request as the board draws it: the operator's line (`Declined
/// yesterday`) and who asked, over a poster-less row.
Widget _declined(
  String title,
  String who, {
  required int daysAgo,
  bool divided = false,
}) => EveryoneRequestRow(
  mine: MyRequest(
    request: SeerrRequest(
      id: title.length,
      status: RequestStatus.declined,
      type: 'movie',
      createdAt: '2026-10-01T10:00:00.000Z',
      media: RequestMedia(id: 1, tmdbId: 1, mediaType: 'movie', title: title),
      requestedBy: RequestedBy(id: 1, displayName: who),
    ),
    stage: MyRequestStage.declined,
    answeredAt: _now.subtract(Duration(days: daysAgo)),
  ),
  now: _now,
  divided: divided,
);

void main() {
  catalogCard(
    'ActivitySection',
    scenes: [
      CatalogScene(
        'ActivitySection() · a name on the page over a slab of rows, and '
        'what it counts at the end of the name\'s line',
        (_) => ActivitySection(
          title: 'Downloads',
          meta: '4 moving · 1 stuck',
          children: const [
            _Row('Sprite Fright', '62% · 11 min'),
            _Row('Elephants Dream', '31% · 6 min', divided: true),
            _Row('Big Buck Bunny', 'Stuck at 47%', divided: true),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySection() · no count: the name alone, as Finished today '
        'has none to say when there is only the one',
        (_) => ActivitySection(
          title: 'Finished today',
          children: const [_Row('Spring', 'Imported 18:52')],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySection(onOpen:) · a count too long for the name\'s line '
        '(three groups) goes under the name, left-aligned, as it does at a '
        'large reading size, instead of running past the page',
        (_) => ActivitySection(
          title: 'Needs you',
          meta: '3 faults · 2 violations · 3 requests',
          onOpen: () {},
          openHint: 'Opens Needs you',
          children: const [_Row('Big Buck Bunny', 'Stuck at 47%')],
        ),
        width: 390,
        id: 'long-count-goes-under-the-name',
      ),
      CatalogScene(
        'ActivitySection(onOpen:) · the count leads to the section\'s own '
        'view, with a chevron and a 44pt target',
        (_) => ActivitySection(
          title: 'Up next',
          meta: '1 queued',
          onOpen: () {},
          openHint: 'Opens Downloads',
          children: const [_Row('Sintel', 'Queued · starts in about 6 min')],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySlabLink() · the last line of a slab leads on: what it '
        'opens, what it counts, a chevron, over a hairline',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '8 total',
          children: [
            const _Row('Coffee Run', 'Ready to watch since 17:53'),
            const _Row(
              'Sprite Fright',
              'Downloading 62% · ready around 21:04',
              divided: true,
            ),
            ActivitySlabLink(
              label: 'All 8 requests',
              meta: '2 processing',
              onTap: () {},
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySlabLink(divided: false) · the only line of a slab, with '
        'no count, and a long label that ellipsises its count rather than '
        'itself',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ActivitySlab(
            children: [
              ActivitySlabLink(
                label: 'All of today in History',
                meta: '3 imports and 1 failed download',
                divided: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the count goes under the name rather than beside '
        'it, the name never breaks inside a word',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '8 total',
          onOpen: () {},
          children: [
            const _Row('Coffee Run', 'Ready to watch since 17:53'),
            ActivitySlabLink(
              label: 'All 8 requests',
              meta: '2 processing',
              onTap: () {},
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · a section with no count, and a link line of '
        'two words',
        (_) => ActivitySection(
          title: 'Finished today',
          children: [
            const _Row('Spring', 'Imported 18:52'),
            ActivitySlabLink(label: 'All of today in History', onTap: () {}),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'ActivitySection(controls:) · Everyone\'s requests narrowed: the '
        'pills between the name and the slab, the one that narrows lit, '
        'Clear while any does, and the count as 41 of 348',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '41 of 348',
          controls: const _Pills(state: 'Declined'),
          children: [
            _declined('Coffee Run', 'Anna', daysAgo: 1),
            _declined('Sprite Fright', 'Ben', daysAgo: 3, divided: true),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySection(controls:) · a filter that leaves nothing: the '
        'section stays with its pills, and its slab says so',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '0 of 348',
          controls: const _Pills(state: 'Blocked', person: 'Anna'),
          children: const [_Empty()],
        ),
        width: 390,
      ),
      CatalogScene(
        'On the desktop · a section in the page well',
        (_) => ActivitySection(
          title: 'Downloads',
          meta: '4 moving · 1 stuck',
          onOpen: () {},
          children: [
            const _Row('Sprite Fright', '62% · 11 min'),
            const _Row('Big Buck Bunny', 'Stuck at 47%', divided: true),
            ActivitySlabLink(label: 'All 5 downloads', onTap: () {}),
          ],
        ),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
