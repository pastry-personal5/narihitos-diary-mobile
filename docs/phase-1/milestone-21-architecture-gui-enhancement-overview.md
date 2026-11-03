# P1-M21: Architecture enhancement and GUI enhancement overview

Status: Planned

Enhance the software architecture and implement GUI enhancements requested by the owner. The initial architecture task reviews processing stages and active resource ownership. M21 follows M19 under the revised execution order; specific GUI changes will be supplied by the owner.

## Entry and locked inputs

- The owner revised the order on 2026-11-03 to M20 → M16 → M17 → M18 → M19 → M21, superseding M21's earlier placement before M16. Follow the [Phase 1 execution order](phase-1.md). This revision does not begin app implementation or close M20 or earlier evidence.
- Preserve the approved [product behavior](../product-behavior.md), [GUI](../ux-gui.md), [containment](../ux-information-architecture.md), [terms](../ux-terms.md), and [P1-M5 contracts](milestone-05-decisions-architecture.md). No particular new layout, control, label, or title-progress display is requested yet.
- Use the implemented M10 queue, M13 draft/title stage, M14 commit, M15 catalog, and M20 maintenance/interaction repairs. Recheck the source inventory against M16–M19 outcomes at entry. M16 continues to own body editing, Favorite mutation, and audio replay; M17 owns complete recovery flows.
- Related undecided items remain unchanged: no new inference provider, runtime, quantization, hosted controls, dependency, build tool, or relaxation of approved safeguards.

## Task 1: Owner-requested GUI enhancements

Reserve this task for concrete owner requests. Before each implementation, add a numbered request with the affected screen, intended behavior, relevant existing contract, and verifiable acceptance checklist. Do not infer a redesign from the milestone title or the lifecycle review.

Each request should identify applicable navigation, accessibility, interaction, and state-restoration checks. Update the GUI/terms/containment docs and README when the delivered behavior changes them. Changes to an existing owner decision need the owner's direction before implementation.

## Task 2: Processing lifecycle architecture review

Review the [processing and queue lifecycle](../architecture.md#processing-and-queue-lifecycle) against current code. Document durable checkpoints separately from transient work and from resource settlement. The [approach](milestone-21-architecture-gui-enhancement-architecture.md) records the current evidence and a proposed small typed projection for lifecycle reporting.

The recommended enhancement makes title/draft work inspectable without inventing a durable `generatingTitle` queue state. Keep transcription, draft adoption/title inference, and commit as separate owners. A returned fallback can permit draft publication while cancelled title inference still owns resources; any projection must represent both facts. A lifecycle projection is read-only and grants no save, removal, or purge authority.

## Out of scope

An unsolicited GUI redesign, new exact progress copy, a title editor, automatic regeneration when a model becomes ready, new durable queue states or schema migrations, a global replacement state machine, broad repository restructuring, dependencies/build-tool changes, and M16–M19 implementation. M21 does not waive earlier phone or adversarial evidence.

## Completion checklist

### Planning and documentation evidence

- [x] Add linked overview/approach documents and align the phase plan and M16 entry condition with the revised M20 → M16 → M17 → M18 → M19 → M21 execution order.
- [x] Compare the architecture lifecycle with queue, candidate, title/adoption, commit, and presentation code; record concrete mismatches and source/test references in the approach.
- [x] Update the architecture lifecycle to show `resultReady`, title/draft work, verified `readyToSave`, commit/upload proof, and fallback-versus-settlement semantics without presenting proposed APIs as implemented.

### Implementation and acceptance

- [ ] Record each concrete owner GUI request and its acceptance checklist before implementation; complete the requested changes with reviewable visual/interaction evidence.
- [ ] Review Task 2's proposed lifecycle projection at implementation entry and record the selected bounded change, or an evidence-backed decision to retain existing interfaces. Any selected change separates durable job state, transient phase, and unsettled ownership without adding persisted title states or mutation authority.
- [ ] For lifecycle changes, verify durable candidate handoff, restart from candidate or verified draft, fallback within the title budget, late-result fencing, no overlapping title inference, and busy ownership until actual settlement. Other ready transcription and save work must retain independent progress.
- [ ] Verify affected GUI behavior with synthetic data, including applicable small/large iPhones, landscape, largest Dynamic Type, VoiceOver, Reduce Motion, foreground/relaunch, and processing/recovery states. Record required target-iPhone evidence separately; unavailable evidence stays unchecked.
- [ ] Reconcile affected architecture, UX, README, milestone, and index docs with delivered behavior; record compatibility with M16's edit/title boundaries and any remaining evidence in its owning milestone.
- [ ] Run `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` on the implemented changes and record the destination/results. Unavailable required checks remain unchecked with the observed blocker.

Planning evidence (2026-11-03): the [source inventory](milestone-21-architecture-gui-enhancement-architecture.md#current-code-review-2026-11-03) records the inspected boundaries. Local links across the seven affected/new planning documents resolve, their referenced Markdown headings exist, both new documents have title/status headers, and `git diff --check` passes. No new runtime, simulator, or physical-device acceptance is claimed; M21 remains Planned and its implementation gate is pending.
