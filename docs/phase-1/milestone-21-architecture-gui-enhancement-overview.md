# P1-M21: Architecture enhancement and GUI enhancement overview

Status: Active

Enhance the software architecture and implement GUI enhancements requested by the owner. The initial architecture task reviews processing stages and active resource ownership. M21 follows M16 under the revised execution order; specific GUI requests are tracked below.

## Scope revision, 2026-11-11 (owner decision)

Tasks 11–14 (reconciliation worker, remembered-first presentation, projection updates/invalidation, prototype comparison) are **Deferred behind a measurement gate**; they supersede the 2026-11-04 instruction to deliver them in order. Task 10's foundation, the Task 11 controller and the Task 13 purge-generation safeguards already exist unwired and stay in the tree, disabled and unreferenced from production paths. See [Task 16](#task-16-catalog-measurement-gate). Task 9's independent remainder stays active, limited to activation coalescing and demand-based readiness. The documentation-consolidation items in Tasks 2b/2c are low priority and may be closed with an explicit disposition. Task 8 (missing Main title under the notice) remains required.

## Entry and locked inputs

- The owner revised the order on 2026-11-04 to M20 → M16 → M21 → M17 → M18 → M19 and requested an M21 task now against the implemented M16 handoff. Follow the [Phase 1 execution order](phase-1.md). This authorizes the bounded Task 2 work below; M16, M20, and earlier evidence remain open.
- Preserve the approved [product behavior](../product-behavior.md), [GUI](../ux-gui.md), [containment](../ux-information-architecture.md), [terms](../ux-terms.md), and [P1-M5 contracts](milestone-05-decisions-architecture.md), as amended by the owner's numbered GUI requests below. No title-progress display is requested.
- Use the implemented M10 queue, M13 draft/title stage, M14 commit, M15 catalog, and M20 maintenance/interaction repairs. Recheck the source inventory against the implemented M16 handoff; M17–M19 remain later work. M16 continues to own body editing, Favorite mutation, and audio replay; M17 owns complete recovery flows.
- Related undecided items remain unchanged: no new inference provider, runtime, quantization, hosted controls, third-party dependency, build tool, or relaxation of approved safeguards. Tasks 10–14 select only the system-SQLite prototype described below.

## Remaining work and proposed order

### Plan consolidation checklist

- [x] Remove future work duplicated by Tasks 10–14 and assign each retained catalog requirement to its selected task.
- [x] Preserve independent GUI, lifecycle, identity, upload-verification and device obligations; keep superseded planning evidence separate from implementation completion.
- [x] Align the overview, approach, phase entry and index; validate local links, task references and whitespace, and record evidence limits.

Consolidation evidence, 2026-11-04 KST: 379 local Markdown links/fragments, including incoming M21 links, resolve with zero errors. Comparison with the pre-review documents confirms Tasks 1–5, 7 and 8 are unchanged and every Tasks 10–14 implementation item remains unchecked. Task 6's separate future stages and Task 9's duplicate catalog/database acceptance are removed; their continuing requirements are assigned below. `git diff --check`, `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` pass generation, lint, build and tests on iPhone 18 Pro / iOS 27.0 after the documented service-access retry. This change updates plans only; no SQLite implementation, phone benchmark or earlier device acceptance is completed.

M21 is Active. The checked implementation items below retain their recorded evidence; they do not close the unchecked visual, physical-device, or future implementation items. This plan review does not expand the owner's earlier implementation selections.

| Work | Status and bounded next step | Completion evidence |
|---|---|---|
| Task 1, Request 1 | Finish the two missing visual cases, then the physical interaction checks. Keep the inline warning visible in the confirmation capture rather than scrolling to Metadata. | Large portrait and dark largest-Dynamic-Type confirmation captures; physical VoiceOver, Reduce Motion, foreground/relaunch observations for current and legacy detail. |
| Task 3 | Implementation/simulator gate recorded; verify the actual system identity token on the target phone. | Sanitized console observation and saved-folder access after relaunch; record the round trip with M8-D04 without closing the rest of M8. |
| Task 4 | Implementation/simulator gate recorded; verify automatic save completion with real iCloud. | Record the app-active Pending → Main transition without manual Retry, offline → online and foreground/relaunch recovery, and preservation of pending work while verification is unavailable. Link M14 evidence; visible Files content alone is not upload proof. |
| Task 2 beyond 2a | Proposed only. Identify a concrete consumer before selecting broader lifecycle aggregation. | A bounded read-only reporting requirement, or an explicit deferral; existing owners remain authoritative. No new progress UI is selected. |
| Task 8 | Independent pending-notice/title repair; planning only. Confirm the containment cause before changing layout. | Notice present/absent/rotating layout and navigation-title evidence, focused regression and separate physical accessibility checks. |
| Task 9, independent remainder | Proposed only. Select activation, private-store recovery or model-readiness changes only where measurements justify them. Its catalog/database work is absorbed into Tasks 10–14. | Reuse Task 10's baseline; prove current-generation activation, serialized storage and integrity-preserving readiness without delaying automatic processing. |
| Tasks 10–14 | Implementation active. Synthetic Release baseline and frozen budgets are recorded; the Task 10 SQLite foundation passes the simulator gate. Reconciliation, purge integration, remembered presentation and final comparison remain open. | Complete the store, reconciliation, presentation, mutation/rebuild and benchmark tasks below without making SQLite authoritative or granting actions from stale rows. |
| Task 15 | Manual creation and its simulator gate are delivered; compact custom bitmap Save/Cancel actions occupy the editor top right. Physical interaction and real-iCloud acceptance remain open below. | Main entry left of English Record, editor/save/cancel behavior, compatible text-only publication and action support, and keyboard/accessibility/provider evidence. |

Task 6 has no separate implementation backlog: its paging, discovery, validation and measurement requirements now belong to Tasks 10–14. Task 9 retains only work those tasks do not deliver: activation coalescing, private-store recovery scheduling and competing model-readiness work. Do not schedule a second memory-catalog implementation or repeat the catalog/database comparison after the selected prototype. If the prototype is rejected, retain the strict file fallback and explicitly replan any further optimization.

Keep M16 and M20 evidence in their owning records; M17–M19 retain their assigned implementation scope and execution order. Task 8's pending-notice/title repair and Tasks 1–4's open acceptance remain independent of the catalog prototype.

For Tasks 10–14, follow baseline and budget record → SQLite foundation → event/reconciliation worker → mutation/rebuild and purge fences → remembered-first presentation → device acceptance. Task numbers identify ownership, not permission to expose Task 12 before Task 13 safeguards. A warm remembered page may ship only after its scope, privacy, fresh-action and rebuild safeguards pass; the baseline is evidence for acceptance, not a gate that reopens the selected engine or presentation policy.

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

Requested on 2026-11-04: brainstorm and plan faster Main loading, considering the latest 10 entries followed by infinite scroll. The owner also suggested an in-memory database and caching. This task prepared the [catalog performance proposal](milestone-21-architecture-gui-enhancement-architecture.md#task-6-main-catalog-performance-proposal); implementation and Main-eligibility changes were unselected at that checkpoint. Tasks 10–14 now own its continuing requirements under the selected persistent SQLite prototype and remembered-first presentation.

### Task 6 planning checklist

- [x] Trace discovery, classification/audio inspection, pagination, refresh, and mutation binding against current source; distinguish suspected costs from measured bottlenecks.
- [x] Compare smaller pages, ordered discovery, an in-memory indexed catalog/cache, deferred validation, and persistent indexing; recommend a staged approach with explicit cold/warm behavior.
- [x] Specify proposed boundaries, cache invalidation/lifetime, continuation, recovery, and unchanged mutation authority; record decision gates and acceptance criteria before implementation.
- [x] Delegate documentation link/fragment and whitespace checks and record their results.

### Task 6 disposition: absorbed into Tasks 10–14

The owner-requested plan cleanup removes the separate future implementation stages. Task 10 owns the baseline, budgets and indexed store; Task 11 owns ordered discovery, work bounds and strict validation; Task 12 owns 10-row demand, continuation and fresh action/detail binding; Task 13 owns invalidation, memory pressure and rebuild; Task 14 owns comparative and device acceptance. The [selected catalog requirements](milestone-21-architecture-gui-enhancement-architecture.md#catalog-demand-discovery-and-validation-requirements) retain the detailed correctness constraints. The memory-only catalog and strict-only presentation alternatives are superseded. Planning evidence below remains historical; this absorption records no implementation pass.

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

## Task 8: Main pending notice containment and navigation-title visibility

Requested on 2026-11-04: fix the Main `pending ...` notice so it fits naturally with the Diary Snippet list and does not hide the `Main` title. Source inspection finds the notice attached as a top `safeAreaInset` around the catalog `List`, while the `Main` navigation title is attached to the same content tree. This is the leading layout hypothesis, not yet a confirmed runtime root cause.

### Task 8 planning checklist

- [ ] Reproduce the missing-title state with a pending notice and capture a focused hierarchy/layout trace or screenshot at small portrait, large Dynamic Type, dark mode, and with notice rotation; compare with the no-notice state.
- [ ] Confirm whether the top `safeAreaInset`/navigation-bar containment causes the title displacement or occlusion; inspect safe-area frames, navigation-title presence, and list content bounds before changing layout.
- [ ] Place the notice in the catalog's list composition or another navigation-safe list-header boundary so it reads as part of the Diary Snippet list, remains a full-width 44-point accessible action, and does not compete with the navigation bar.
- [ ] Preserve notice rotation/category routing, pending/recovery copy, privacy behavior, list refresh/loading/empty states, and the existing `Main` title; do not introduce progress-title UI or change Main eligibility.
- [ ] Add a focused presentation regression covering notice absent/present/rotating states, title visibility, list placement, accessibility label/hint, 44-point target, Dynamic Type, and navigation to Pending Recordings.
- [ ] Review representative light/dark screenshots and run `make lint` plus the full required simulator gate; keep physical VoiceOver, Reduce Motion, and target-iPhone evidence separate and unchecked until performed.

Planning only: no code, product copy, navigation contract, or Main eligibility change is selected by this task. The exact root cause and final containment API remain implementation findings, subject to the existing GUI contracts.

Task 8 planning evidence, 2026-11-04 KST: source inspection identified `MainView`'s top `safeAreaInset` and `MainNoticeView`'s one-line, full-width notice as the relevant boundary. No runtime reproduction, screenshot, build, simulator test, or physical-device validation was performed.

## Task 9: Launch and app-return responsiveness brainstorm

Requested on 2026-11-04: brainstorm an M21 task to speed up launch and switching back to the app, including possible architectural changes. The owner identifies `Loading Diary Snippets` and its waiting indicator as the symptom. The [launch and app-return proposal](milestone-21-architecture-gui-enhancement-architecture.md#task-9-launch-and-app-return-responsiveness-proposal) reviews activation, private-storage recovery and model-readiness competition. Catalog/database implementation and comparison now belong solely to Tasks 10–14. The independent remainder below is proposed, without measured phone bottlenecks or selected implementation.

Owner follow-up, 2026-11-04: consider an on-device database. The original comparison considered SQLite, SwiftData and Core Data. The [selected database plan](milestone-21-architecture-gui-enhancement-architecture.md#on-device-database-option) now belongs to Tasks 10–14; engine comparison and memory-only implementation are no longer pending Task 9 work.

### Task 9 planning checklist

- [x] Trace initial view construction, activation/deactivation, catalog reset/discovery/classification, private-store recovery and Apple/Cohere readiness; relate them to the reported waiting indicator.
- [x] Compare bounded lifecycle/storage changes with catalog caching and broader storage changes; record a recommended order and preserve existing owners and contracts.
- [x] Define measurement boundaries, staged acceptance and decisions required before implementation; keep performance claims separate from source evidence.
- [x] Consider a persistent on-device database, including engine tradeoffs, source authority, indexed paging, reconciliation, protection/rebuild and strict-versus-cached presentation choices.
- [x] Validate affected documentation links/fragments and whitespace; record the result below.

### Task 9 independent future implementation acceptance

- [ ] Reuse Task 10's baseline and Task 14's measurement protocol to select any justified activation, private-store or readiness subset and its numerical budgets. Catalog baseline collection, database comparison and catalog acceptance are no longer separate Task 9 work.
- [ ] Coalesce initial-task/scene-active entry into one activation per current generation; prove late completion cannot restart catalog, readiness publication or processing after inactivity, account/folder replacement, protected-data loss or maintenance. Cancellation must retain ownership until work settles.
- [ ] Remove measured unrelated work from Main's critical path while checking the purge barrier and current destination before access. If storage work moves off the main actor, retain serialized journal ownership, durable acknowledgments, revision checks, capture recovery and oldest-ready automatic processing without user navigation or scrolling.
- [ ] Make readiness checks demand-based and share concurrent verification of the same installation when selected. Prove integrity before model use, Q4/Q5 isolation, Q5 runtime safeguards, failed-read retry and cancellation settlement; browsing must not wait for unrelated model checks.
- [ ] For any selected independent change, compare the same cold/return fixtures with empty/pending/completed-history stores and zero/one/both Cohere variants installed. Verify privacy cover, capture-through-switching, automatic queue progress, edits, save retries and purge recovery. Reuse Task 14 evidence where it covers the same delivered revision; run affected regressions, lint and the full required simulator gate for new code and keep physical evidence separate. Record an explicit deferral if no independent change is justified.

Planning only: app behavior, schemas, storage authority and existing validation results are unchanged. No runtime profiling, phone timing or performance improvement is claimed.

Task 9 planning evidence, 2026-11-04 KST: checked 228 local links/fragments across the M21 overview/approach and phase changelog, title/status structure and unchecked future acceptance; all pass, as does `git diff --check`. No Swift lint, build, simulator tests or phone profiling were run for this brainstorm. Existing Task 8 planning edits are preserved; runtime and device acceptance remain open.

Task 9 database follow-up evidence, 2026-11-04 KST: reviewed SQLite's local-cache/index/WAL documentation and Apple's persistence/background/protection documentation; checked 232 local links/fragments, five evidenced planning items and seven unchecked implementation items across the same three documents. Documentation checks and `git diff --check` pass. No database prototype, dependency/build change, runtime test or phone performance measurement was performed.

## Task 10: Persistent SQLite catalog foundation

Selected by the owner on 2026-11-04 for an M21 prototype. Add a rebuildable, on-device system-SQLite read model for Main summaries and discovery metadata. iCloud files, commit records and existing journals remain authoritative. SQLite is an adapter detail, not a new diary format or a dependency for recording, transcription, save, edit or deletion success.

### Tasks 10–14 plan-review checklist

- [x] Check the selected plan against current catalog handles, ordering, complete-index action admission, lifecycle settlement and purge roots; document concrete gaps and corrections.
- [x] Specify remembered-row identity, race-safe reconciliation, pagination, failure fallback, purge/rebuild sequencing and measurable acceptance without changing approved product decisions.
- [x] Validate changed documentation links, whitespace and consistency through the delegated runner; retain implementation and device evidence as unchecked future work.

### Task 10 acceptance checklist

- [ ] Record the single shared baseline and numerical first-remembered-page, eventual-current-page, main-thread, memory and disk budgets before implementation, using Task 14's protocol; retain comparable current-catalog fixtures and attribute activation, private-recovery and model-verification costs for Task 9's independent remainder.
- [x] Add a storage-neutral application port and one serialized non-main SQLite owner. Confirm target SDK/module/link integration without a third-party package; keep SQL, connections, statements and relative resource locators inside the adapter.
- [x] Define a versioned schema for scope, resources, nonunique identity claims, timeline ordering, source/validation observations and scan coverage. Use the [reviewed identity and query contract](milestone-21-architecture-gui-enhancement-architecture.md#tasks-1014-reviewed-implementation-contract): separate persistent row identity from session action handles, preserve Swift timestamp/string ordering, and prove index use with tied/Unicode/legacy fixtures. Query the latest 10 by keyset and support subsequent increments of 10 without sorting the whole catalog or using large offsets.
- [x] Store no diary body, audio, bookmark, live file handle, coordinate, credential or queue/edit/commit truth. Treat title, Favorite and relative locators as protected data; exclude the database and every journal/WAL/SHM/temp artifact from backup and cloud sync.
- [ ] Prove atomic transactions, bounded busy/error mapping, interrupted open/write recovery, schema mismatch and corruption discard/rebuild. Keep protection/permission/I/O/full-disk failures retryable rather than treating them as corruption; disable the projection and use the strict file catalog when it cannot be used safely. Database failure must not change or roll back an authoritative file operation.

### Implementation entry and baseline record

Implementation authorized by the owner on 2026-11-04: deliver Tasks 10–14 in their dependency order (10 → 11 → 13 safeguards → 12 → 14), then Task 9. Existing acceptance checklists above remain the completion gates. Prepare instrumentation and synthetic benchmarks before the prototype; freeze numerical budgets after recording the baseline. Existing documentation edits are preserved.

- [x] Add aggregate catalog enumeration/read/decode/hash diagnostics and deterministic synthetic scale/playable-audio fixtures without personal data or production behavior changes.
- [x] Run comparable baseline fixtures in Release on the simulator and connected target iPhone without a debugger; record samples, source/configuration and evidence limits.
- [x] Freeze latency, work, memory, disk and regression budgets before introducing the SQLite prototype; record unavailable provider/UI measurements explicitly.

Entry evidence, 2026-11-04: the [benchmark record](milestone-21-catalog-benchmark-results.md) records source/configuration, 55 passing target-phone samples, 55 simulator samples, the system SQLite module/link preflight, frozen limits and missing provider/UI/resource evidence. Simulator focused validation also passes nine existing file-worker/diary-handler regressions. `make lint` passes. These are preparation results; they do not check off the composite Task 10/14 acceptance items or claim a prototype speedup.

Foundation progress, 2026-11-04: `CatalogIndexPort`/`CatalogRememberedRow` separate persistent identity from live handles; `SQLiteCatalogIndex` serializes blocking SQL off the main actor. Schema v1 has scoped metadata, nonunique claims, a Swift-string timeline index, historical observations and coverage records. Current checks cover differential Unicode/precision/legacy ordering, indexed keyset pages, cursor/session fences, invalidation races, retryable refresh retention, protected-access refusal, safe-path failures, bounded busy/full errors, atomic metadata batches, missing scope metadata and a copied hot-journal recovery image. `make lint` and the full required `scripts/validate.sh` gate pass on iPhone 18 Pro / iOS 27.0. All 11 focused SQLite tests pass in Release on the target iPhone / iOS 27.0.1 using real Complete Protection and verified backup exclusion; artifact `test_device_2026-11-04T10-13-57-338Z_pid40894_0248d091.xcresult`. An earlier locked-phone/preflight run ended before test connection and is not a pass. Main still uses the strict file catalog: Tasks 11/13 integration must precede Task 12 display. The complete first-frame/provider/resource baseline and strict fallback integration remain open, so the other composite Task 10 items remain unchecked.

## Task 11: Catalog reconciliation worker

Introduce one dedicated, generation-fenced worker that maintains the projection after the initial query. It reconciles current iCloud observations while the app is active; it is not a `BGTaskScheduler` promise and need not run while suspended or terminated.

### Task 11 acceptance checklist

- [ ] After maintenance, protected-data and current account/folder checks, query remembered candidates and start newest-range reconciliation without blocking Main on a whole-folder import.
- [ ] Reconcile additions, replacements, deletions, duplicate asset-ID claims, conflicts, legacy siblings and current Favorite/title observations. Retire a missing row only after the corresponding current enumeration completed; cancellation, offline state and partial scans never imply deletion.
- [ ] Consume successful save/edit/Favorite/delete callbacks and file-presenter/provider notifications as hints, fencing earlier in-flight scan results with per-resource revisions and dirty coverage before applying them. Activation and relaunch reconciliation cover missed or coalesced external changes. Coalesce bursts and maintain one writer/generation per scope.
- [ ] Deliver the [catalog discovery and validation requirements](milestone-21-architecture-gui-enhancement-architecture.md#catalog-demand-discovery-and-validation-requirements): 50 combined candidate visits per request, separate enumeration/provider/decode budgets, resumable cross-handler frontier, typed waits/retries and exact-content proof rules. Publish bounded diffs and continue toward the latest 10 before older demand.
- [ ] Prove fair bounded metadata reconciliation beyond the visible range, including unknown-date/recovery resources and missed external changes; do not decode all historical audio as an idle task. Document retry triggers and finite settled-fixture convergence.
- [ ] Fence late work across inactivity, account/folder replacement, maintenance, purge, protected-data loss and worker replacement; reject old-generation publication immediately and settle connections/file access before replacement work starts.

Worker/controller progress, 2026-11-04: schema v2 adds scan presence and invalidation revisions to the Task 10 foundation. Newest-first directory discovery, bounded legacy-sibling preparation, current-file inspection, checked absence retirement and periodic metadata reconciliation are implemented behind an unwired indexed adapter. The first controller/worker/legacy/SQLite run passes 21 Release simulator tests (`test_sim_2026-11-04T11-24-20-177Z_pid17401_18b02c44.xcresult`), including cached-first startup, one provider loan, actual settlement, failed-cache fallback and missed deletion. Four additional race/oracle checks and subsequent generation guards remain under validation. Mutation/purge integration, presentation and the full acceptance matrix remain open; Main still uses the strict file catalog.

## Task 12: Remembered-first Main presentation

Selected presentation policy: after current account/folder scope is verified and protected local data is available, show the latest remembered summaries immediately and validate them silently in the background. Normal warm reconciliation adds no global checking banner, stale badge, progress title or empty-screen spinner. This deliberately permits remembered rows to be temporarily stale; it does not make them current or actionable.

### Task 12 acceptance checklist

- [ ] Require Task 13 invalidation, purge/restart and fallback safeguards before enabling remembered presentation. Represent remembered versus freshly validated state internally while keeping stable row identity and scroll position as atomic diffs insert, update, reorder or remove rows. The first query returns at most 10; scrolling requests keyset pages of 10.
- [ ] Do not expose remembered rows until the current account/folder binding is verified. If scope, protection or destination access cannot be verified, use the existing unavailable/restore/privacy behavior and do not reveal another scope's titles.
- [ ] Grant detail/edit/Favorite/replay/delete only from a fresh current resource binding. Keep complete current metadata discovery/unique-claim admission for edit/Favorite/replay/delete, and existing exact-pair/version checks at execution; no stored handle can be restored. A tap on an unvalidated remembered row performs demand-priority validation, then opens the current item or uses an existing typed unavailable/recovery outcome; it never acts on a stale locator or cached validation result.
- [ ] Verify snapshot-bound continuation under insert/delete/reorder and repeated viewport events: no duplicate/omitted rows after settled refresh, no unbounded footer demand, and no terminal-empty claim from partial coverage.
- [ ] Fill unmet demand in increments of 10, including partial and recovery-only slices after rows exist; stop on satisfied demand, end or typed wait. Provide accessible continuation, coalesce viewport events and verify 3 → 10 → 20 without a footer-driven drain. Reopen an older edited item through its exact scoped resource without reading every intervening summary.
- [ ] Reconcile silently during normal warm use: no checking UI and no replacement empty overlay while remembered rows exist. Preserve existing loading behavior for an empty/rebuilt cache, and existing typed notices when current truth requires user action.
- [ ] Verify warm launch/return, stale update/delete/reorder, newly added newer rows, offline/evicted files, empty-to-populated and remembered-to-empty transitions, rapid scrolling, Dynamic Type, VoiceOver, Reduce Motion and privacy-cover behavior.

## Task 13: Projection updates, invalidation and rebuild

Connect authoritative mutations and lifecycle events to the catalog without turning it into a transaction participant for diary writes. Rebuild or discard only this projection; never touch diary assets or existing recovery journals to repair it.

### Task 13 acceptance checklist

- [ ] After an authoritative save, edit, Favorite or delete succeeds, enqueue an idempotent projection update keyed by exact resource/revision. A projection failure leaves the source operation successful and schedules reconciliation/rebuild instead of reporting a false file failure.
- [ ] Invalidate and settle catalog access under the existing durable maintenance barrier before purge can complete or an old worker can repopulate deleted rows. Cache invalidation failure must fence cache display without converting successful authoritative deletion into a file failure; the durable barrier must prevent old-cache reuse on restart. Cover both purge scopes, account/folder change, destination restoration, protection loss, cache-version change and process termination during update/rebuild.
- [ ] Rebuild into generation/epoch-scoped transactions so partial imports are never mistaken for complete coverage. Continue serving a valid prior snapshot when safe; otherwise fall back to existing cold loading until a bounded page is available.
- [ ] Verify no cache row can authorize mutation, suppress a duplicate/conflict, resurrect a deleted diary, hide a newly discovered diary indefinitely or block recording/transcription/save/edit/delete progress.
- [ ] Verify crash points before/after authoritative success, projection commit, purge admission/completion and rebuild promotion; missed callbacks recover through reconciliation, while pre-purge epochs remain unusable.
- [ ] Document disk-budget/eviction policy and an internal app-owned cache reset path (no new Settings action selected). Reset removes only SQLite projection artifacts and is recoverable from iCloud files without diary modification.
- [ ] Bound transient inspection proofs and measure all retained indexes, summaries and tasks; settle access before memory-pressure teardown. Verify continued scrolling/reopening after rebuild with no diary collection cap or lost retryable observations.

Safeguard progress, 2026-11-04: the existing purge journal now retains a completed projection generation, verified before indexed scope admission. Both purge scopes wait for actual catalog settlement; cache-discard failure cannot reopen an older generation. Synthetic tests preserve the cache deliberately across completion, test legacy/interrupted intents and verify staging can repopulate only through a fresh scan. The strict production route now supplies the settlement callback. Internal indexed reset/memory teardown, bounded provider admission and coalesced mutation hints are tested in the unwired adapter. The [benchmark record](milestone-21-catalog-benchmark-results.md#reconciliation-and-maintenance-progress-2026-11-04) lists the overlapping 26- and 20-test Release simulator runs and limits. End-to-end mutation callbacks, app notifications, presentation, resource measurement and physical crash/provider evidence remain open; these composite acceptance items stay unchecked.

Safeguard validation checkpoint: `make lint` and the full required `scripts/validate.sh` generation/lint/build/test gate pass on iPhone 18 Pro / iOS 27.0, including metadata-only recovery fairness and all existing regressions. The local documentation check resolves 450 links/fragments with zero errors and preserves independent Tasks 1–5/7/8; `git diff --check` passes. This enables Task 12 integration work, without claiming its presentation or Task 14's phone/resource acceptance.

## Task 14: Prototype comparison and delivery decision

Use Task 10's baseline and the benchmark protocol to decide whether the selected prototype earns production retention. This is the single catalog comparison and device-acceptance task; the former Task 6 stages and Task 9 database comparison do not run separately. The decision compares the user-visible path, not merely SQL query speed.

### Task 14 acceptance checklist

- [ ] Verify Task 10's baseline record includes fixture sizes, measurement boundaries, repeat counts, numerical latency/resource limits and allowed regression margins using the [benchmark protocol](milestone-21-architecture-gui-enhancement-architecture.md#tasks-1014-benchmark-and-retention-protocol), frozen before prototype implementation/comparison. Reuse that record for acceptance.
- [ ] Measure process-cold launch, warm app return, process relaunch, empty/rebuilt cache, large history and real-iCloud locally present/evicted/offline cases on the target iPhone in Release without a debugger. Report repeat counts and median plus supported tail values.
- [ ] Compare first frame, first remembered row/10, first freshly validated row/10, final ordering/eligibility equivalence, scans, bytes/hash/decode work, main-thread stalls, memory, database/sidecar size and reconciliation duration with the baseline.
- [ ] Run adversarial fixtures for same-size replacement with restored modification time, duplicate/legacy ambiguity, missed external events, partial enumeration, corruption, protection loss, purge and account/folder switch. Final settled output must match a strict fresh-file oracle.
- [ ] Verify recording/transcription, automatic save verification, editing, Favorite, replay, deletion and recovery remain responsive and authoritative during open, reconciliation, invalidation and rebuild.
- [ ] Run affected focused regressions, `make lint` and the full required simulator gate; record physical-iPhone accessibility and real-iCloud evidence separately. Retain SQLite only if the preselected user-visible and resource budgets pass; otherwise keep the strict file catalog available and recommend disabling or removing only the disposable prototype. Record measured results and an explicit owner production-retention decision; unperformed device checks cannot be scored as passing.

Planning checkpoint: Tasks 10–14 selected the prototype engine and remembered-first behavior before code existed. The implementation-entry and foundation records above now supersede that no-code checkpoint; production retention remains open. Changing to SwiftData/Core Data, making the database authoritative, adding a third-party wrapper, or weakening fresh action validation requires a new owner decision.

Tasks 10–14 planning evidence, 2026-11-04 KST: the delegated changed-document checker resolved 311 local Markdown links/fragments with zero errors and found no remaining contradiction between the selected SQLite/remembered-first policy and the historical Task 6 strict-memory recommendation. `git diff --check` and `make lint` pass. A broad link pass reported only four pre-existing template/heading-normalization false positives outside these changes. No Swift build, simulator test, database prototype, phone timing or runtime/device acceptance was performed for this documentation-only update.


Tasks 10–14 review evidence, 2026-11-04 KST: the source-backed review findings and implementation/benchmark contracts are recorded in the approach. The delegated runner passed `make lint`, `git diff --check` and the final five-document local Markdown check (375 links, zero errors) after correcting three heading fragments. Semantic review found no remaining policy/status contradiction. This checks only the plan-review checklist; every prototype implementation/acceptance item remains unchecked. No app code, database prototype, Swift build, simulator run, phone timing or runtime/device acceptance was added.

## Task 15: Manually write a Diary Snippet

Requested on 2026-11-09: add a manual-writing button immediately to the left of the English (`en-US`) Record button on Main. Tapping it opens a text editor; Save creates a new Diary Snippet from the editor text, and Cancel cancels creation. The owner's subsequent corrections replace the original bottom/full-width arrangement: **Save and Cancel are compact custom bitmap buttons grouped at the top right of the editor. Neither button is full width; no bottom Save/Cancel action area is requested.**

Status: Active. Implementation requested by the owner on 2026-11-09 after the corrected button requirements. The [implementation approach](milestone-21-architecture-gui-enhancement-architecture.md#task-15-manual-diary-snippet-creation) records the selected defaults and source boundaries. This request authorizes the text-only creation path; recorded v1 pair requirements remain strict.

### Selected implementation scope

- Main has a custom bitmap writing button immediately left of English Record; it opens a focused editor sheet. Compact custom bitmap Cancel and Save actions share the editor's top-right group, with 44 × 44 pt hit areas, accessible names and no bottom/full-width action area.
- Creation rejects blank/whitespace-only new bodies and enforces the existing 1 MiB body limit without trimming saved text. Existing empty-body edits remain allowed. Save snapshots one identity/body/timestamp; retries reconcile that same submission, including uncertain acceptance. The creation timestamp is first Save, not editor opening.
- Explicit schema 2 with `creation_method: "manual"` stores one Markdown file and no recording/audio/transcription/context fields. Schema 1 recorded snippets still require their audio pair and provenance. Manual detail omits Audio and recording Metadata, while editing, Favorite and exact-resource deletion remain available.
- Save durably retains protected, backup-excluded text and the selected iCloud destination before dismissing the editor. Shared title generation/fallback and foreground publication run independently of recording jobs. All → Pending Diary Snippets shows manual save waits/review reasons; transient waits retry automatically and can be retried manually. Work never silently changes destination.
- Cancel discards an untouched buffer immediately and asks inline before discarding changed text. Swipe dismissal is blocked for changed/submitting text. Scene inactivity retains the unsent buffer in memory under the privacy cover; pre-Save restoration after process termination is outside this task. Accepted work survives relaunch. A previously accepted uncertain Save continues even if the editor is left; the editor explains this before discard.
- Completed submissions retain small protected idempotency receipts without body text or destination bookmarks. These are not unfinished staging and do not block active-folder purge; internal-staging purge removes them. Creation/edit/replay/catalog owners must settle before purge, and pending manual submissions block folder purge.

### Task 15 acceptance checklist

- [x] Resolve the creation defaults and update product, architecture, GUI, containment and vocabulary contracts together with implementation.
- [x] Add the manual-writing button immediately left of English Record on Main, retaining both recording-language actions. Source review confirms writing bypasses microphone and transcription-readiness gates; existing capture regressions pass in the full gate.
- [x] Provide a labeled multiline editor and compact custom bitmap Save and Cancel buttons together at the top right, with neither action full width and no bottom action area. Hosted tests assert accessible names, native button traits, at least 44 pt targets and compact/top-right frames; light/dark previews confirm template appearance and readable large-text discard protection.
- [x] Preserve the submitted body and stable creation identity through Save/retry, including Unicode/Korean text, CRLF, nonblank-new-entry validation, shared title fallback and uncertain acknowledgments. Existing empty-body edits remain valid. Physical IME composition remains in the open device item.
- [x] Deliver explicit text-only codecs, publication/upload verification, strict/indexed discovery and fresh detail, body/Favorite editing, exact-file deletion and retained conflict snapshots. Recorded missing-audio/malformed/legacy regressions pass without invented recording provenance.
- [x] Verify synthetic Cancel/discard creates no submission, accepted work survives journal restart, other-install restoration does not publish, pending text blocks folder purge, external replacement is preserved and interrupted cleanup resumes before reporting completion. Small completion receipts prevent duplicate Save after restart without retaining body/bookmark.
- [x] Run focused regressions, lint and the full required simulator gate; update user-facing docs and record evidence limits.
- [ ] Verify physical-iPhone keyboard/composition, VoiceOver reading/focus order, Reduce Motion and privacy-cover/lifecycle behavior across small/large portrait, landscape and largest Dynamic Type. Hosted previews cover visual subsets, not physical interaction. Device discovery did not return in this session.
- [ ] Record real-iCloud upload completion/offline recovery, destination/account changes, protected-data loss and foreground/relaunch/purge races for manual submissions. Synthetic upload observations and recorded-diary regressions do not close these manual platform/provider scenarios.

Task 15 planning validation, 2026-11-09: the delegated test runner passed `make lint` and `git diff --check`, verified Task 15 cross-links, and confirmed the final top-right compact bitmap requirements in the task and remaining-work table. A broad Markdown scan reported only four pre-existing template/AGENTS-anchor false positives, with no Task 15 link errors. At that planning checkpoint, no simulator gate, runtime or physical-device acceptance was performed and every Task 15 implementation item was unchecked. Later implementation evidence is recorded separately below.

Task 15 implementation evidence, 2026-11-09: the delegated test runner passed `make generate && make lint`, all 14 focused tests in five suites (`ManualDiaryCodecTests`, `ManualDiaryStorageTests`, `ManualDiaryEditingTests`, `ManualDiaryCatalogLifecycleTests`, `ManualDiaryEditorTests`), and the full `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` generation/lint/build/test gate after the final folder-cancellation correction. `git diff --check` passes. Focused results are at `/tmp/ndm-manual-final.xcresult`; the full-gate log is `/tmp/ndm-final-validate-latest.log`. Initial restricted-shell simulator/macro failures were resolved by the documented service-access retry.

Reviewed synthetic `manual-editor-small.png`, `manual-editor-large.png`, `manual-editor-landscape.png` and `manual-editor-dark-large.png` previews, with programmatic Cancel/discard and compact top-right action assertions. A truncated largest-type discard prompt was corrected with a scrollable confirmation. The indexed test originally waited for ten-row demand satisfaction with a one-row fixture; it now accepts exhausted coverage and awaits worker settlement before fixture deletion. The recorded-creation proof API still always requires both file proofs; a separate, validated edit-only method handles explicit absence of audio. No real provider upload proof is claimed: synthetic observers bind controlled upload flags to real coordinated file versions. MobileBuildMCP 2.7.1 device listing did not return, so physical-iPhone and real-iCloud checks above remain open. Earlier M16/M20/M21 acceptance is not closed by this feature.

## Task 16: Catalog measurement gate

Decides whether Tasks 11–14 resume. Do not wire the SQLite projection into Main until this gate opens.

- [ ] Wire no production path to the SQLite adapter (Tasks 10–13 code stays disabled). Confirm with a grep/test that Main uses only the strict file catalog.
- [ ] On the target iPhone, Release, no debugger, with a realistic synthetic history (at least 365 diaries, real iCloud folder, locally present), measure process-cold launch and warm return to the first 10 Main rows using the [frozen protocol](milestone-21-catalog-benchmark-results.md#frozen-prototype-budgets). Record repeat counts, median and maximum.
- [ ] Gate: reopen Tasks 11–14 only if the file catalog's first-10 median exceeds the frozen 500 ms remembered-page budget or the owner reports visible slowness. Note that the synthetic baseline already shows 741 ms median for a 100-diary first batch of 50, so first try the smaller first batch and discovery-barrier removal that baseline motivates before building the cache.
- [ ] Record the outcome and an owner decision: keep deferred, resume Tasks 11–14, or remove the disabled SQLite code.

## Task 17: Snippet loading after weather Settings

Owner report, 2026-11-11: after enabling weather in Settings, Main can remain on `Opening Diary Snippet` indefinitely. Trace detail selection, view disappearance and task ownership without changing context policy or enabling the deferred SQLite path.

- [x] Reproduce the stuck detail with synthetic snippets across Main → All → Settings → Main and identify the state transition that loses loading progress.
- [x] Repair detail lifecycle ownership and cover completed/in-flight detail, navigation dismissal and stale callbacks with regression checks.
- [ ] Run focused checks, `make lint` and the required full simulator gate; record observed results and physical-device evidence limits.

Task 17 evidence, 2026-11-11: the hosted strict-catalog round trip failed before the fix with a retained selection, nil detail/issue and an accessible `Opening Diary Snippet`. Removing disappearance-driven cleanup and tying cancellation to nil selection passes the round trip for both completed and delayed reads. All 18 focused tests across `CatalogCollectionPresentationTests`, `CatalogModelTests` and `RememberedCatalogPresentationTests` pass on iPhone 18 Pro / iOS 27.0; artifact `test_sim_2026-11-11T13-48-09-156Z_pid40431_40a7f47d.xcresult`. `make lint` passes after shortening the test name. Physical-iPhone/weather-provider checks were not performed. Existing independent workspace changes and milestone evidence remain intact.

The full required `scripts/validate.sh` run passes generation, lint and build, with **555 tests passed, 4 skipped and 3 failed** (562 total reported by xcresulttool). All failures are in the unchanged `ReminderDeviceTests`: notification authorization blocks/times out before the simulator prompt is answered, and `.protectionKey` is nil for the device-only file-protection assertion. The initial restricted-shell CoreSimulator refusal was resolved by service-access discovery and validation. After answering the simulator's notification prompt, a focused reminder rerun finishes with 4 passed/2 failed: the same protection assertion and a refused notification schedule. These reminder/platform checks are not a clean full-gate pass, so the composite gate item stays unchecked. No reminder implementation or test requirement was changed to close it. Full logs/result bundle remain at `/var/folders/g8/85jt_6h55k18d0yypsf09kdh0000gn/T/tmp.3ke3G6Tnfj`; the reminder rerun is `test_sim_2026-11-11T13-54-36-031Z_pid40431_481b9065.xcresult`.

## Out of scope

An unsolicited GUI redesign, a catalog checking/stale banner, a title editor, automatic regeneration when a model becomes ready, new durable queue states, migration of diary/queue/edit truth into SQLite, a global replacement state machine, broad repository restructuring, third-party dependencies/build-tool changes, and M16–M19 implementation. M21 does not waive earlier phone or adversarial evidence.

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
- [ ] Complete Task 3's physical-token and Task 4's real-iCloud acceptance; Task 16's gate outcome recorded (Tasks 11–14 are deferred, not required), Task 9's independent remainder delivered or explicitly deferred, and record the broader Task 2 disposition before marking M21 Done. Task 6 has no separate implementation gate. Checked historical gates do not complete future code or device work.
- [x] Reconcile affected architecture, UX, README, milestone, and index docs with delivered behavior; record compatibility with M16's edit/title boundaries and any remaining evidence in its owning milestone.
- [x] Run `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` on the implemented changes and record the destination/results. Unavailable required checks remain unchecked with the observed blocker.

Planning evidence (2026-11-03): the [source inventory](milestone-21-architecture-gui-enhancement-architecture.md#current-code-review-2026-11-03) records the inspected boundaries. Local links across the seven affected/new planning documents resolve, their referenced Markdown headings exist, both new documents have title/status headers, and `git diff --check` passes. At that planning checkpoint no new runtime, simulator, or physical-device acceptance was claimed. The 2026-11-04 Task 2a work and gate are recorded in its task section above.
