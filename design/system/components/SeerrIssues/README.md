# SeerrIssues

The Issues tab of Seerr's room: the problems people reported, a row each, open ones in amber, with Resolve at the end of an open row.

Rendered from `lib/features/discover/presentation/seerr_admin_screens.dart` (`SeerrIssuesScreen`) by `test/design_catalog/seerr_issues_catalog_test.dart`. The scenes run the real `SeerrService` over a Seerr that answers in its real shape (`test/fixtures/seerr/issues.json`).

## Where the title comes from

Seerr's issue list carries no title: `media` holds only its ids, kind and status. The service names each row from the title's own page (`/movie/:id`, `/tv/:id`), four reads at a time and once per title for the service's life, the same cache and lanes as the Requests list (`SeerrService._hydrateIssues`). A title that does not answer leaves its row as it was, `Unknown media`; the list is not failed for it.

## Anatomy

- Filter pills (`SelectionPills`): Open, Resolved, All, then one summary line: `3 open · the newest change first` (a list cut short reads `50+`).
- A row (`SeerrIssueRow`, a door slab with a hairline): the title's poster at 36x54 under its own light (`MediaPosterCard`), the title, the state word in its tone (amber `Open`, green `Resolved`) beside `S2 E3 · Audio · Anna · Sat 26 Sep`, the report's words on two lines (whole at a large reading size), and `2 replies` when there are some. The whole row opens the issue (`/stack/seerr/issues/:id?i=<connection>`, see [SeerrIssueThread](../SeerrIssueThread/README.md)).
- Resolve is a 44pt button of its own at the end of an open row, dimmed with its reason where the account may not resolve. It asks first (`Resolve this issue?`: `Seerr marks it resolved for Anna. It can be reopened.`), then every list and page that speaks of the issue is read again.
- The row speaks one sentence (`Title. Open. S2 E3 · Audio · Anna. The words. 2 replies`); Resolve stays its own control.

The board draws the rows as one group with hairlines; the page keeps `ServiceListPage`'s separated rows, which carry the pull to refresh and the failure bands.

## Scenes

Every row named; All, with a resolved row; the Resolve confirm drawn on a scene-local navigator; a title that did not answer; twice the reading size.
