# SeerrIssues

The Issues tab of Seerr's room: the problems people reported, a row each, open ones in amber, with Resolve at the end of an open row.

Rendered from `lib/features/discover/presentation/seerr_admin_screens.dart` (`SeerrIssuesScreen`) by `test/design_catalog/seerr_issues_catalog_test.dart`. The scenes run the real `SeerrService` over a Seerr that answers in its real shape (`test/fixtures/seerr/issues.json`).

## Where the title comes from

Seerr's issue list carries no title: `media` holds only its ids, kind and status. The service names each row from the title's own page (`/movie/:id`, `/tv/:id`), four reads at a time and once per title for the service's life, the same cache and lanes as the Requests list (`SeerrService._hydrateIssues`). A title that does not answer leaves its row as it was, `Unknown media`; the list is not failed for it.

## Anatomy

- Filter pills (`SelectionPills`): Open, Resolved, All.
- A row (`AppCard.outlined`): a report glyph in the issue's tone (amber open, green resolved), the title in `titleMedium` 600, under it `Type · reporter · N comments` in `bodyMedium`, and Resolve as an icon button (44pt) on an open row, dimmed with its reason where the account may not resolve.
- Resolve asks first (`Resolve this issue?`); the row speaks `Title`, then `Open, Audio, reported by Anna`.

## Scenes

Every row named; a title that did not answer; twice the reading size.
