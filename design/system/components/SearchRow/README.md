# SearchRow

One row of the Discover tab's search, laid out by kind (On your server, Movies, Series, People), of the atrium's People index, and of a person's and a collection's page (`CatalogTitleRow`): a title with its poster, what it is and where it stands, or a person with their face and what they are known for.

Rendered from `lib/features/discover/presentation/widgets/search_row.dart` (`SearchRow`, `SearchRowAction`, and the pieces a search is made of: `SearchHeading`, `SearchRowsPending`, `SearchNothing`) by `test/design_catalog/search_row_catalog_test.dart`.

## Anatomy

- Flat on the page, no card: the section name above groups the rows (`label` in the room's secondary ink, `space-md` above it). At least 76 tall (`SearchRow.minHeight`), `space-sm` above and below the picture.
- **Title** (`SearchRow.title`): the poster at 44 × 66, `radius-thumb` (8), decoded at its own size (`ArtworkDecodeBox`); with no artwork, or when it fails to load, the room's quiet fill with a hairline edge and the title's initials in `label` ink, which stop at the compact tiles' reading ceiling (`TextScaleMetrics.clampedScalerOf`) so two letters never fill the plate. `space-md`, then three lines: the title in `row` ink (one line), the meta in `meta` secondary ink (`Movie · 1996 · TMDB 8.0`, one line), and, when there is something to say, where it stands: a 7pt dot in the tone (`statusToneColor`), `space-s`, the word in `caption` at 600 in the secondary ink. The tone is on the dot only, as on `StatusBadge.poster`.
- **The control at the end** (`action`, a `SearchRowAction`), `space-sm` after the row; none where there is nothing to add or ask for:
  - `SearchRowAdd`, the plus: a 44 disc in the quiet fill with a hairline edge, `add_rounded` at 20 in the ink. Never a filled disc: adding is a row's action, not the page's one amber fill.
  - `SearchRowRequest`: `Request` in `button` ink on the quiet fill with a hairline edge, 44 tall at standard density, gated by the account's verdict (`RoleGatedAction`: dimmed with the server's reason, or absent). At a large reading size it takes the line under the row, at its end, so the title keeps its width.
  - `SearchRowSetUp`: the plus where nothing set up can add the title, dimmed but tappable (`CrossServiceAction`): its hint is `requires Radarr`, and a tap answers `Radarr is not set up.` with `Set up Radarr`.
- **Person** (`SearchRow.person`): the face, a 44 circle in the quiet fill with a hairline edge (initials without a picture), the name in `row` ink, one line under it in `meta` secondary ink (up to two lines: `Known for Forrest Gump, Toy Story`, or `Director · Dune` in the atrium), and a trailing chevron in the secondary ink.
- **Album** (`SearchRow.album`) and **artist** (`SearchRow.artist`), music's results: a 44 square cover (`radius-thumb`) or a 44 disc, the initials without a picture, the name in `row` ink (up to two lines), the meta in `meta` secondary ink (up to two lines: `The White Stripes · 2003 · Album`), and under it where it stands, which unlike a person's line these two say: the dot and the word in `caption` 600 as a title's, the dot a ring in the secondary ink (`statusHollow`) for the backlog (`Wanted`, `Unmonitored`, `9 of 11 tracks`), the words and tones those of the state lexicon. No chevron: what a tap does is told by `hint` (`Adds it to Lidarr`). The control at the end is the same as a title's, and `SearchRowAdd.busy` turns the plus into a spinner and the control inert while its write is out (the monitor and search of an album the library left alone). A count never breaks from its noun (`7 tracks` holds a no-break space).
- **The pieces of a search**: `SearchHeading` is a section's name in the label role in the secondary ink with, when the search knows it, how many on the right (`Artists  2`); `SearchRowsPending` is the rows on their way, plates at a row's size in the poster, square or circle shape, spoken as its label; `SearchNothing` is a search with nothing to show, the title in the section role, a line under it, and where there is a next step an action under that (and a glyph over it when the absence wants one). Discover's search draws the same three.
- `padding` around the row: none in a search, whose list carries the gutter; the slab's inset (`space-lg`) among the atrium's people.
- With a `heroTag` and artwork, the poster flies into the title's page (`MediaPosterCard.flightOnUserGestures`); with no artwork there is no flight, so an empty plate never flies.
- **Selected** (`selected`): on a tablet, the row whose page the pane beside the list shows sits on the room's strong fill (`fillStrong`, `radius-md`), the mark of what is selected in the settings' list and the tab bar. The fill reaches `space-sm` into the gutter on either side and is painted behind the row, so nothing in the row moves. The caller asks the pane (`paneShows` for a title's key, `paneShowsPerson` for a person, in `open_media.dart`); a poster wears its ring instead (`ContentCard.paneTag`).

## Where a title stands

The page decides the word, in the reader's vocabulary: on a media server it is `On Jellyfin` (or Plex, or Emby) (green, the connection's name once there are two); else Seerr's word for its record (`seerrCatalogStatus`, the requester's words for her); else `In Radarr` (neutral) for a library that holds it. No word for a title nobody holds a record of.

On a person's or a collection's page (`CatalogTitleRow`) the operator gets the plus to the title's arr when it is set up, every connection of it has answered and none holds the title. Through Seerr (the operator's choice on Seerr's connection page, the default) the plus is `Request` instead, once Seerr has answered that it has an arr to send it to, and it waits for that answer rather than changing from an add; without that arr, `Request` when Seerr has one to send it to; with neither, the plus dimmed. The requester gets `Request` as far as her account may. Nothing is offered for a title that is there, on its way or asked for.

## The consumer provides

`title`, `meta`, an optional `status` (label and tone), `poster` and `posterHeaders`, `heroTag`, `onTap`, and an `action` with its label (`Add Cosmic Voyage to Radarr`, `Request Project London`) where there is one to honour. A person: `name`, `line`, `face`, `onTap`. An album: `title`, `meta`, `cover` and `coverHeaders`, `status` with `statusHollow`, `hint`, `action`. An artist: `name`, `line`, `photo` and `photoHeaders`, the same. Either: `selected` while the pane beside the list shows its page.

## Semantics

The row is one button: its label is the title (or the name), its value the meta and the state (`Movie · 1996, Waiting for approval`; an album's and an artist's dots read as commas, `Jan Morgenstern, 2006, 7 tracks, Complete`), its hint what a tap does; its parts are silent, and it is announced as selected while the pane shows its page. The control at the end is its own button, named by its label; the dimmed plus keeps its button role and hint, never `enabled: false`.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- A search by kind: a title on the server with artwork and its state, one with no artwork and the plus, one waiting for approval, a person with no picture.
- A long title and a long state at 320pt: one line each, the plus whole.
- Selected: a person between two rows, one of them a title with its plus, at the tablet list's 440.
- The control at the end: the plus to Sonarr, a title on the server with none, Request, the plus dimmed.
- Music's results: an artist not held with the plus and one held (`In your library`), an album complete, wanted in the ring, left alone with its plus busy, and one with the plus; the same at 200%, the title and the meta on two lines.
- Text at 200%.

## Do / don't

- Do let the section name say what the rows are; don't add a service's name or colour to a row: the answer is by kind, not by source.
- Don't offer the plus on a title an arr holds, on one whose arr is not set up, or while one of that arr's connections has not answered: a silent server is never one that holds nothing.
