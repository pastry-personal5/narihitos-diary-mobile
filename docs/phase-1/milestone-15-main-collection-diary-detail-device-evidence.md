# P1-M15: Main collection and Diary Snippet detail device evidence

Status: Planned

This record captures redacted target-iPhone evidence for active-folder ordering/paging, provider refresh, bounded reads, recovery classification, Main/detail accessibility, and privacy. Use only synthetic diary and audio fixtures in a controlled iCloud Drive folder.

## Evidence rules

- Record device model, iOS version, app revision, active-folder test label, locale/time zone, appearance, accessibility settings, and observation time. Do not record account identifiers, bookmarks, full paths, diary text, titles, exact location, filenames, audio, or raw provider errors.
- Use bounded synthetic markers such as `fixture-a` only in the private test notes; committed evidence describes state classes, counts, ordering, and pass/fail observations without content.
- Record whether the iCloud files were local, downloading, uploaded, replaced, moved, or conflicted only at the coarse state needed for the scenario. Do not claim cross-device receipt from local readability.
- A simulator, preview, unit test, or screenshot alone does not satisfy a target-iPhone scenario. Automated evidence may supplement each row.
- For paging/resource claims, record sanitized counters, durations, peak memory, cancellation/settlement events, and the observation method. A smooth-looking scroll alone does not prove the 50-candidate budget or bounded buffers. Identify injected stalls separately from naturally observed provider behavior.
- Establish the legacy writer/specification or owner-confirmed sanitized example before deriving fixtures. Record its documentation reference, not personal source files. If it is unavailable, leave legacy evidence open rather than claiming guessed input represents the old format.

## Test setup

| Field | Value |
|---|---|
| Device model | Not recorded |
| iOS version | Not recorded |
| App revision | Not recorded |
| Locale / time zone | Not recorded |
| Active-folder fixture | Not recorded |
| Evidence date | Not recorded |
| Legacy format / fixture contract reference | [Owner-evidenced legacy contract](milestone-15-legacy-format.md); synthetic fixtures only |
| Instrumentation / injected-fault method | Not recorded |
| Supplementary simulator layout configurations | Not recorded |

## Scenario results

| ID | Scenario and observable pass condition | Result | Evidence note |
|---|---|---|---|
| M15-D01 | Use more than 100 synthetic entries spanning pages/local dates, equal timestamps, current and evidenced legacy timestamp precision, plus an initial all-recovery slice. Counter evidence shows at most 50 candidate visits per request including discovery/classification. Main distinguishes discovery/progress from empty/end, publishes normalized instant-descending/ID-ascending/resource-ascending ranges without duplicates or later ordering corrections, reaches the end, and keeps Record clear of list/safe areas. Repeat with no folder, a genuinely empty folder, and an all-recovery folder. | Not run | — |
| M15-D02 | Begin a page/detail read, then change the active folder and separately change iCloud identity/access. Every old cursor/callback is rejected, the prior collection clears, no former-folder item enters Main, and restored access loads only the currently selected folder. | Not run | — |
| M15-D03 | While Main/detail are open, add, replace, move, and remove files, including insertion ahead of a loaded cursor; temporarily make one resource unavailable. Refresh invalidates affected ordering/detail, a resource's new version replaces its old row, stale handles cannot open changed bytes, and a read failure never proves deletion. Repeat queue completion into the active folder and into a former active folder: only completion into the former active folder produces the approved separate banner; current-folder changes refresh through the catalog. | Not run | — |
| M15-D04 | Exercise supported, malformed, unsupported, incomplete, unsafe-reference, and duplicate-ID fixtures across page boundaries. Supported resources remain readable; each bad resource is isolated as typed recovery attention; distinct duplicates remain separate; and no bad candidate blocks the next page. | Not run | — |
| M15-D05 | Use fixture-backed legacy headers/names with zero/one/multiple plausible siblings, unsafe sibling types, and exact/one-over 64 MiB and 60 decoded-minute boundaries or failed decoding. Exactly one safe sibling permits read-only Main/detail; zero/multiple/unsafe pairing yields explained recovery without following unsafe resources. One unusable/oversize/overlong safe audio leaves safe text readable with audio unavailable. Source comparisons show no app writes/normalization; legacy exposes no Favorite/edit action and malformed v1 cannot downgrade. | Not run | — |
| M15-D06 | Exercise exact/one-over v1 byte/frame-duration limits, wrong format, unsafe type, digest mismatch, corrupt/truncated tails, false duration declarations, and Markdown/audio replacement during decoding and between list/detail. Only a stable pair reaching clean decoder end reports audio available. No playback authority escapes; unsafe/invalid v1 pairs become recovery, while download/access timeouts remain retryable. | Not run | — |
| M15-D07 | With processing, queued, and several recovery destinations present, observe processing/queued/recovery order, 10-second rotation, fair recovery subroutes, and polite announcements. Counts/progress must not restart the timer or announcements. Taps select All and the displayed destination. VoiceOver/Reduce Motion/inactivity pause rotation; full notice text remains accessible. The separate six-second former-folder banner is dismissible and does not obscure content/focus or reset notice timing. | Not run | — |
| M15-D08 | Inspect the target iPhone in light/dark, portrait/landscape, maximum Dynamic Type, VoiceOver, and app-switcher transitions; supplement with smaller/larger simulator layout checks. Bitmaps are sharp/tinted, labels/state/contrast/44-point targets are correct, and Title/body/Metadata reflow. Stored coordinates display without a place, weather uses locale units with attribution, unavailable groups/provenance stay hidden, inert text causes no link/HTML/remote fetch, and privacy cover/diagnostics reveal no sensitive content outside the visible accessible UI. | Not run | — |
| M15-D09 | Use a large single-day directory, irrelevant files, many bad candidates, long safe legacy audio, and controlled slow/stalled I/O. Record memory/buffer/work-slice and settlement observations. Main remains responsive and discovery advances without spinning; loaded pages retain summaries, not every body/audio. Navigate away, background, change folder, and inject memory pressure: results are fenced immediately, no retry accumulates unsettled accessors, and scope/observers release after settlement. A genuinely nonsettling operation remains truthfully unavailable; leave unresolved provider behavior open. | Not run | — |
| M15-D10 | Without a local pending job, introduce controlled unresolved provider versions, unpairable versions, and separate resources sharing one ID across pages. No unresolved/duplicate resource is presented as finished. Conflict and incomplete/duplicate reasons route separately with exact-version handles; no read repairs, chooses, removes, or merges source files. After a controlled external resolution and refresh, only the newly validated pair returns to Main. | Not run | — |

## Result

Target-iPhone evidence is not yet available. Every scenario remains open, so this record makes no device-behavior or milestone-completion claim.


## Supplementary automated evidence (2026-11-02)

Delegated `make lint` and the full `scripts/validate.sh` gate passed using `platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082`. Focused suites establish synthetic paging/order, legacy grammar/pairing, actual audio bounds, generation fences, notice state, and routing; the final full gate also covers the inherited application suites. The generated one-hour AAC focused test completed in 0.6206 seconds in the simulator. Icon manifests and dimensions passed for 24 template sets/72 PNGs. Documentation/link and whitespace checks passed.

These results do not close a row above. No target-iPhone scenario, user-picked-folder download/provider event, real conflict, WeatherKit attribution availability, VoiceOver/layout inspection, app-switcher observation, or device resource measurement is claimed. The personal examples established format only and were not used as automated test input.
