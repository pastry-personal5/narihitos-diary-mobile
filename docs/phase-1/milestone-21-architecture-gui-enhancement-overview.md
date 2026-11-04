# P1-M21: Architecture enhancement and GUI enhancement overview

Status: Active

Enhance the software architecture and implement GUI enhancements requested by the owner. The initial architecture task reviews processing stages and active resource ownership. M21 follows M16 under the revised execution order; specific GUI changes will be supplied by the owner.

## Entry and locked inputs

- The owner revised the order on 2026-11-04 to M20 → M16 → M21 → M17 → M18 → M19 and requested an M21 task now against the implemented M16 handoff. Follow the [Phase 1 execution order](phase-1.md). This authorizes the bounded Task 2 work below; M16, M20, and earlier evidence remain open.
- Preserve the approved [product behavior](../product-behavior.md), [GUI](../ux-gui.md), [containment](../ux-information-architecture.md), [terms](../ux-terms.md), and [P1-M5 contracts](milestone-05-decisions-architecture.md). No particular new layout, control, label, or title-progress display is requested yet.
- Use the implemented M10 queue, M13 draft/title stage, M14 commit, M15 catalog, and M20 maintenance/interaction repairs. Recheck the source inventory against the implemented M16 handoff; M17–M19 remain later work. M16 continues to own body editing, Favorite mutation, and audio replay; M17 owns complete recovery flows.
- Related undecided items remain unchanged: no new inference provider, runtime, quantization, hosted controls, dependency, build tool, or relaxation of approved safeguards.

## Task 1: Owner-requested GUI enhancements

Reserve this task for concrete owner requests. Before each implementation, add a numbered request with the affected screen, intended behavior, relevant existing contract, and verifiable acceptance checklist. Do not infer a redesign from the milestone title or the lifecycle review.

Each request should identify applicable navigation, accessibility, interaction, and state-restoration checks. Update the GUI/terms/containment docs and README when the delivered behavior changes them. Changes to an existing owner decision need the owner's direction before implementation.

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
- [x] Reconcile affected architecture, UX, README, milestone, and index docs with delivered behavior; record compatibility with M16's edit/title boundaries and any remaining evidence in its owning milestone.
- [x] Run `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` on the implemented changes and record the destination/results. Unavailable required checks remain unchecked with the observed blocker.

Planning evidence (2026-11-03): the [source inventory](milestone-21-architecture-gui-enhancement-architecture.md#current-code-review-2026-11-03) records the inspected boundaries. Local links across the seven affected/new planning documents resolve, their referenced Markdown headings exist, both new documents have title/status headers, and `git diff --check` passes. At that planning checkpoint no new runtime, simulator, or physical-device acceptance was claimed. The 2026-11-04 Task 2a work and gate are recorded separately below.
