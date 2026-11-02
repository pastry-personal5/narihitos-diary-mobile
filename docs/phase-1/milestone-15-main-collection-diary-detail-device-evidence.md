# P1-M15: Main collection and Diary Snippet detail device evidence

Status: Planned

This record captures redacted target-iPhone evidence for active-folder paging, provider refresh, legacy/audio classification, Main/detail accessibility, and privacy. Use only synthetic diary and audio fixtures in a controlled iCloud Drive folder.

## Evidence rules

- Record device model, iOS version, app revision, active-folder test label, locale/time zone, appearance, accessibility settings, and observation time. Do not record account identifiers, bookmarks, full paths, diary text, titles, exact location, filenames, audio, or raw provider errors.
- Use bounded synthetic markers such as `fixture-a` only in the private test notes; committed evidence describes state classes, counts, ordering, and pass/fail observations without content.
- Record whether the iCloud files were local, downloading, uploaded, replaced, moved, or conflicted only at the coarse state needed for the scenario. Do not claim cross-device receipt from local readability.
- A simulator, preview, unit test, or screenshot alone does not satisfy a target-iPhone scenario. Automated evidence may supplement each row.

## Test setup

| Field | Value |
|---|---|
| Device model | Not recorded |
| iOS version | Not recorded |
| App revision | Not recorded |
| Locale / time zone | Not recorded |
| Active-folder fixture | Not recorded |
| Evidence date | Not recorded |

## Scenario results

| ID | Scenario and observable pass condition | Result | Evidence note |
|---|---|---|---|
| M15-D01 | Select a controlled user-created iCloud Drive folder with more than 50 valid synthetic Diary Snippets spanning multiple local dates. Main loads incrementally, never requests more than 50 candidates per page, preserves newest-first deterministic order without duplicates, reaches the end, and keeps Record/list content clear of safe areas. | Not run | — |
| M15-D02 | Begin a page/detail read, then change the active folder and separately change iCloud identity/access. Every old cursor/callback is rejected, the prior collection clears, no former-folder item enters Main, and restored access loads only the currently selected folder. | Not run | — |
| M15-D03 | While Main and detail are open, add, replace, move, and remove controlled files through Files or a second controlled client; also make one resource temporarily unavailable. Provider/foreground refresh invalidates the affected projection, never opens changed bytes under a stale handle, never treats failure as deletion authority, and continues loading other items. | Not run | — |
| M15-D04 | Exercise supported, malformed, unsupported, incomplete, unsafe-reference, and duplicate-ID fixtures across page boundaries. Supported resources remain readable; each bad resource is isolated as typed recovery attention; distinct duplicates remain separate; and no bad candidate blocks the next page. | Not run | — |
| M15-D05 | Exercise legacy Markdown with zero, one, and multiple safe plausible audio siblings plus one oversize/over-60-minute/undecodable audio fixture. Exactly one sibling yields a read-only Main/detail entry without file modification; zero/multiple yields recovery; and unsafe or unusable audio leaves safe text readable with audio unavailable. | Not run | — |
| M15-D06 | Exercise current-schema audio at the accepted boundaries and with wrong format, unsafe resource type, digest mismatch, oversize bytes, decoded duration over 301 seconds, truncation, and replacement between list/detail. Only a stable validated pair reports audio available; failures preserve files and expose no playback authority. | Not run | — |
| M15-D07 | With processing, queued, and recovery states present, observe the one-line notice order and 10-second rotation, routes, and polite announcements. Enable VoiceOver and then Reduce Motion: rotation pauses, focus/order remains usable, unchanged notices do not chatter, and the six-second former-folder banner remains dismissible and nonblocking. | Not run | — |
| M15-D08 | Inspect Main and detail in light/dark mode, portrait/landscape, small and large iPhone widths, maximum Dynamic Type, VoiceOver, and app-switcher transitions. Custom bitmaps remain sharp/tinted, all targets are at least 44 points, body/metadata reflow without clipping, inert Markdown causes no link/HTML/remote fetch, and the privacy cover/logs reveal no sensitive fixture content. | Not run | — |

## Result

Target-iPhone evidence is not yet available. Every scenario remains open, so this record makes no device-behavior or milestone-completion claim.
