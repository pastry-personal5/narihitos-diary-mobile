# P1-M21: Architecture enhancement and GUI enhancement approach

Status: Proposal

Plan architecture enhancements and owner-requested GUI enhancements within the existing application boundaries. The initial architecture review distinguishes persisted recovery checkpoints, transient title/draft work, and resource ownership that may outlive a visible result.

## Current-code review, 2026-11-03

| Evidence | Current behavior | Documentation or design implication |
|---|---|---|
| [`ProcessingQueue.swift`](../../NarihitosDiary/Application/ProcessingQueue.swift), `QueueJobState` and `settle` | Successful inference publishes and verifies a private candidate, then persists `resultReady` and releases the transcription worker. | The old diagram's direct `transcribing` → `readyToSave` transition omitted a durable recovery checkpoint. |
| [`DiaryDraftAdoptionCoordinator.swift`](../../NarihitosDiary/Application/DiaryDraftAdoptionCoordinator.swift), `adopt` and `finish` | A separate task reserves/reuses the asset ID, obtains a title, publishes and verifies the draft, then persists `readyToSave`. During title generation the durable state remains `resultReady`. | Title generation exists as transient work; there is no durable `generatingTitle` enum case. Draft verification is the next checkpoint. |
| [`DiaryTitlePolicy.swift`](../../NarihitosDiary/Application/DiaryTitlePolicy.swift), `title` and `TitleDeadlineGate` | A 30-second deadline returns fallback and cancels the model task. `hasActiveWork` remains true until that task returns; subsequent title requests use fallback while it is unsettled. | A title result and idle resource ownership are different facts. Do not infer idle from timeout, fallback publication, or coordinator deactivation. |
| [`DiaryCommit.swift`](../../NarihitosDiary/Application/DiaryCommit.swift) | Publication, destination/upload waits, file-version checkpoints, and recovery are represented by the commit record and reason while the job remains `readyToSave`; verified completion sets `saved`. | The old diagram's `saving`, `waitingForDestination`, and `saveFailed` were conceptual phases, not current queue enum cases. Show that mapping explicitly. |
| [`AppModel.swift`](../../NarihitosDiary/Presentation/AppModel.swift), `updateMainNotices` | Only `transcribing` contributes to the processing notice; `resultReady` contributes to the pending count. | Current GUI has no distinct title-generation progress. A new owner request is needed to choose its presentation and exact copy. |
| [`DiaryDraftAdoptionTests.swift`](../../NarihitosDiaryTests/DiaryDraftAdoptionTests.swift), [`DiaryTitlePolicyTests.swift`](../../NarihitosDiaryTests/DiaryTitlePolicyTests.swift) | Existing tests describe candidate/draft restart, removal fencing, title deadlines, and held model ownership. | Reuse these seams for future regressions; source inspection is not a new test pass. |

The previous lifecycle section was directionally correct about fallback and independent progress, but incomplete about the M11/M13 handoff and M20 settlement safeguards. The [updated architecture section](../architecture.md#processing-and-queue-lifecycle) describes existing behavior; this document's projection below is proposed work.

## Affected boundaries

| Boundary | M21 responsibility |
|---|---|
| SwiftUI views and presentation models | Implement only supplied GUI requests. Consume typed stage information if a request needs it; preserve navigation, inline removal confirmation, and existing accessibility semantics. |
| `ProcessingQueueCoordinator` | Remain the durable transcription scheduler. Keep selected-method snapshots, candidate verification, oldest-ready ordering, and acknowledged cancellation. |
| `DiaryDraftAdoptionCoordinator` / `DiaryTitlePolicy` | Own candidate adoption and bounded title work independently of transcription. Report transient work and unsettled model ownership accurately if the projection is selected. |
| `DiaryCommitCoordinator` | Keep publication/version/upload proof and cleanup authority. A screen stage or timeout does not substitute for its evidence. |
| `AppModel` / composition root | Compose read-only lifecycle snapshots and owner events. Avoid duplicating transition logic in screen counts or making presentation the authority for maintenance admission. |

No new module, target, dependency, or broad coordinator rewrite is needed for this plan.

## Recommended enhancement: separate checkpoints, phases, and ownership

At implementation entry, assess a small typed application snapshot assembled from existing owners. Prefer extending current projections over introducing a second scheduler. Proposed identifiers are illustrative and are not implemented APIs or approved user-facing labels.

1. **Durable checkpoint:** retain `QueueJobState` and the verified candidate/draft/commit evidence used on restart. `resultReady` already gives title/draft work a recovery point; adding durable `generatingTitle`, `titleFailed`, or `titleTimedOut` states is unnecessary for current fallback behavior.
2. **Transient per-job phase:** if needed, expose candidate/draft checking, title generation, draft verification, and commit/upload wait through owner-supplied typed values. Bind updates to the job/attempt and relevant revisions; the durable `resultReady` value alone cannot prove that a title request is currently running. Reconstruct transient phases from live owners after launch rather than persisting them.
3. **Resource ownership:** report unsettled transcription, title, and commit work separately from a job's displayed phase. A timed-out title call may still own the model after its job advances to `readyToSave` or finishes saving. Keep its identity until settlement; do not attach its busy state to a later job that merely uses fallback. Existing maintenance admission must continue checking actual owners.

Use bounded snapshots and callbacks on actual changes, including the final settlement after a fallback. Reject obsolete attempt/body/destination events, clear completed transient phases, and avoid polling files or decoding audio merely to update a progress indicator. No diary body, generated title, coordinate, bookmark, or path belongs in lifecycle diagnostics. A read-only snapshot never authorizes deletion or publication.

Record the selected narrow implementation, or a justified no-change outcome, in the overview before changing code. Keep GUI labels and placement reserved for the owner's concrete request. If code inspection reveals a required product or mechanism change beyond approved outcomes, resolve that decision before implementation.

## Title lifecycle and M16 handoff

The implemented recording path is:

`transcribing` → verified private candidate / `resultReady` → title policy and draft verification → `readyToSave` → verified iCloud pair and both uploads / `saved`.

During `resultReady`, adoption can reuse an already verified draft without running the title model. Otherwise the title policy chooses AI or local fallback. A deadline fences late output and lets the draft use fallback; the cancelled model remains owned until it settles. Later jobs can use fallback without starting overlapping title inference. Model readiness alone never rewrites a saved title.

M16 should reuse the title policy and any selected runtime reporting seam for its independent submitted-edit journal. An edit is not a recording job; do not manufacture `resultReady` queue entries to report title work. Preserve M16's body-revision fencing, stable submitted candidate, separate Favorite path, and resource/version ownership.

## Implementation and evidence sequence

1. Read the current M20 outcome and recheck this source inventory; add each supplied GUI request and its completion criteria to the overview.
2. Select the narrow lifecycle reporting change if justified. Keep durable storage and recovery semantics intact; add focused regressions only for changed behavior or identified gaps.
3. Verify restart before/after candidate publication, draft publication, and queue replacement; title fallback and held cancellation; late callbacks after removal/supersession; maintenance busy/idle; and independent transcription/commit progress as applicable to the change.
4. Implement the requested screens using existing view models and inward-owned ports. Capture synthetic before/after evidence and perform the relevant accessibility and target-phone checks without accessing real diary contents.
5. Update affected docs and run the standard lint/full simulator gate. Record failures and unperformed phone checks without closing earlier milestones or advancing M16 prematurely.
