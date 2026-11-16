# DiscoverMusic

Music in Discover, for the operator with a music source (today Lidarr): the shelf `More from your artists` in the atrium, the page its heading opens, and the `Music` section of the search.

Rendered from `lib/features/discover/presentation/widgets/more_from_your_artists_shelf.dart` (`MoreFromYourArtistsShelf`, `ArtistAlbumTile`), `lib/features/discover/presentation/more_from_your_artists_page.dart` (`MoreFromYourArtistsPage`) and `lib/features/discover/presentation/widgets/discover_music_section.dart` (`DiscoverMusicSection`, over `lib/features/music/presentation/music_hit_row.dart`) by `test/design_catalog/discover_music_catalog_test.dart`.

## The shelf

- After `The best you're missing` when Seerr is set up (before `Trending this week`), under the calendar's band when it is not. It reads nothing of Seerr, so a Seerr that did not answer leaves it where it is.
- Heading in the section role with a chevron that opens See all, and under it, in the meta role, `Albums Lidarr knows from artists you have, not monitored.` (the connection's name once there are two). On a pointer the rail carries its arrows beside the chevron (`RailArrows`).
- Up to twenty tiles, newest release first (`MoreFromYourArtists.shelfLength`): the albums the library's artists have that are out, not monitored and have no file. A tile is 132 wide: the cover in a 132 square with its own light (`ContentCard.lit`, the album glyph without artwork), `space-sm`, the title in the label role (two lines) and under it `Jan Morgenstern · EP · 2008` in the caption role in the secondary ink (two lines): the artist, the kind in the singular (`AlbumKind.fact`) and the year. No plus: choosing is done on the artist's page.
- Drawn only for the operator, with a music source, and once it has something to show. While it is read, over a failed read, and with nothing left, it is nothing at all, as the atrium's other optional shelves are.
- A tap opens the artist's page landed on the album, on its tracks (`?album=`). One sentence: `Big Buck Bunny Suite, EP by Jan Morgenstern, 2008, unmonitored`, hint `Opens the artist`.
- The words follow the reading size up to the compact ceiling and the rail grows with them (`ArtistAlbumTile.heightFor`).

## See all

`/discover/artists`: the title, the line above, then the artists A to Z (blind to case and accents), each as a `SearchHeading` with how many albums, and under it their albums newest first as `SearchRow.album` (cover, title, `EP · 2008 · 5 tracks`, the hollow `Unmonitored`). Built as it scrolls. Pull to read again. Over a failed read: Lidarr's failure with Retry; with nothing left: `Nothing left to find`. The requester is sent to Discover.

## The search

- The field says `Movies, series, people, music`; without Seerr `Movies, series, music`. The requester's stays `Movies, series, people`, and Lidarr is never asked for her.
- `Music` follows the series, before the people. At most three rows of Lidarr's search, in its order, artists and albums together (`MusicHitRow.mixed`): the line leads with the kind (`Album · Jan Morgenstern · 2010`, `Artist · Group · Bury, England`). A held row says where it stands (`In your library`, or the album's own state word) and opens the artist, on the album for an album; one not held carries the plus that opens the add sheet; an album left alone carries the plus that monitors it and searches. Under them `Show all music for “…”` opens the Music wall on the Lidarr scope with the same words.
- While Lidarr answers after the others: `Music`, `Asking Lidarr` and two square plates. Nothing found: no section. Its catalog not answering (`LidarrCatalogUnavailable`) or Lidarr silent: no section, and the quiet line every source has at the head of the results (`Lidarr answered, but its music catalog did not, so music is missing.`, Retry). A library that cannot be read says the same rather than guess which rows are held.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The shelf in the atrium with Seerr, and on the page without it.
- The shelf at 200%, and on a desktop window with its arrows.
- See all, at 200%, and on a desktop window.
- The search for Sintel (movie and music together), for Elbow (music alone), with Lidarr answering late, with its catalog down, the requester's, on a desktop window, at 200%.

## Do / don't

- Do keep the section named `Music`, not the service: another source joins the same section.
- Don't put a plus on the shelf's covers, and don't draw a shelf over a failed read.
