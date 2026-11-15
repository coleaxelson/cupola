# SeerrIssueThread

One problem somebody reported, and its conversation, for the operator and for the requester who reported it.

Rendered from `lib/features/media/presentation/seerr_issue_thread_screen.dart` (`SeerrIssueThreadScreen`) and `seerr_issue_thread_parts.dart` by `test/design_catalog/seerr_issue_thread_catalog_test.dart`. The files section reads `issue_files_provider.dart`.

## Where it lives

- Operator: `/stack/seerr/issues/:issueId`, inside the Issues tab. Requester: `/requests/issues/:issueId`, under her Requests tab. Both resolve from the path alone; `?i=` names the Seerr connection (an issue number is per instance), and none reads the lens.
- Opened by an Issues row, by the own-report row and the operator's issue rows on a title's page. A title opened from it lands under the same tab.

## Anatomy

- Back plate, then the title card (poster, title, `Movie · 2012 · on your server` or `S2 E3 · The Second Cycle`; the requester reads no `on your server`), tapped to open the title through `open_media.dart`.
- The report's words as the heading, then the state line: amber `Open` for the operator, blue `Reported` for the requester, green `Resolved` for both, with `Video · Luca · yesterday 21:40` (the requester's own report omits her name) or `… · resolved by you, Mon 28 Sep` from `modifiedBy`.
- `Replies` and the count, one bubble each: `You` for one's own reply, the person's name otherwise, never a service name. One's own reply has a ⋯ with `Edit reply` (in place: a field, `Cancel`, `Save`) and `Delete reply` (asks first), each as its verdict says.
- The composer: `Reply to <reporter>` (operator), `Reply to <last other author>` or `Add a detail` (requester), and its caption (who reads it).
- Operator: `Files it could be` (the copies the title page already reads: quality and size, the file name in mono, `Radarr 4K · imported yesterday`; an episode issue shows that episode's file; nothing for a season or a whole series), `Search a new release` (the app's release search for that copy; with several copies the title page's copy choice first), `Resolve` (primary) or `Reopen`, `Delete issue` and `Open in Seerr` (the connection's reached address + `/issues/<id>`). The files show only while the issue is open.
- Requester: `Mark as resolved` or `Reopen`, and `Delete report` only while the report is alone, with its caption.

## Verdicts and failures

Every control reads `RoleGate` (live, dimmed with the reason as hint and toast, or absent). A failed write keeps the words and says `Nothing was sent` or `Nothing changed`, with `Retry` where the same request can succeed; a reply deleted meanwhile reads the thread again; an issue deleted meanwhile reads `This issue is gone` (operator, `Back to Issues`) or `This report was deleted.` (requester). Every write reads the issue, the Issues list and the title's report rows again.

## Scenes

Operator open (with the files), an episode, resolved, the reply menu, editing, Delete reply and Delete issue asked (drawn on a scene-local navigator), an account that cannot manage, a reply that did not send, gone. Requester answered, just reported, resolved, Delete report asked, an account that may no longer report, gone. Both at twice the reading size.
