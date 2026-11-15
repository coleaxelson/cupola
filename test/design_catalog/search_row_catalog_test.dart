@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

String get _poster => ImageUtils.buildTmdbPosterUrl(CatalogArt.tmdbPoster);

/// A search's answer as the page lays it out: a section name over its rows.
Widget _answer() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const _Heading('On your server'),
    SearchRow.title(
      title: 'Cosmos Laundromat',
      meta: 'Series · 2015 · TMDB\u00A08.0',
      status: (label: 'On Jellyfin', tone: StatusTone.success),
      poster: _poster,
      onTap: () {},
    ),
    const _Heading('Movies'),
    SearchRow.title(
      title: 'Cosmic Voyage',
      meta: 'Movie · 1996',
      onTap: () {},
      action: SearchRowAdd(label: 'Add Cosmic Voyage to Radarr', onTap: () {}),
    ),
    SearchRow.title(
      title: 'Metropolis',
      meta: 'Movie · 1927 · TMDB\u00A08.2',
      status: (label: 'Waiting for approval', tone: StatusTone.info),
      poster: _poster,
      onTap: () {},
    ),
    const _Heading('People'),
    SearchRow.person(
      name: 'Tom Hanks',
      line: 'Known for Forrest Gump, Toy Story',
      onTap: () {},
    ),
  ],
);

/// A person's page with no Radarr set up: a series keeps its plus to
/// Sonarr, a movie is asked of Seerr, and where Seerr has no Radarr either
/// the plus stays, dimmed.
Widget _withoutRadarr() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const _Heading('Directed'),
    SearchRow.title(
      title: 'Dynamo Dream',
      meta: '2019 · Series',
      onTap: () {},
      action: SearchRowAdd(label: 'Add Dynamo Dream to Sonarr', onTap: () {}),
    ),
    SearchRow.title(
      title: 'Tears of Steel',
      meta: '2012 · Movie · TMDB\u00A06.6',
      status: (label: 'Available', tone: StatusTone.success),
      poster: _poster,
      onTap: () {},
    ),
    SearchRow.title(
      title: 'Project London',
      meta: '2011 · Movie',
      onTap: () {},
      action: SearchRowRequest(
        label: 'Request Project London',
        verdict: const Live(),
        onTap: () {},
      ),
    ),
    SearchRow.title(
      title: 'Project London',
      meta: '2011 · Movie',
      onTap: () {},
      action: const SearchRowSetUp(
        label: 'Add Project London',
        service: ServiceKey.radarr,
        blockedMessage: 'Radarr is not set up.',
      ),
    ),
  ],
);

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      SearchHeading(text, top: 12, count: null);
}

/// Music's results as a search lays them out: artists and albums, held or
/// not, the backlog's ring, a write in flight.
Widget _music() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SearchHeading('Artists', top: 12),
    SearchRow.disc(
      name: 'Elbow',
      line: 'Group\u00A0· Bury, England',
      onTap: () {},
      hint: 'Not in your library. Adds it to Lidarr',
      action: SearchRowAdd(label: 'Add Elbow to Lidarr', onTap: () {}),
    ),
    SearchRow.disc(
      name: 'Ella Fitzgerald',
      line: 'Person',
      status: (label: 'In your library', tone: StatusTone.success),
      onTap: () {},
    ),
    const SearchHeading('Albums', top: 20),
    SearchRow.album(
      title: 'Elephants Dream',
      meta: 'Jan Morgenstern\u00A0· 2006\u00A0· 7\u00A0tracks',
      status: (label: 'Complete', tone: StatusTone.success),
      cover: _poster,
      onTap: () {},
    ),
    SearchRow.album(
      title: 'Ella and Louis',
      meta: 'Ella Fitzgerald\u00A0· 1956\u00A0· 11\u00A0tracks',
      status: (label: '9 of 11\u00A0tracks', tone: StatusTone.neutral),
      statusHollow: true,
      onTap: () {},
    ),
    SearchRow.album(
      title: 'Electric Ladyland',
      meta: 'The Jimi Hendrix Experience\u00A0· 1968\u00A0· Album',
      status: (label: 'Unmonitored', tone: StatusTone.neutral),
      statusHollow: true,
      onTap: () {},
      action: SearchRowAdd(
        label: 'Monitor Electric Ladyland and search for it',
        busy: true,
        onTap: () {},
      ),
    ),
    SearchRow.album(
      title: 'Leaders of the Free World',
      meta: 'Elbow\u00A0· 2005\u00A0· Album',
      onTap: () {},
      action: SearchRowAdd(
        label: 'Add Leaders of the Free World by Elbow to Lidarr',
        onTap: () {},
      ),
    ),
  ],
);

void main() {
  catalogCard(
    'SearchRow',
    // Seerr and Sonarr are set up, Radarr is not.
    overrides: () async => [
      currentSettingsProvider.overrideWith(
        (ref) =>
            settingsWithServices(const [ServiceKey.seerr, ServiceKey.sonarr]),
      ),
    ],
    scenes: [
      CatalogScene(
        'A search by kind · a title on the server with its artwork and where '
        'it is, one with no artwork (its initials) and the plus, one waiting '
        'for approval, and a person with no picture',
        (_) => _answer(),
        width: 390,
      ),
      CatalogScene(
        'SearchRow.title · a long title and a long state, cut to one line '
        'each; the plus keeps its 44',
        (_) => SearchRow.title(
          title: 'The Cabinet of Dr. Caligari and Other Expressionist Films',
          meta: 'Movie · 1920 · TMDB\u00A08.0',
          status: (label: 'Partially available', tone: StatusTone.info),
          onTap: () {},
          action: SearchRowAdd(
            label: 'Add The Cabinet of Dr. Caligari to Radarr',
            onTap: () {},
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'Selected · on a tablet, the row whose page the pane beside the list '
        'shows sits on the room\'s strong fill, reaching into the gutter; '
        'the rows around it, one with its plus, are as ever',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SearchRow.person(
                name: 'Ton Roosendaal',
                line: 'Producer · Sintel',
                onTap: () {},
              ),
              SearchRow.person(
                name: 'Colin Levy',
                line: 'Director · Sintel',
                onTap: () {},
                selected: true,
              ),
              SearchRow.title(
                title: 'Tears of Steel',
                meta: 'Movie · 2012 · TMDB\u00A06.4',
                onTap: () {},
                action: SearchRowAdd(
                  label: 'Add Tears of Steel to Sonarr',
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        width: 440,
      ),
      CatalogScene(
        'The control at the end · the plus to Sonarr, a title on the server '
        'with none, Request where Seerr sends a movie to its Radarr, and the '
        'plus dimmed where nothing set up can add it',
        (_) => _withoutRadarr(),
        width: 390,
      ),
      CatalogScene(
        'SearchRow.disc and SearchRow.album · music\u2019s results: a disc '
        'and a square cover with their initials, a state under the meta line '
        '(filled for what is held, the backlog\u2019s ring for what is '
        'wanted or left alone), the plus, and the plus while its write is out',
        (_) => _music(),
        width: 390,
      ),
      CatalogScene(
        'SearchRow.album at 200% · the title and the meta take two lines, a '
        'count never breaks from its noun',
        (_) => _music(),
        width: 390,
        textScale: catalogTextScale,
        id: 'search-row-album-200',
      ),
      CatalogScene(
        'Text at 200% · the row grows past its floor, the words stay on one '
        'line each and the person\'s line takes two',
        (_) => _answer(),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
