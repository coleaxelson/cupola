# MediaReport

How a person reports a problem with a title, and how the page says where a report stands: a row on the title's page, and the sheet it opens.

Rendered from `lib/features/media/presentation/media_report_row.dart` (`MediaReportSection`, `MediaReportRow`, `MediaEpisodeReportRow`) and `lib/features/media/presentation/report_problem_sheet.dart` (`ReportProblemSheet`) by `test/design_catalog/media_report_catalog_test.dart`. Where they stand on the page is the [MediaPage](../MediaPage/README.md) card.

## When it is drawn

Only with a Seerr connection whose record of the title says it is on the server (`status` or `status4k` available, for a series partly available too) and carries a media id (`mediaReportSourceOf`). No Seerr, or a title not on the server: nothing, and no gap. Of two Seerr connections that qualify, the page's `focus` wins, else the first. The episode row also needs the episode's season to be on the server, and is never drawn for Specials: Seerr reads season 0 as every season.

## Anatomy

- **Requester**: one group under the lead. Her own report first (from `mediaInfo.issues`, by her user id): the newest still open when she has one, so a newer resolved report never hides it, else the newest she made (`MediaReportSource.ownCurrent`): `Your video report is open` with the blue `Reported`, the date and the replies (`1 reply from Matt`, read from that one issue), or `Your video report was resolved` with the green `Resolved`. Then `Report another problem` (open) or `Report a problem` (resolved, or none yet). The own-report row opens the report ([SeerrIssueThread](../SeerrIssueThread/README.md)) under her Requests tab, and so does an operator's issue row inside Seerr's Issues tab.
- **Operator**: `Reported problems` (`N open`) with the title's open issues, amber: its words, then `Video · Luca · yesterday · 2 replies`; then `Report a problem`, subtitled `Filed in Seerr as <name>` (`Filed in Seerr` for the key; `Filed on <server>` where the server has a title of its own). With nothing open, only the row, no heading.
- **The gate** (`RoleGate.reportIssueAction`): live, or dimmed: still drawn, a 44pt target, its reason as the hint and as the toast on a tap, never `Semantics(enabled: false)`.
- **The sheet** (`AppBottomSheet`): `Report a problem` and the title, with `S2 E3` once a place is chosen. `What's wrong?` as a radio group of four, nothing preselected. For a series `Where`: Season (`All seasons` and the seasons on the server only; one season alone is preselected) and, once a season is chosen, Episode (`All episodes`, then `E3 · The Second Cycle`). `Describe it`, the caption, `Submit report`. A missing type reads `Choose what's wrong.`, missing words `Say what happens.`, in the field's error style.
- **Sending**: the button busy, one tap only, and neither the barrier nor Back closes the sheet. A failure whose outcome is not known (a timeout after the send, a reply that broke off, a 5xx) is not offered again before the app reads what Seerr holds (`writeMayHaveLanded`): a report of hers with the same type, place and words that the title did not have before counts as filed, and the sheet closes as on success; when none is there, the failure is told as below; when the read fails too, the note under it reads `Your report is still here. We can’t tell if it arrived.` A failure that certainly never arrived is not read back. A failure is told in the sheet and the draft stays: the requester reads `Can't reach the server` (with its time when the app saw it) and `Retry`; the operator reads `Seerr did not answer`; signed out is blue and `Sign in again` leads; a refusal is amber with no Retry and Submit dimmed; a title Seerr no longer has is neutral, with `Close`.
- **After success**: the sheet closes, `Problem reported`, the title's Seerr record and the Issues list are read again.

## Scenes

The row dimmed (a requester, and an account on another server), her report open and resolved, the operator with an open issue and with none, the toast, twice the reading size. The sheet for a movie, for an episode, from the series page, with nothing chosen, sending, and each failure. The menu that picks the episode opens on the root overlay, which a sheet cannot show: it is described here, and drawn by the widget test.
