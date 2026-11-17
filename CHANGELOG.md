# Changelog

## 1.2.0-beta

Problem reports through Seerr, a music library you can grow and walk from Cupola, and
selection on every library wall, with the fixes our testers and issues asked for. It
updates 1.1.0-beta in place: your connections stay.

### Added

- **Report a problem with a title, and follow it up** (#12). A title Seerr has on the
  server now has *Report a problem*: say what is wrong (Video, Audio, Subtitles or
  Other, each with an example), for a series the season and the episode, and in your
  own words. The report goes into Seerr's own issues, so it is the same report on the
  web. An episode's sheet reports a problem with that episode.
  - A household member finds their reports under their requests (*Your reports*), with
    who replied, and can reply, mark one as resolved, reopen it, or delete it while
    nobody has answered.
  - Whoever runs the server reads every open report in *Needs you*, on Seerr's Overview
    (*Open problems*) and on the title's page, with the files it could be about and a
    way to search a new release. They can reply, resolve, reopen or delete it, or open
    it in Seerr. Seerr's Issues tab shows each report's poster, episode and words, and
    opens it.
  - Every control follows Seerr's own permissions: one an account may not use stays
    in place, dimmed, and says why.
- **Add artists and albums to Lidarr from Cupola.** A search result that is not in your
  library opens a sheet that adds the artist with your root folder's defaults, then
  lands on the artist's page while Lidarr reads its albums. An album can be added on
  its own: Lidarr adds its artist too and monitors only that album.
- **Find in your library, on every wall.** Music, Movies, Series and Authors have a
  field that finds as you type in what the wall already holds (blind to case and
  accents). A second scope asks the service itself: Lidarr for artists and albums,
  Radarr and Sonarr for titles, each with the plus that adds what you do not have.
- **Select several titles and act on them together.** A long press, or *Select*, turns
  a library wall into a selection: Search, Monitor, a profile, or Remove, with the
  actions each service's editor accepts. On a phone the selection bar takes the place
  of the navigation bar. When a service refuses part of the set, the notice names who
  was refused, in the service's words, and Retry acts on those alone. Remove acts only
  on the selected titles the current filter shows, and a Search over more than fifty
  titles asks first, because the service searches them one by one and cannot be
  stopped.
- **A big music library is easier to walk.** On Lidarr's wall *Wanted* takes the place
  of *Missing*: the artists with at least one album released, monitored and not on
  disk, each saying how many. Every wall sorted by title gets an A–Z index on its
  right edge.
- **An artist's page sorts albums by kind and finds a track.** An artist with more than
  one kind of release gets pills (Albums, EPs, Singles, Concerts, Compilations,
  Soundtracks and more, each with its count), and *Find a track* searches the tracks of
  every album and opens the album the track is on.
- **More from your artists, and music in Discover's search.** Discover shows the albums
  Lidarr knows from artists you have and nobody monitors, and its search finds music
  too when Lidarr is set up: held albums in your library's words, the rest with the
  plus that adds them.
- **Filter Requests by state and by who asked.** Activity's Requests and Seerr's Requests
  tab get two filters, and the heading reads *41 of 348* while one narrows the list.
- **Hide what I have, on Discover's first page.** The switch now sits on the atrium too,
  and Trending, Coming soon and Because you watched leave out what is already on the
  server. Until you flip it, it starts from Seerr's own *Hide available media*
  setting.
- **Ready for the foldable iPhone Duo.** Cupola follows the Duo from the outer screen to
  the inner one while it runs, keeps its content clear of the sensor column, and opens
  dialogs in one half, away from the fold.
- **A smaller Android package for 64-bit phones.** Each release now carries
  `cupola-<version>-arm64-v8a.apk`, less than half the size, beside the universal
  `cupola-<version>.apk`. Both have the same signature and version, so a phone can move
  from one to the other without uninstalling.
- **CPU and memory on the Unraid Overview.** The System section now opens with the
  server's CPU load and memory in use (*41% · 26.4 of 64.0 GB*), read again every few
  seconds while you look at it. An Unraid whose API is too old to know them shows
  neither row, rather than a dash that never fills in.

### Changed

- **On Android, the code scanner no longer reports to Google.** *Copy from another
  device* now reads the other device's code with zxing-cpp, free software that runs
  on the phone and sends nothing, instead of Google's ML Kit, which sent Google
  usage data with no way to turn it off. Nothing changes on iPhone, iPad or Mac.
- **A long title takes two lines** beside *Request*, so titles that share a long
  beginning can be told apart. A collection's legend appears only when something is on
  its way or waiting, instead of repeating the headline.

### Fixed

- **Unraid shows its containers and figures again on Unraid 7.2 and later** (#14).
  We asked for the container list by a name Unraid's API dropped before 7.2, so the
  server refused the whole request and the Docker tab, the container count and the
  other readout figures all disappeared. We now ask the way the current API answers,
  and the figures no longer disappear together: if the containers cannot be read, the
  array's figures stay, and the other way round.
- **A failed download no longer asks you to fix an import** (#15). *Needs you* read every
  failed download in the arrs' history as *Could not import*, with a notification and a
  Fix that opened a manual import with nothing in it. When a download fails, Radarr,
  Sonarr and Lidarr have already set that release aside and are looking for another,
  so there is nothing to ask of you; History still says *Download failed*. A release a
  delay profile holds back now says when it starts (*Queued · starts in about 3 h*).
- **Seerr's Issues tab names its titles.** Every row read *Unknown media* on a real
  server, because Seerr's issue list carries no title. People are named by their Seerr
  display name, so a Jellyfin or Emby account no longer shows its email.
- **A switch that is off can be seen** in both themes.
- **An artist with no picture** on Lidarr's Overview shows a person, not a movie.

### Known limits

- **Tracearr** needs version 2.7.0 or newer. History has no filter by library,
  because Tracearr's history does not offer one, and Live has no filters yet.
- **Authors find in your library only**: Readarr no longer offers a lookup to ask.
- **The new Android code scanner** has been tried on an emulator, not yet on a phone.

## 1.1.0-beta

Two new services in the Stream group, Emby and Tracearr, both tried on servers we use
every day, and what those servers taught us about Jellyfin and Plex too. It updates
1.0.0-beta.1 in place: your connections stay.

### Added

- **Emby, the eighteenth service.** Add an Emby server with its address and an API key
  and it gets the room Jellyfin has: Overview, Libraries, Users, Devices, Tasks and
  Activity. You see who is watching right now and what you left halfway, and you can
  pause, resume, stop or message a session. Titles open in the Emby app or in the
  browser, Emby answers the global search, and a title Seerr finds on Emby offers
  *Watch on Emby*, for a household member too, who keeps the simpler app.
- **Tracearr, the nineteenth service.** Add a Tracearr with its address and its public
  API key and it gets five tabs: Overview, Live, History, Users and Violations. Live
  shows every stream on the media servers Tracearr watches as it starts, moves and
  stops, and you can end one from there. A violation opens to what the rule saw, in
  numbers and never an address, and the grave ones appear in *Needs you*. *Now
  playing* on the Home puts Tracearr's streams in the same list as your Jellyfin's
  and Emby's, including the ones only Tracearr sees, and a title says who watched it
  (*Watched by*). Sign in as the owner and you can Acknowledge or Dismiss a violation
  from the app, and a *Flagged* notification tells you when Tracearr records a new
  one.
- **A wrong server now says so.** Point a connection at the address of another
  service and the form names the one that answered, and offers to set that one up
  with the same address.

- **Posters are named.** A media server's library, a title's contents and *Recently
  added* put the title and the year under each poster, so one without artwork is not
  a blank.

### Fixed

- **An episode Sonarr has no date for is no longer Missing** (#13). Sonarr sends no
  date for an episode announced without one (its *TBA*) and leaves it out of Wanted;
  we read the missing date as a past one. It now reads *No air date*, and counts
  neither as aired nor as missing.
- **A session control is shown only where the player takes it.** Jellyfin and Emby
  accept Pause, Stop and Message for any player and answer the same either way, so a
  TV app that never listens took a Pause and played on. Those controls now appear
  only for players that announce them, and after Pause or Stop the page says when the
  player did not obey.
- **A playback opens its title.** A stream in *Now playing* opens the title it plays,
  and Play leads on the server the title was opened from.
- **Plex names a 4K copy.** A title found on Plex says its copy's picture again
  (`2160p`), which Plex's search answer leaves out.
- **Media server rooms no longer flash** a placeholder for a frame on every refresh.
- **TrueNAS says a pool's state in words** (`Healthy`, `Degraded`, `Has errors`)
  instead of ZFS's raw `ONLINE`.
- **A title Seerr reads as Processing** no longer says Radarr already tracks it while
  Radarr's own row says it does not.
- **An episode code never splits** across two lines (`S2 E5`).
- **Dockge is recognised by its own page**, so a Tracearr at the address being
  checked is no longer taken for it.
- **The GitHub link in Settings** opens the repository under its current name.

### Known limits

- **Tracearr** needs version 2.7.0 or newer. History has no filter by library,
  because Tracearr's history does not offer one, and Live has no filters yet.

## 1.0.0-beta.1

The first release of Cupola, published as a beta. Everything before it was published
as Seekarr (up to 0.8.0) and covered five services; this one is a new app rather than
an update. The [release notes](https://github.com/matthw-labs/cupola/releases/tag/v1.0.0-beta.1)
go through every area in detail.

### Coming from Seekarr

- Cupola installs **beside** Seekarr and starts empty: the Android package changed
  from `labs.matthw.seekarr` to `com.matthwlabs.cupola`, and the Apple bundle ids
  changed too. Add your services again (same addresses, same API keys), check that
  they answer, then uninstall Seekarr. *Set up another device* copies them to the
  next device.
- **Obtainium:** remove the Seekarr entry and add Cupola as a new app.
- The minimums went up: Android 7.0 (was 6.0), iOS 17, and macOS 12 on an Apple
  silicon Mac (Seekarr also ran on Intel Macs and on macOS 10.15).
- Cupola is released under Apache 2.0; Seekarr 0.8.0 and earlier stay under MIT
  (see `NOTICE`).

### What is in it

- **17 services in one app:** Seerr, Radarr, Sonarr, Lidarr, Readarr, Bazarr,
  qBittorrent, Transmission, SABnzbd, NZBGet, Prowlarr, Jellyfin, Plex, TrueNAS,
  Unraid, Dockge and Nginx Proxy Manager. The README says, per service, how far
  Cupola goes and whether we have tested it against a real instance.
- **Home:** what arrived, what comes out next, what you were halfway through and what
  needs you, as modules you keep, order or leave out.
- **Discover:** trending, a calendar, every way in (genres, networks, studios,
  people, decades, moods), one search across Seerr, the arrs, Jellyfin and Plex, and
  one page per title to decide and act on it.
- **Activity:** *Needs you* says what went wrong in plain words and leads with the
  way out; downloads from all four clients sit in one list, and a client whose
  figures stop coming back says how old they are.
- **Stack:** every service in its own room, with an Overview and its own tabs.
  Add movies and series from the app, and choose a release in a search that waits
  for you in Activity.
- **For the household:** a member signs in to Seerr with their own account and gets
  Home, Discover and their requests, without the operator's controls.
- **At home and away:** a second address per connection, Cloudflare Access service
  tokens, proxy passwords or custom headers, and self-signed certificates trusted on
  first use and pinned per host.
- **A new device in one code:** *Set up another device* copies every connection over
  your home network, encrypted. *Invite someone* hands a household member the way to
  your Seerr, never its API key.
- **Widgets and notifications** on iOS and Android, worked out on the phone itself:
  no push server. Notifications are off until you turn them on.
- **Phone first, then tablet and desktop**, light and dark, large text, VoiceOver and
  TalkBack. No server at hand? *Explore a demo home* on the first screen.

### Install

| Platform | Get it | Notes |
| --- | --- | --- |
| iPhone, iPad | TestFlight | The link is in the release notes. iOS 17. |
| iPhone, iPad | unsigned `.ipa` | Sideload with AltStore, SideStore or Sideloadly. With a free Apple ID the install lasts **7 days**, and the widgets may stay empty. |
| Android | `.apk` | Android 7.0. Allow installs from unknown sources, or use Obtainium. |
| macOS | `.dmg` | macOS 12, Apple silicon. Signed with a Developer ID and notarized by Apple. |
| Windows | `.zip` | Built by GitHub Actions and not signed: SmartScreen asks once. |
| Linux | `.tar.gz` | Built by GitHub Actions; needs GTK 3 and libsecret. |

`SHA256SUMS` on the release lists the digest of every file, taken from the copies a
reader downloads.

### Known limits

- **Unraid** is tested against recorded answers from its API, never against a real
  server: we do not run one. A report from someone who does is very welcome.
- **Plex, Bazarr, Readarr, TrueNAS and Nginx Proxy Manager** have been read against
  real instances, but not every action has been run against one.
- **Readarr is manage only:** no adding authors, because Readarr is retired and its
  metadata service no longer answers. **Bazarr** is mostly read.
- **TrueNAS** needs SCALE 25.04 or later.
- **Background refresh is the operating system's call.** Widgets and notifications
  update when iOS or Android lets the app run, which can be hours apart on iOS.
- **Windows and Linux** builds are made by CI and we have not run them ourselves.
- **English only**, by design.
