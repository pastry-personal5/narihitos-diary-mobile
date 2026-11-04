# P1-M21: Architecture enhancement and GUI enhancement approach

Status: Active

Record the delivered shared title-work reporting and plan further architecture and owner-requested GUI enhancements within the existing application boundaries. The initial architecture review distinguishes persisted recovery checkpoints, transient title/draft work, and resource ownership that may outlive a visible result.

## Current-code review, 2026-11-03

| Evidence | Current behavior | Documentation or design implication |
|---|---|---|
| [`ProcessingQueue.swift`](../../NarihitosDiary/Application/ProcessingQueue.swift), `QueueJobState` and `settle` | Successful inference publishes and verifies a private candidate, then persists `resultReady` and releases the transcription worker. | The old diagram's direct `transcribing` → `readyToSave` transition omitted a durable recovery checkpoint. |
| [`DiaryDraftAdoptionCoordinator.swift`](../../NarihitosDiary/Application/DiaryDraftAdoptionCoordinator.swift), `adopt` and `finish` | A separate task reserves/reuses the asset ID, obtains a title, publishes and verifies the draft, then persists `readyToSave`. During title generation the durable state remains `resultReady`. | Title generation exists as transient work; there is no durable `generatingTitle` enum case. Draft verification is the next checkpoint. |
| [`DiaryTitlePolicy.swift`](../../NarihitosDiary/Application/DiaryTitlePolicy.swift), `title` and `TitleDeadlineGate` | A 30-second deadline returns fallback and cancels the model task. `hasActiveWork` remains true until that task returns; subsequent title requests use fallback while it is unsettled. | A title result and idle resource ownership are different facts. Do not infer idle from timeout, fallback publication, or coordinator deactivation. |
| [`DiaryCommit.swift`](../../NarihitosDiary/Application/DiaryCommit.swift) | Publication, destination/upload waits, file-version checkpoints, and recovery are represented by the commit record and reason while the job remains `readyToSave`; verified completion sets `saved`. | The old diagram's `saving`, `waitingForDestination`, and `saveFailed` were conceptual phases, not current queue enum cases. Show that mapping explicitly. |
| [`AppModel.swift`](../../NarihitosDiary/Presentation/AppModel.swift), `updateMainNotices` | Only `transcribing` contributes to the processing notice; `resultReady` contributes to the pending count. | Current GUI has no distinct title-generation progress. A new owner request is needed to choose its presentation and exact copy. |
| [`DiaryDraftAdoptionTests.swift`](../../NarihitosDiaryTests/DiaryDraftAdoptionTests.swift), [`DiaryTitlePolicyTests.swift`](../../NarihitosDiaryTests/DiaryTitlePolicyTests.swift) | Existing tests describe candidate/draft restart, removal fencing, title deadlines, and held model ownership. | Reuse these seams for future regressions; source inspection is not a new test pass. |

The previous lifecycle section was directionally correct about fallback and independent progress, but incomplete about the M11/M13 handoff and M20 settlement safeguards. The [updated architecture section](../architecture.md#processing-and-queue-lifecycle) describes existing behavior. The broader projection below remains proposed work; the delivered title-only subset is recorded separately.

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

Task 2a implements the title-only subset below. Broader checkpoint/adoption/commit aggregation remains proposed; assess it against concrete reporting needs before extending the snapshot. Prefer extending current projections over introducing a second scheduler. Proposed identifiers are illustrative and are not implemented APIs or approved user-facing labels.

1. **Durable checkpoint:** retain `QueueJobState` and the verified candidate/draft/commit evidence used on restart. `resultReady` already gives title/draft work a recovery point; adding durable `generatingTitle`, `titleFailed`, or `titleTimedOut` states is unnecessary for current fallback behavior.
2. **Transient per-job phase:** if needed, expose candidate/draft checking, title generation, draft verification, and commit/upload wait through owner-supplied typed values. Bind updates to the job/attempt and relevant revisions; the durable `resultReady` value alone cannot prove that a title request is currently running. Reconstruct transient phases from live owners after launch rather than persisting them.
3. **Resource ownership:** report unsettled transcription, title, and commit work separately from a job's displayed phase. A timed-out title call may still own the model after its job advances to `readyToSave` or finishes saving. Keep its identity until settlement; do not attach its busy state to a later job that merely uses fallback. Existing maintenance admission must continue checking actual owners.

Use bounded snapshots and callbacks on actual changes, including the final settlement after a fallback. Reject obsolete attempt/body/destination events, clear completed transient phases, and avoid polling files or decoding audio merely to update a progress indicator. No diary body, generated title, coordinate, bookmark, or path belongs in lifecycle diagnostics. A read-only snapshot never authorizes deletion or publication.

Record the selected narrow implementation, or a justified no-change outcome, in the overview before changing code. Keep GUI labels and placement reserved for the owner's concrete request. If code inspection reveals a required product or mechanism change beyond approved outcomes, resolve that decision before implementation.

## Delivered Task 2a: shared title-work snapshot

The selected 2026-11-04 implementation extends the existing shared owner rather than introducing a scheduler. `DiaryTitleWorkSnapshot` is an immutable application value with one random operation ID, optional `DiaryTitleWorkOwner`, and `generating` or `settling` phase. `DiaryTitlePolicy.workSnapshot` is externally read-only, and `onWorkChange` emits the current value only on changes, including nil at final settlement. `hasActiveWork` derives from the same owned operation.

`DiaryDraftAdoptionCoordinator` supplies recording job ID, attempt ID/generation, destination revision, and body revision after its existing current-job check. `DiaryEditCoordinator` supplies the accepted submission ID; each revision already has its own immutable journal identity. Direct policy calls can omit correlation. No body, title, coordinates, bookmark, filename, or destination capability enters the snapshot. No observer can authorize publication or removal.

Normal completion reports generating → idle. A deadline reports generating → settling while returning fallback; a competing request returns fallback without emitting events or taking over the original operation's identity. The late model return reports idle and cannot replace the returned title. A subsequent request starts with a new operation ID. The deadline gate reports whether it actually resolved the continuation, preventing an expired/cancelled timer from inventing settling after completion.

The projection deliberately stops at the shared title owner. Candidate and draft verification still belong to adoption; commit and upload proof still belong to commit records. No queue state, persisted schema, scheduler, maintenance admission rule, or GUI copy changes. M17–M19 have no delivered outcomes to consume yet under the revised order, and their recovery/context/adversarial work remains assigned there.

Focused evidence lives in `DiaryTitlePolicyTests.completedTitleReportsGeneratingThenIdle` and the two directions of `timeoutKeepsOriginalOwnerUntilSettlement`. Existing adoption timeout/maintenance and edit acceptance/navigation regressions now assert the production callers' owner bindings and final idle state. The full gate also covers existing candidate/draft restart, removal fencing, commit/upload, and edit/replay maintenance scenarios. Simulator results do not close native model, real-provider, or physical-device evidence.

## Task 3: iCloud identity decoding class restriction

`AppleDestinationPlatform.identitiesMatch` previously supplied `[NSObject.self]` to both secure unarchive calls. That admits every Objective-C subclass and produces the owner's runtime warning. The replacement obtains a fresh `FileManager.ubiquityIdentityToken`, then uses its public `classForKeyedArchiver` (falling back to `classForCoder`) as the sole allowed class. This supports Foundation class clusters without naming private implementation classes or deriving identity from reflection. Missing identity requires restoration; an `NSObject` coding class or a class without secure-coding support fails closed. Stored bytes never select the allowed class.

Both archived snapshots still decode and compare with `isEqual`, preserving existing account-change and transaction checks. Archive bytes, persistence formats, bounds, bookmark ownership, and folder contents are unchanged. Existing non-secure archives remain readable when their encoded objects support secure decoding; the adapter does not disable secure decoding to silence diagnostics. A changed platform coding representation may fail closed and require access restoration rather than broaden the allowance.

`UbiquityIdentityDecodingTests` exercises the actual adapter through an injected `FileManager` with synthetic tokens: existing archive round trips, account mismatch, unexpected roots in either argument, malformed/truncated archives, absent identity, rejected `NSObject` coding metadata, and secure custom tokens with allowed/rejected nested values. The focused run passes all 44 tests across that suite, `DestinationTransactionTests`, and `FirstLaunchAndDestinationTests` on iPhone 18 Pro / iOS 27.0. The overview records the final gate. These synthetic tokens do not establish the current iPhone token's restart round trip or prove all framework-originated warnings absent; M8-D04 and the owner's physical-device console/relaunch verification remain open.

## Task 4: automatic iCloud verification retries

The source defect is the old `AppModel.saveAttempted` foreground-session latch. `AppleDiaryPairStore.observeUploads` obtains one bounded observation of each file; an upload not yet reported successful returns no proof. `DiaryCommitCoordinator` correctly retains `readyToSave`, the intent and staging with an upload-wait reason. However, `pumpSaves` excludes the already-attempted job until manual Retry or app activation clears the latch. No timer or provider event makes it eligible when upload finishes. This explains the reported manual-retry recovery without implying a failed transcription or a new durable queue state.

Before repair, the delayed-upload regression against an extracted copy of that scheduling loop failed: the job remained `readyToSave`, only one upload check ran, no delay was scheduled, and no cleanup occurred; the other 13 commit tests passed. With `DiarySaveScheduler`, the same regression passes. Its strengthened final version initially supplies only Markdown proof, then supplies both on a synthetic retry deadline, and asserts durable completion, one saved callback, and exactly one cleanup. This establishes the scheduling defect; the owner's actual provider upload timing remains a target-phone observation.

`DiarySaveScheduler` now owns transient save tasks and retry timers, independently of transcription. It calls the existing commit coordinator for each attempt, so each retry rereads the verified draft and exact pair, separately obtains both upload proofs, and performs the final unchanged check. No timer, network signal, prior report, or visible file substitutes for proof. Ordinary upload, destination, and protected-data waits receive 2, 5, 15, 30, then at most one retry per 60 seconds while active. Failed/review jobs and conflict-resolution records do not receive these timed retries. Manual Retry bypasses a pending delay. Independent jobs can advance while another waits.

An active task remains owned until the commit accessor settles, including cancellation, inactivity, and reactivation; queued tasks recheck enabled state and their exact job snapshot before starting. Timer tokens and current job equality reject cancelled or superseded wakes; changed attempt/destination/body revisions cannot be acknowledged by an earlier attempt. Removal cancels its timer after recording the removal intent. Queue pause or unreadable storage stops scheduling; maintenance and scene inactivity cancel timers without treating in-flight I/O as settled. Foreground/relaunch reconstructs scheduling from durable `readyToSave` records. Timer waits grant no file-mutation authority and do not count as active provider work for maintenance admission; retained staging still blocks folder purge through the existing independent admission check.

No `BGTaskScheduler` registration, background entitlement, or durable format change is needed for the approved app-open processing contract. iCloud may upload independently while the app is suspended; verification resumes when the app becomes active. This implementation does not claim execution while suspended or force-quit. The existing Pending reason and Retry Verification action stay available; the existing saved callback refreshes Main only after durable completion.

Focused evidence: 39 tests pass across `DiarySaveSchedulerTests`, `DiaryCommitTests`, and `AppleDiaryPairStoreTests` on iPhone 18 Pro / iOS 27.0. Deterministic clock tests cover backoff, transient wait types, independent jobs, immediate manual retry, stale timers, removal/revision changes, and actual ownership through suspension; existing adapter tests cover metadata changes, pair replacement, exact-file adoption, and upload proof. The overview records the final gate and remaining physical-iCloud evidence.

## Title lifecycle and M16 compatibility

The implemented recording path is:

`transcribing` → verified private candidate / `resultReady` → title policy and draft verification → `readyToSave` → verified iCloud pair and both uploads / `saved`.

During `resultReady`, adoption can reuse an already verified draft without running the title model. Otherwise the title policy chooses AI or local fallback. A deadline fences late output and lets the draft use fallback; the cancelled model remains owned until it settles. Later jobs can use fallback without starting overlapping title inference. Model readiness alone never rewrites a saved title.

M16 precedes M21 and reuses the existing title policy through its independent submitted-edit journal. The 2026-11-04 order places M21 immediately after M16; reconcile reporting with M16's delivered interfaces while its evidence remains open. An edit is not a recording job; do not manufacture `resultReady` queue entries to report title work. Preserve M16's body-revision fencing, stable submitted candidate, separate Favorite path, and resource/version ownership.

## Task 2b: State and deletion documentation review

The owner requested a software architecture review on 2026-11-04, emphasizing state, title generation, and deletion. This review updates the architectural description against existing contracts and source. It adds no runtime behavior, queue/edit schema, global state machine, or automatic destructive retry.

| Finding | Source/contract evidence | Documentation repair |
|---|---|---|
| The processing diagram mixed durable queue cases with nested transient title/adoption phases. | [`QueueJobState`](../../NarihitosDiary/Application/ProcessingQueue.swift), [`DiaryDraftAdoptionCoordinator`](../../NarihitosDiary/Application/DiaryDraftAdoptionCoordinator.swift), and [`DiaryEditStage`](../../NarihitosDiary/Application/DiaryEdit.swift) | Add a state-ownership table, keep the queue diagram durable-only, and describe the independent edit journal and live title state separately. |
| A title result can precede model settlement, including after saving; later fallback callers must not inherit the held owner. | [`DiaryTitlePolicy`](../../NarihitosDiary/Application/DiaryTitlePolicy.swift), adoption/edit `hasActiveWork`, and Task 2a tests | Add a title-owner transition diagram and result/checkpoint/ownership table; document operation correlation, late-result fencing, fallback progress, deletion admission, and purge admission. |
| The architecture said finished-asset removal was outside v1 despite implemented owner-approved detail deletion. | [M20 Task 21](milestone-20-enhancements-fixes-refactoring-architecture.md#task-21-delete-a-diary-snippet-from-detail), [`DiaryActionsModel`](../../NarihitosDiary/Presentation/DiaryActionsModel.swift), [`DiaryDeletionPort`](../../NarihitosDiary/Application/DiaryDeletion.swift), [`AppleDiaryDeletionService`](../../NarihitosDiary/Adapters/AppleDiaryDeletionService.swift) | Separate pending-recording removal, committed-pair deletion, recovery cleanup, and purge. Record confirmation consumption, edit reservation, replay settlement, creation cleanup, exact-file checks, partial failure, and absence of automatic detail-deletion retry. |
| Removal was described as waiting for one barrier spanning publication through completion, obscuring confirmation that invalidates an unverified save. | [`ProcessingQueueCoordinator.remove`](../../NarihitosDiary/Application/ProcessingQueue.swift), [`DiaryCommitCoordinator`](../../NarihitosDiary/Application/DiaryCommit.swift), and [approved save/removal behavior](../product-behavior.md#transcription) | Describe current owner tracking, durable cancelling/removing markers, post-suspension claim checks, and coordinated mutations. Preserve the approved already-verified completion versus removal-first outcomes and outstanding provider race evidence. |
| A later paragraph called `waitingForDestination` a queue state, and legacy/purge wording obscured explicit deletion scopes. | `QueueJobState`, commit wait reasons, M20 Tasks 9/21, [`ApplePurgeService`](../../NarihitosDiary/Adapters/ApplePurgeService.swift) | Correct destination waiting to `readyToSave` plus reason; clarify eligible legacy deletion and the separately confirmed folder-content purge exception. |

The [architecture verification matrix](../architecture.md#state-and-deletion-verification-matrix) points to existing title, adoption, edit, removal, deletion, and purge test seams. Source review is distinct from execution evidence. README and GUI behavior need no change because this task corrects architecture documentation only. M17 recovery screens and earlier physical-device/provider obligations remain open.

Validation results are recorded in the [Task 2b checklist](milestone-21-architecture-gui-enhancement-overview.md#task-2b-acceptance-checklist).

## Implementation and evidence sequence

1. Read the M20 and implemented M16 outcomes and recheck this source inventory; add each supplied GUI request and its completion criteria to the overview.
2. Select the narrow lifecycle reporting change if justified. Keep durable storage and recovery semantics intact; add focused regressions only for changed behavior or identified gaps.
3. Verify restart before/after candidate publication, draft publication, and queue replacement; title fallback and held cancellation; late callbacks after removal/supersession; maintenance busy/idle; and independent transcription/commit progress as applicable to the change.
4. Implement the requested screens using existing view models and inward-owned ports. Capture synthetic before/after evidence and perform the relevant accessibility and target-phone checks without accessing real diary contents.
5. Update affected docs and run the standard lint/full simulator gate. Record failures and unperformed phone checks without closing earlier milestones' open evidence.

## Task 1 request 1: Diary Snippet detail layout

The owner requested full-width Edit Diary, the existing Delete Diary Snippet action immediately below it, and Metadata below Audio on 2026-11-04. `DiaryCatalogDetailView` keeps the body and action stack together, gives Edit Diary the existing centered headline/52-point full-width label treatment with a prominent style, and renders replay or Audio Unavailable in a separate section above read-only Metadata. Preserve the existing action identifiers, model eligibility, inline warning/Cancel, accessibility focus, and navigation/scene/version cancellation hooks. Legacy detail still omits editing and Favorite. No persistence, coordinator, or replay mechanism changes are needed.

Use the existing `DiaryPresentationTests` and `DiaryDeletionPresentationTests` synthetic hosted layouts and activation checks for editor, Favorite, replay, legacy, inline confirmation, and scene cancellation, plus the full required simulator gate. Review generated screenshots for layout; record physical interaction and untested configurations separately in the [request checklist](milestone-21-architecture-gui-enhancement-overview.md#request-1-diary-snippet-detail-action-and-metadata-layout).
