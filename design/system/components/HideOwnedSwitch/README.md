# HideOwnedSwitch

`Hide what I have`: the one switch that takes what the server already holds off Discover's lists. On a catalogue page, under its pills, and on the atrium, right under the quiet links (`Moods ›  Languages ›`) and above the shelves.

Rendered from `lib/features/discover/presentation/widgets/hide_owned_switch.dart` (`HideOwnedSwitch`) by `test/design_catalog/hide_owned_switch_catalog_test.dart`.

## Anatomy

- One row at least 48 tall (`HideOwnedSwitch.minHeight`), `AppSpacing.lg` on each side: the words in `AppType.row` at 500 in the ink, the theme's `Switch` at the end. The whole row is the control: a tap anywhere on it turns the switch.
- The row is a phone's at most (`AppBreakpoints.splitList`), at the start of a wider page: across a tablet or a desktop window the switch would sit a thousand points from the words that say what it does.
- Before the choice is known (`value: null`) the row keeps its words and its height, and the real switch is laid out in its place but not drawn or live, so the words and the row do not move by a pixel on any platform's theme when it comes when the switch comes, and a switch that flipped on its own after being drawn would say what the page had not yet decided. The row takes no tap meanwhile and says nothing to a screen reader.

## What it holds

One choice for the whole of Discover, kept across launches (`catalogHideOwnedProvider`), never one per shelf. The person's own choice when there is one. Until they make it, the lens's Seerr says: its `hideAvailable` from `/settings/public` (`SeerrServerFacts.hideAvailable`, read like every Seerr fact, through the connection's reach). With no Seerr, or one that did not answer, it is off.

On the atrium it takes what the server holds off Because you watched, Trending this week and Coming soon, each at its shelf: Trending itself is read whole (the doors' artwork, People's faces and the check that Seerr answered all read it), and with the switch on its shelf reads a second page once, and only when fewer than twelve titles are left. The best you're missing and Complete the collection are never filtered: the first already leaves out what the server holds, the second is about what it does. A shelf with nothing left is not drawn. Every list waits for the choice and for Seerr's numbering before it draws a poster, so none appears and then goes. The requester's Home does not read the switch.

## The consumer provides

`value` (null until known) and `onChanged`. The atrium draws it only where Seerr answered: with Seerr silent there are no shelves for it to filter.

## Semantics

One toggle: the words are its label, merged with the `Switch`, announced as on or off. Without a value the row is silenced.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Off, on, and before the choice is known (no switch).
- On a tablet or a desktop window: the row stays a phone's width, at the start.
- Text at 200%: the row grows with its words.

## Do / don't

- Do keep it one switch: a second, per shelf, would hold a choice nobody can see in one place.
- Don't draw the switch before its value is known, and don't draw a shelf and filter it afterwards.
- Don't put it on the requester's Home, which has no atrium to filter.
