# P1-M15: Main collection and Diary Snippet detail approach

Status: Planned

This plan adds a generation-fenced active-folder catalog behind Clean Architecture ports, then projects validated summaries and read-only details into Main. External files remain untrusted and presentation state remains disposable.

## Source boundaries and composition

Keep type-neutral catalog values and use cases in Domain/Application, active-folder coordination and file/audio decoding in Adapters, and list/detail/notice state in Presentation. Extend the existing composition root with an `AssetCatalogRegistry`: each registered kind supplies a bounded summary/detail decoder and presentation route. Diary Snippet v1 and its legacy reader are the only shipped handlers; a synthetic test handler proves extension without a global kind switch or a new runtime plugin feature.

The application-facing `AssetCatalogPort` should expose operations equivalent to:

- begin or refresh the current active-folder session;
- load the next bounded page from an opaque cursor;
- reopen one opaque item/version handle for detail; and
- publish typed invalidation/access/recovery events.

`CatalogSessionID`, `CatalogItemHandle`, and `CatalogCursor` bind the active `DestinationID`, destination/identity generation, provider resource identity/version, registry handler, and continuation state. They are bounded opaque values, not encoded URLs or deletion paths. The adapter may keep a session-local mapping to coordinated resources while active; it clears it on destination/identity change, inactivity, or memory pressure. Do not persist a content-bearing catalog cache in M15.

Extend the M8 destination adapter with a scoped active-folder catalog loan that reuses the positive iCloud/account predicate, balances security scope, and verifies the generation again after each coordinated operation. This is distinct from M14's capture-snapshot loan: it follows the current active selection and becomes stale immediately when Settings changes it. Application and presentation never receive the root URL.

## Candidate discovery and paging

Walk only plain directories beneath the active root without following aliases or links. In the existing UTC year/month/day hierarchy, discover canonical second-resolution and documented legacy millisecond layout stems. Coalesce a Markdown resource and the matching `.assets` directory as one candidate; an orphan on either side remains one recovery candidate, including an audio-only survivor. Ignore unrelated ordinary files for catalog presentation, but never recurse through unexpected resource types. Directory enumeration must be cancellable and incremental; a page stops after examining 50 coalesced candidates, even when some become recovery items rather than Main entries.

The cursor records continuation over a deterministic descending resource-name traversal plus the catalog generation. It is an observation aid, not authority. Before returning a page, the adapter coordinates each candidate read, verifies it is still the same plain file, and attaches a provider/file identity and version to the result. A stale cursor, changed generation, moved/replaced resource, or unbalanced provider loan returns a typed refresh/access outcome rather than partial results from another snapshot.

Sort accepted summaries by parsed `created_at` descending, then stable asset ID for v1 or ephemeral catalog ID for legacy, then resource identity to make collisions deterministic. The presentation model deduplicates only identical observations of the same resource/version. If a later page reveals a different resource with the same v1 asset ID, remove neither: reclassify both as separate ambiguous recovery projections. Regroup loaded entries from the original recording instant using `Calendar.autoupdatingCurrent`; a timezone/day change updates sections without rewriting or reinterpreting the UTC files.

Provider change observation stays behind an adapter port. Use coordinated/file-presenter signals to invalidate the affected item/page when possible and the whole session when the change cannot be localized. Refresh on foreground entry as a backstop. Coalesce notification bursts, but do not use elapsed time as proof that a resource is unchanged. A former-folder M14 completion event drives only its approved banner and never injects an item into the current session.

## Current-schema and legacy classification

For a current-schema candidate:

1. Open the Markdown with bounded coordinated, non-following access. Apply M7's 64 KiB front-matter, 1 MiB body, 64-key, and 8 KiB scalar rules.
2. Require supported codec output and require its asset ID/`created_at` to reproduce the exact canonical Markdown name, assets directory, and explicit audio filename. Unknown schema/kind/method/title origin is unsupported; malformed known-v1 data is malformed. Neither is rewritten.
3. Open the referenced audio only after validating every resource component and containment. Require one plain file no larger than 64 MiB, bind any declared audio digest, and inspect actual container/codec, decodability, and decoded duration no longer than 301 seconds. Do not trust extension or front-matter declarations as audio evidence.
4. Return a minimal summary for Main and an opaque exact-version detail handle. Detail repeats the coordinated identity/content checks before returning the full bounded body and metadata. M16 must obtain a fresh verified audio lease before playback; M15's availability result is not a long-lived URL.

Use M14's typed incomplete-pair classifier where its canonical layout input applies. Map unsupported, malformed, unsafe, missing, changed, and duplicate conditions to sanitized recovery reasons that retain the exact observed resource/version but grant no ownership. If an item changes between summary and detail, close the stale detail and refresh; do not silently open a replacement with the same asset ID.

The legacy reader recognizes only the documented pre-v1 envelope/body: no v1 `schema_version` or `kind`, a canonical legacy millisecond stem and UTC hierarchy, unique bounded legacy `id`/`created_at`/`updated_at` fields that agree with that layout, and a bounded body. A document that presents as v1 but fails v1 decoding remains malformed v1; it cannot fall back to legacy. Treat every legacy header field and Markdown byte as untrusted, ignore unneeded legacy syntax rather than constructing YAML objects, and use the Markdown resource path/version as an ephemeral session identity. Derive the list/detail display title with M13's bounded first-sentence fallback only, without AI or persistence. Within the matching sibling `.assets` directory, enumerate safe regular `.m4a` candidates without following links. Exactly one plausible sibling permits a Main entry. Zero or multiple candidates become recovery items. One candidate that exceeds 64 MiB, exceeds 60 decoded minutes, or fails decoding does not suppress safe text; detail reports audio unavailable. Legacy content is never fed to the v1 encoder, title generator, editor, Favorite writer, or commit store.

## Detail and inert content

Project a full detail value only after a successful exact-version reopen. For v1 it contains the saved Title, Favorite state, Diary body, recording start, declared duration/language hint, valid optional place/weather values, and typed audio availability. It deliberately excludes title provenance and raw unknown scalars. Legacy detail contains only safely decoded read-only values and explicit audio availability; it exposes no mutation capability.

Render Markdown with a native restricted presentation that preserves readable text structure while removing link actions, HTML/script execution, remote images, attachments, and automatic fetches. URL-looking text remains text. Do not place body/title/context into accessibility identifiers, navigation paths, logs, caches, or diagnostics. The existing neutral privacy cover must precede any nonforeground snapshot for collection and detail routes.

Lay out `Diary Snippet` in semantic reading order: Title and the current Favorite state, Diary body, then `Metadata`. M15 displays Favorite state but does not add a toggle intent. Metadata formats recording start with the user's current locale/time zone, duration with locale-appropriate components, and stored language hint without redetection. It omits invalid or unavailable optional groups. M18 supplies recording-time optional-context acquisition and any platform Weather attribution material; M15 must leave the bottom section able to accept that attribution without rearranging the approved order. M16 replaces typed audio availability with play/pause, seeking, elapsed/total controls after reacquiring a verified lease.

## Main presentation and notices

Use a native lazy list/section presentation so a page append does not instantiate the unbounded collection. The view model owns one catalog generation, loaded pages, a single in-flight next-page request, and retry/end state. Trigger the next page near the loaded tail, preserve stable item identity, prevent duplicate requests, and keep the loading row semantically busy without shifting existing focus. Record controls remain in a safe-area inset so the last list row and VoiceOver focus are not obscured.

Build `MainNoticeState` from semantic sources rather than display strings:

1. processing work while the app is open;
2. queued/pending work; and
3. known catalog/queue recovery attention.

Show one bounded line. With multiple states, advance every 10 seconds in that order. Stop the timer whenever VoiceOver or Reduce Motion is enabled, while the app is inactive, or while the notice is not visible. Restart from the highest-priority current state when the semantic set changes. Post one polite announcement for a newly introduced semantic state and deduplicate an unchanged state across timer cycles. Taps emit navigation intents: processing/queued opens Pending Recordings; recovery carries the typed M17 destination. M15 may route to the existing placeholder until M17 supplies its screen, but it must not flatten all recovery into one raw count or infer actions.

Replace M15-owned temporary system symbols with checked-in monochrome template bitmaps and consistent outline/filled variants. Keep visible labels and semantic names independent of filenames. Verify 1x/2x/3x raster sharpness, system tint in light/dark modes, 25/24/32 pt visual sizes, 44-point hit areas, Dynamic Type reflow, and VoiceOver focus order. Do not add a Main toolbar or animation that persists under Reduce Motion.

## Verification sequence

1. Add type-neutral catalog/session/page/detail/recovery values, the registry, and protocol fakes. Test a synthetic second kind, deterministic 50-candidate paging, equal-time ordering, local-calendar regrouping, duplicate observation versus duplicate asset ID, cancellation, and stale-generation rejection.
2. Add the active-folder scoped loan and coordinated catalog adapter. Test plain-directory confinement, links/aliases, target swaps, unexpected file types, folder/identity changes, provider failures, notification invalidation, resource replacement between summary/detail, and guaranteed scope release.
3. Add current-v1 and legacy classifiers plus actual audio inspection. Use checked-in synthetic Markdown and generated audio fixtures for every size/duration boundary, malformed/unsupported data, canonical-layout mismatch, digest mismatch, zero/one/multiple legacy siblings, decoder failure, and bad-item continuation. Verify no reader writes a source.
4. Add Main paging, notice state machine, detail projection, inert rendering, and M15-owned bitmap assets. Test navigation intents, loading focus stability, notice ordering/pause/announcements, omission rules, hidden provenance, legacy read-only behavior, privacy cover, light/dark mode, safe areas, Dynamic Type, VoiceOver, and Reduce Motion.
5. Run focused tests while iterating. At completion, delegate `make lint` and `TEST_DESTINATION=… scripts/validate.sh` to the required `test_runner`, then execute and record [M15-D01–M15-D08](milestone-15-main-collection-diary-detail-device-evidence.md) on a target iPhone with synthetic iCloud fixtures. A provider behavior that cannot preserve the approved bounded/safe outcome returns to owner review rather than weakening it.
