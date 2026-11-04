# P1-M21: Architecture enhancement and GUI enhancement overview

Status: Active

Enhance the software architecture and implement GUI enhancements requested by the owner. The initial architecture task reviews processing stages and active resource ownership. M21 follows M16 under the revised execution order; specific GUI requests are tracked below.

## Entry and locked inputs

- The owner revised the order on 2026-11-04 to M20 → M16 → M21 → M17 → M18 → M19 and requested an M21 task now against the implemented M16 handoff. Follow the [Phase 1 execution order](phase-1.md). This authorizes the bounded Task 2 work below; M16, M20, and earlier evidence remain open.
- Preserve the approved [product behavior](../product-behavior.md), [GUI](../ux-gui.md), [containment](../ux-information-architecture.md), [terms](../ux-terms.md), and [P1-M5 contracts](milestone-05-decisions-architecture.md), as amended by the owner's numbered GUI requests below. No title-progress display is requested.
- Use the implemented M10 queue, M13 draft/title stage, M14 commit, M15 catalog, and M20 maintenance/interaction repairs. Recheck the source inventory against the implemented M16 handoff; M17–M19 remain later work. M16 continues to own body editing, Favorite mutation, and audio replay; M17 owns complete recovery flows.
- Related undecided items remain unchanged: no new inference provider, runtime, quantization, hosted controls, dependency, build tool, or relaxation of approved safeguards.

## Remaining work and proposed order

M21 is Active. The checked implementation items below retain their recorded evidence; they do not close the unchecked visual, physical-device, or future implementation items. This plan review does not expand the owner's earlier implementation selections.

| Work | Status and bounded next step | Completion evidence |
|---|---|---|
| Task 1, Request 1 | Finish the two missing visual cases, then the physical interaction checks. Keep the inline warning visible in the confirmation capture rather than scrolling to Metadata. | Large portrait and dark largest-Dynamic-Type confirmation captures; physical VoiceOver, Reduce Motion, foreground/relaunch observations for current and legacy detail. |
| Task 3 | Implementation/simulator gate recorded; verify the actual system identity token on the target phone. | Sanitized console observation and saved-folder access after relaunch; record the round trip with M8-D04 without closing the rest of M8. |
| Task 4 | Implementation/simulator gate recorded; verify automatic save completion with real iCloud. | Record the app-active Pending → Main transition without manual Retry, offline → online and foreground/relaunch recovery, and preservation of pending work while verification is unavailable. Link M14 evidence; visible Files content alone is not upload proof. |
| Task 2 beyond 2a | Proposed only. Identify a concrete consumer before selecting broader lifecycle aggregation. | A bounded read-only reporting requirement, or an explicit deferral; existing owners remain authoritative. No new progress UI is selected. |
| Task 6 | Planning only. Start with baseline/design selection, then consider the staged implementation below. Evidence collection can proceed independently of the open GUI/device checks. | Per-stage checklists, source regression evidence, and comparable performance measurements; select implementation before changing code. |

After Task 6 selection, follow baseline → demand policy → ordered discovery/action prerequisites → validation reuse → device acceptance. Do not start cache work as a prerequisite for measuring the current bottleneck. Keep M16 and M20 evidence in their owning records; M17–M19 retain their assigned implementation scope and execution order.

## Task 1: Owner-requested GUI enhancements

Reserve this task for concrete owner requests. Before each implementation, add a numbered request with the affected screen, intended behavior, relevant existing contract, and verifiable acceptance checklist. Do not infer a redesign from the milestone title or the lifecycle review.

Each request should identify applicable navigation, accessibility, interaction, and state-restoration checks. Update the GUI/terms/containment docs and README when the delivered behavior changes them. Changes to an existing owner decision need the owner's direction before implementation.

### Request 1: Diary Snippet detail action and metadata layout

Requested on 2026-11-04: make Edit Diary full width, move the existing removal action (Delete Diary Snippet) directly below it, and put Metadata below the Audio controls. Preserve the M16 editor/replay behavior and M20 inline deletion confirmation, eligibility, and lifecycle fences. Legacy entries retain deletion and replay without Edit Diary.

- [x] Stack full-width Edit Diary and Delete Diary Snippet beneath the body, then Audio, then read-only Metadata.
- [x] Run the existing synthetic hosted detail/editor/replay/legacy and inline deletion activation checks; review small portrait, landscape, dark largest-Dynamic-Type detail, and light inline confirmation screenshots.
- [x] Update the owning GUI, containment, terms, README, and milestone approach; run lint and the full required simulator gate.
- [ ] Review large portrait and dark inline confirmation at largest Dynamic Type. Existing previews use 375 × 812 and 812 × 375 points; the dark confirmation preview scrolls past the relocated warning to bottom Metadata.
- [ ] Check physical-iPhone VoiceOver focus/reading order, Reduce Motion, and foreground/relaunch interaction. Simulator rendering and programmatic activation alone do not establish this evidence.

Request 1 implementation evidence, 2026-11-04 KST: `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` pass generation, lint, build, and all simulator tests on iPhone 18 Pro / iOS 27.0 using the `NarihitosDiary` project/scheme. The existing hosted suites exercise editing, Favorite, replay, legacy read-only behavior, full-width deletion, inline confirmation/Cancel, and scene disarming. Reviewed synthetic `m16-detail-light.png`, `m16-delete-button.png`, `m16-detail-dark-large.png`, `m16-detail-landscape.png`, and `m16-delete-confirmation-light.png`: Edit and Delete share the content width, Delete follows Edit, and Audio precedes Metadata. Restricted-shell CoreSimulator discovery failed with connection refusal; service-access discovery and the required gate then succeeded. No physical interaction or earlier milestone acceptance is closed.

## Task 2: Processing lifecycle architecture review

Review the [processing and queue lifecycle](../architecture.md#processing-and-queue-lifecycle) against current code. Document durable checkpoints separately from transient work and from resource settlement. The [approach](milestone-21-architecture-gui-enhancement-architecture.md) records the current evidence, the implemented Task 2a title-work snapshot, and the remaining broader lifecycle projection proposal.

The recommended enhancement makes title/draft work inspectable without inventing a durable `generatingTitle` queue state. Keep transcription, draft adoption/title inference, and commit as separate owners. A returned fallback can permit draft publication while cancelled title inference still owns resources; any projection must represent both facts. A lifecycle projection is read-only and grants no save, removal, or purge authority.

## Task 2a: Read-only shared title-work lifecycle

Selected on 2026-11-04 before implementation: extend the shared `DiaryTitlePolicy` with one bounded, transient snapshot and change callback. Report an operation ID, its recording attempt/revisions or independent edit submission ID, and generating versus timed-out-but-settling phase; absence means idle. Keep `hasActiveWork` tied to actual settlement. A competing fallback request must never replace the held owner's identity. This is the first bounded part of Task 2; whole-pipeline phase aggregation remains future work.

### Task 2a acceptance checklist

- [x] Expose a read-only snapshot and emit changes at work start, timeout fallback, and actual settlement, with no diary content or storage capability.
- [x] Supply recording attempt/body/destination revisions and separate edit submission identity from the existing callers; keep durable queue/journal formats and mutation checks unchanged.
- [x] Verify normal completion, fallback with held inference, competing recording/edit requests, stable owner identity, late-result fencing, busy ownership until settlement, and fresh identity after settlement.
- [x] Run existing candidate/draft restart, removal, maintenance, shared-title/edit, and commit regressions in the full simulator gate; record lint and gate results.
- [x] Reconcile architecture, milestone, phase order, and index documentation with the delivered subset. GUI behavior and physical-device evidence remain in their existing tasks.

Task 2a completed, 2026-11-04 KST: MobileBuildMCP focused execution reported 45 tests passed, zero failed/skipped across `DiaryTitlePolicyTests`, `DiaryDraftAdoptionTests`, and `DiaryEditTests`. The timeout regression exercises both recording-first and edit-first ownership. `make lint` and the required full `scripts/validate.sh` gate passed with `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082'` (iPhone 18 Pro, iOS 27.0); generation, lint, build, and tests all passed. Initial restricted-shell discovery failed with CoreSimulator connection/permission errors; service-access discovery and validation succeeded. No app change or simulator reset was needed for that restriction.

The [delivered subset](milestone-21-architecture-gui-enhancement-architecture.md#delivered-task-2a-shared-title-work-snapshot) and [architecture lifecycle](../architecture.md#processing-and-queue-lifecycle) describe the source contracts. Local Markdown link targets/header checks and `git diff --check` pass. README and UX were reviewed: this internal read-only seam changes no visible behavior, so their product descriptions need no update. No new physical-device or GUI acceptance is claimed, and M16's remaining evidence stays open. Broader lifecycle aggregation and owner-specified GUI requests remain future M21 work.

## Task 2b: Architecture state and deletion documentation review

Requested on 2026-11-04: review, correct, and enhance the software architecture document, concentrating on title generation and deletion. This is a documentation task against existing approved behavior and current source; no new state machine, persistence format, or GUI behavior is authorized by this review.

### Task 2b acceptance checklist

- [x] Compare queue, shared title, edit, recording-removal, committed-pair deletion, and purge owners with the approved contracts; record discrepancies and source evidence in the approach.
- [x] Document durable checkpoints, transient work, resource settlement, and presentation state separately, including title fallback and edit submission identity.
- [x] Replace obsolete deletion claims with distinct pending-recording removal, exact-pair Diary Snippet deletion, and maintenance purge contracts; explain confirmation, mutation fences, partial failure, and recovery.
- [x] Check changed documentation links/headings and whitespace; record validation results and any remaining milestone gate or device-evidence limitations without claiming new runtime behavior.

Task 2b completed, 2026-11-04 KST: the [review findings](milestone-21-architecture-gui-enhancement-architecture.md#task-2b-state-and-deletion-documentation-review) link the checked source and approved contracts. Local validation resolves 286 Markdown links/fragments across the architecture, M21 overview/approach, documentation index, and changelog, verifies title/status headers and coverage of all ten persisted queue cases, and confirms removal of the obsolete finished-deletion and destination-wait claims. `git diff --check` passes. `make lint` and the full `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` gate pass (project generation, lint, build, tests; iPhone 18 Pro, iOS 27.0). Initial restricted-shell CoreSimulator discovery failed; retry with service access and validation succeeded. This task changes documentation only and adds no runtime/GUI or physical-device acceptance; the remaining M21 GUI work and earlier evidence stay open.

## Task 2c: Documentation consolidation

Requested on 2026-11-04: remove repeated documentation, shorten `AGENTS.md` with links to the authoritative guides, and repair affected links. Preserve approved behavior, historical decisions, existing implementation edits, and outstanding evidence.

### Task 2c acceptance checklist

- [x] Replace duplicated product/setup/process detail in `AGENTS.md` with links while retaining agent workflow and approval boundaries.
- [x] Consolidate contributor and documentation rules in their owning guides; replace obsolete validation instructions and duplicated README repair history with links to milestone evidence.
- [x] Resolve stale cross-references and verify local Markdown targets/fragments, documentation index coverage, and whitespace.
- [x] Run `make lint` and the required simulator validation gate; record results without closing remaining GUI or device evidence.

Task 2c completed, 2026-11-04 KST: reduced `AGENTS.md` from 2,498 to 418 words and replaced repeated README/phase-plan repair history and schema detail with links to their owning records. Contributor setup, conventions, and simulator recovery now live in the contribution guide; documentation rules and exemptions live in the development process. Repaired stale architecture/agent anchors and UX decision references; the index covers every active `docs/` Markdown file. Local project-document link/fragment checks and `git diff --check` pass. `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` pass (generation, lint, build, tests; iPhone 18 Pro, iOS 27.0). Restricted-shell simulator discovery failed initially; discovery and validation succeeded with service access. This documentation task adds no runtime or physical-device acceptance; existing implementation edits and open GUI/device evidence are preserved.

## Task 3: Narrow iCloud identity decoding classes

Requested on 2026-11-04: reduce the runtime `NSKeyedUnarchiver` warning caused by allowing `NSObject` while comparing saved iCloud identity tokens. Preserve opaque `isEqual` comparison, existing archives, account-change fencing, and folder data. Derive the expected archive class only from the live system token's public coding metadata; never trust a class named by stored bytes or hard-code a private class name.

### Task 3 acceptance checklist

- [x] Replace the `NSObject` decoding allowance with the live token's coding class; fail closed when the identity or a suitably narrow class is unavailable.
- [x] Verify matching and different identities, existing non-secure archive compatibility, malformed input, unexpected root/nested classes, missing identity, and refusal of an `NSObject` coding class using synthetic tokens.
- [x] Run `make lint` and the required full simulator validation gate; record results and remaining target-iPhone warning/relaunch limitations.
- [x] Reconcile the implementation approach and owning identity-round-trip documentation without closing earlier physical-device evidence.
- [ ] Confirm warning disappearance and saved-folder access after relaunch on the target iPhone. This session has synthetic simulator evidence only; the M8-D04 physical-token round trip remains open.

Task 3 focused evidence, 2026-11-04 KST: MobileBuildMCP reports 44 passed, zero failed/skipped across `UbiquityIdentityDecodingTests`, `DestinationTransactionTests`, and `FirstLaunchAndDestinationTests` on iPhone 18 Pro / iOS 27.0. The focused test log contains no `allowed classes list contains` warning. `make lint`, 35 local Markdown links/fragments, and `git diff --check` pass. The [implementation approach](milestone-21-architecture-gui-enhancement-architecture.md#task-3-icloud-identity-decoding-class-restriction) records compatibility and remaining device limits. No GUI or user-data changes are involved.

Task 3 final gate, 2026-11-04 KST: `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` passes project generation, lint, build, and all simulator tests. Restricted-shell CoreSimulator discovery initially failed with connection refusal; service-access discovery and the full gate succeeded using the documented retry procedure. This closes simulator validation only; target-iPhone console/relaunch evidence remains unchecked above.

## Task 4: Automatically resume iCloud upload verification

Requested on 2026-11-04: recordings repeatedly reach Pending with iCloud verification needed; tapping Retry Verification then makes the Diary Snippet appear in Main. Find the cause and automatically retry transient verification, adding scheduling/state fixes as needed. Preserve the M14 requirement for separate exact-version upload proof and final unchanged-pair verification before durable `saved` or staging cleanup.

### Task 4 acceptance checklist

- [x] Reproduce delayed upload followed by successful verification and document the scheduling root cause with a failing regression before the repair.
- [x] Automatically retry transient upload/destination/protected-data waits with bounded backoff and fresh verification; avoid immediate loops, duplicate attempts, retranscription, and automatic recovery/conflict actions.
- [x] Fence scheduling on inactivity, maintenance, queue pause, removal, and job replacement; resume pending verification on foreground/relaunch and retain immediate manual Retry.
- [x] Verify delayed success, repeated waits/backoff, independent jobs, changed versions, recovery stops, suspension/resumption, and removal/maintenance races with deterministic synthetic tests.
- [x] Update architecture, behavior, GUI, README, and milestone evidence; run lint and the required full simulator gate.
- [ ] Verify the record → Pending → automatic Main transition against real iCloud on the target iPhone, including offline/foreground recovery. Simulator evidence alone cannot close this item.

Task 4 focused evidence, 2026-11-04 KST: the pre-fix delayed-upload regression failed with the job still `readyToSave`, one upload check, no scheduled retry, and no cleanup; the other 13 commit tests passed. After repair, MobileBuildMCP reports 39 tests passed, zero failed/skipped across `DiarySaveSchedulerTests`, `DiaryCommitTests`, and `AppleDiaryPairStoreTests` on iPhone 18 Pro / iOS 27.0. The strengthened completion regression starts with only one file's upload proof, obtains both on retry, then observes exactly one saved event and cleanup. `make lint`, 392 local Markdown links/fragments, and `git diff --check` pass. The [implementation approach](milestone-21-architecture-gui-enhancement-architecture.md#task-4-automatic-icloud-verification-retries) records the root cause, scheduling/ownership boundaries, and the app-active execution limit. No target-phone Files/upload timing or suspended-app execution is claimed.

Task 4 final gate, 2026-11-04 KST: `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` passes generation, lint, build, and all simulator tests. Initial restricted-shell discovery failed with CoreSimulator connection refusal; service-access discovery and the complete gate then succeeded using the documented retry. Earlier M14/M16 evidence remains open, as does Task 4's physical-iCloud acceptance above.

## Task 5: Icon contribution rule

Requested on 2026-11-04: document a preference for Apple's SF Symbols and related Apple design materials when creating icons, where suitable.

### Task 5 acceptance checklist

- [x] Add the icon rule to the contribution guide's code and repository conventions, allowing custom artwork when suitable Apple materials are unavailable.
- [x] Review the documentation change and check whitespace; record evidence without claiming runtime or device validation.

Task 5 documentation evidence, 2026-11-04 KST: the [contribution conventions](../contribution-guide.md#code-and-repository-conventions) now prefer Apple's SF Symbols and related Apple design materials where suitable and permitted, with custom artwork as the fallback. The test runner reviewed the wording and confirmed `git diff --check` passes. No lint, build, simulator, or device checks were run for this documentation-only task; this does not close the milestone's runtime or device gates.

## Task 6: Main Diary Snippet loading architecture plan

Requested on 2026-11-04: brainstorm and plan faster Main loading, considering the latest 10 entries followed by infinite scroll. The owner also suggested an in-memory database and caching. This task prepares the [catalog performance proposal](milestone-21-architecture-gui-enhancement-architecture.md#task-6-main-catalog-performance-proposal); implementation and any changes to approved Main eligibility remain unselected.

### Task 6 planning checklist

- [x] Trace discovery, classification/audio inspection, pagination, refresh, and mutation binding against current source; distinguish suspected costs from measured bottlenecks.
- [x] Compare smaller pages, ordered discovery, an in-memory indexed catalog/cache, deferred validation, and persistent indexing; recommend a staged approach with explicit cold/warm behavior.
- [x] Specify proposed boundaries, cache invalidation/lifetime, continuation, recovery, and unchanged mutation authority; record decision gates and acceptance criteria before implementation.
- [x] Delegate documentation link/fragment and whitespace checks and record their results.

### Task 6 future implementation acceptance

- [ ] Stage 0: record a reproducible baseline and select the implementation subset, latency/memory targets, cache budget, and existing-behavior constraints before coding; no database dependency or deferred-validation UX is selected by this plan.
- [ ] Stage 1: fill initial and subsequent demand in increments of 10 eligible summaries, including partial/recovery-only slices after some rows already exist. Stop at satisfied demand/end/typed wait; coalesce viewport events and provide accessible continuation without a footer-driven drain.
- [ ] Stage 2: introduce a scoped ordered catalog/frontier; prove latest-range ordering across handlers, bounded discovery/classification work, no older content reads when unnecessary, and resumable large-day/legacy-sibling discovery.
- [ ] Stage 2: retain complete-index action admission for the first delivery; finish any needed metadata discovery on demand without decoding intervening audio. Prove duplicate claims, fresh detail/action bindings, exact-resource old-entry edit/reopen, cursor invalidation, and external-change fences.
- [ ] Stage 3: prove exact-content validation reuse, retryable-outcome handling, source/conflict/sibling invalidation, settled access ownership, foreground/account/folder/maintenance fences, and memory-pressure rebuild without truncating the collection.
- [ ] Stage 4: compare identical baseline/final fixtures and cache states; record target-iPhone latency, memory, real-iCloud availability, recording/transcription responsiveness, Dynamic Type, VoiceOver and scroll/navigation evidence. Run affected regressions, lint, and the full required simulator gate for delivered code.

Planning only: no app code, file schema, dependency, Main eligibility, or existing validation result changes. Source inspection does not establish actual load times. The broader M21 and earlier milestone gates remain open.

Task 6 planning evidence, 2026-11-04 KST: the test runner checked 336 local Markdown links/fragments across the changed documentation with zero errors, confirmed title/status structure and Task 6 sections, and reported that `git diff --check` passes. Its contract review found no contradictions with the current 50-visit bound, Main eligibility, action gates, or disposable cache semantics. No Swift lint, build, simulator tests, phone measurements, or runtime acceptance was performed for this documentation-only proposal. Pre-existing Task 5/contribution-guide edits remain preserved.

## Task 7: Upcoming-task plan review

Requested on 2026-11-04: review M21 and fix or enhance the remaining task plans. This task updates planning documents against current source and approved contracts; it does not select Task 6 implementation or approve new product behavior.

### Task 7 acceptance checklist

- [x] Recheck open GUI, identity, upload-verification, and lifecycle work; give each a bounded next step and preserve earlier evidence ownership.
- [x] Correct Task 6 demand, ordering, work-budget, retry, action-binding, cache, and memory-pressure gaps using current source references.
- [x] Split future implementation into verifiable stages with selection gates, regression scenarios, and reproducible performance evidence.
- [x] Check affected documentation links, status/checklist consistency, and whitespace; run required lint/simulator validation and record any blockers separately from planning completion.

Task 7 review evidence, 2026-11-04 KST: the approach's review findings trace the corrected plan to the catalog source and M15 contract. Checks resolve 352 local Markdown links/fragments across the five affected documents, verify title/status structure and Task 6/7 coverage, and confirm future implementation items remain unchecked. `git diff --check` and `make lint` pass. The first full simulator gate passed generation/lint/build but reported `CatalogModelTests.hiddenCollectionDoesNotPrefetchAndExhaustedEmptyPageBecomesEnd` terminated by a signal; its result bundle reports no assertion failure. All eight `CatalogModelTests` then passed in isolation through MobileBuildMCP. A fresh full `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` run passed generation, lint, build and tests on iPhone 18 Pro / iOS 27.0. The termination's cause remains unestablished. Restricted-shell CoreSimulator discovery initially failed; service-access validation succeeded using the documented retry procedure. This review changes documentation only; independent workspace edits were preserved. No phone measurements, new runtime behavior, or Task 6 implementation acceptance is claimed.

## Out of scope

An unsolicited GUI redesign, new exact progress copy, a title editor, automatic regeneration when a model becomes ready, new durable queue states or schema migrations, a global replacement state machine, broad repository restructuring, dependencies/build-tool changes, and M16–M19 implementation. M21 does not waive earlier phone or adversarial evidence.

## Completion checklist

### Planning and documentation evidence

- [x] Add linked overview/approach documents and align the phase plan and M16 entry condition with the owner-revised M20 → M16 → M21 → M17 → M18 → M19 execution order.
- [x] Compare the architecture lifecycle with queue, candidate, title/adoption, commit, and presentation code; record concrete mismatches and source/test references in the approach.
- [x] Update the architecture lifecycle to show `resultReady`, title/draft work, verified `readyToSave`, commit/upload proof, and fallback-versus-settlement semantics without presenting proposed APIs as implemented.

### Implementation and acceptance

- [ ] Record each concrete owner GUI request and its acceptance checklist before implementation; complete the requested changes with reviewable visual/interaction evidence.
- [x] Review Task 2's proposed lifecycle projection at implementation entry and record the selected bounded change, or an evidence-backed decision to retain existing interfaces. Any selected change separates durable job state, transient phase, and unsettled ownership without adding persisted title states or mutation authority.
- [x] For lifecycle changes, verify durable candidate handoff, restart from candidate or verified draft, fallback within the title budget, late-result fencing, no overlapping title inference, and busy ownership until actual settlement. Other ready transcription and save work must retain independent progress.
- [ ] Verify affected GUI behavior with synthetic data, including applicable small/large iPhones, landscape, largest Dynamic Type, VoiceOver, Reduce Motion, foreground/relaunch, and processing/recovery states. Record required target-iPhone evidence separately; unavailable evidence stays unchecked.
- [ ] Complete Task 3's physical-token and Task 4's real-iCloud acceptance; record Task 6's selected/delivered subset or explicit deferral and the broader Task 2 disposition before marking M21 Done. Checked historical gates do not complete future code or device work.
- [x] Reconcile affected architecture, UX, README, milestone, and index docs with delivered behavior; record compatibility with M16's edit/title boundaries and any remaining evidence in its owning milestone.
- [x] Run `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` on the implemented changes and record the destination/results. Unavailable required checks remain unchecked with the observed blocker.

Planning evidence (2026-11-03): the [source inventory](milestone-21-architecture-gui-enhancement-architecture.md#current-code-review-2026-11-03) records the inspected boundaries. Local links across the seven affected/new planning documents resolve, their referenced Markdown headings exist, both new documents have title/status headers, and `git diff --check` passes. At that planning checkpoint no new runtime, simulator, or physical-device acceptance was claimed. The 2026-11-04 Task 2a work and gate are recorded in its task section above.
