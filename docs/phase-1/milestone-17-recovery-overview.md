# P1-M17: Pending, failed, incomplete, and conflict recovery overview

Status: Planned

Complete the four All recovery destinations with truthful state, safe inspection, and version-bound actions. Preserve pending work and unrelated files through retry, destination replacement, conflict choice, and confirmed removal.

## Entry and locked inputs

- Implementation follows P1-M21 under [Phase 1 order](phase-1.md), unless the owner authorizes a reorder. This request plans M17 only; it does not start implementation or close earlier checklist, simulator, or device evidence.
- Follow the approved [product behavior](../product-behavior.md), [recovery architecture](../architecture.md#failure-and-recovery-contract), [mutation controls](../architecture.md#mutation-and-recovery-integrity), [GUI](../ux-gui.md#planned-owner-approved-behavior), and [P1-M5 contracts](milestone-05-decisions-architecture.md). No new product decision, dependency, build tool, schema for finished assets, or transcription method is proposed.
- Consume M9 capture recovery, M10 durable queue/quarantine, M11/M12 method readiness, M13 managed drafts, M14 commit/repair/conflict proof, M15 exact-version recovery discovery, and M16 independent submitted-edit journals and replay/session ownership. Earlier platform evidence remains open where its milestone records say so.
- M18 retains context acquisition and notification permission/scheduling. M19 retains complete-experience validation and the full adversarial matrix. M17 supplies reliable pending/recovery projections for those milestones.

## Implementation prerequisites

- **Typed actions:** current queue projections expose state and a display reason, and minimal views infer available actions from broad states. Add typed stage/reason/action capabilities; do not dispatch by message text. Verification retry must resume the retained draft/commit, not invoke transcription retry or discard candidates.
- **Recovery beyond capture jobs:** M14 conflict choice and cleanup currently take a `QueueJob`; M15 can discover provider conflicts without one, and M16 owns separate edit transactions. Add type-specific resource/destination bindings and journals for these owners. Do not fabricate recording jobs or require capture staging that has already been deleted.
- **Fresh confirmation authority:** a catalog handle, asset UUID, snapshot ID, or job ID alone cannot authorize deletion. Bind each confirmation to the exact owner revision, destination/account, resource/version set, and selected/unchosen versions. Revalidate at use, including after an asynchronous picker or confirmation dialog.
- **Surviving-content access:** M16's normal replay lease requires a complete pair. Add a read-only recovery lease for an independently validated surviving audio resource or protected conflict snapshot; do not relax normal pair validation or use a displayed availability Boolean as playback authority.
- **Recovery inventory:** aggregate adopted jobs, unadopted/failed capture receipts, isolated malformed records, active-folder catalog issues, and submitted-edit recovery without duplicate rows or dependence on visiting Main first. Keep former-folder job/edit work reachable through its original binding.

## Scope

| Work | Required behavior |
|---|---|
| Pending Recordings | Show queued, processing, prerequisite-waiting, draft/save/upload-waiting, review-required, and Cancelling states. Offer only applicable model, method, access, verification, Resume, and confirmed Remove actions. Keep an entry's reason beside it. |
| Failed Recordings | Show failed attempts and unreadable interrupted audio with an entry-level reason. Manual Retry uses current Settings with no fixed retry-count limit while audio remains; invalid audio may fail again without disappearing. Preserve isolated recovery issues without enabling unsafe retry/deletion. |
| Restored work | Keep other-install or unbound recordings quarantined until Resume/Remove review. Resume verifies source ownership and audio, creates a fresh current-Settings attempt, and revalidates destination access. Present M16 restored submitted edits distinctly, preserving their accepted body rather than retranscribing them. |
| Destination recovery | Restore the capture-time destination without silently using the active folder. Offer explicit per-recording replacement only after the user confirms removal/revocation of the original folder. Persist the new validated iCloud capability and destination revision before resuming a retained draft. |
| Incomplete Diary Snippets | Present safe surviving text/audio read-only with typed missing, malformed, unsupported, unsafe, duplicate-ID, or legacy-ambiguity reasons. Reuse automatic repair only with a positively bound retained candidate. Offer confirmed removal only for exact resources whose ownership, containment, versions, and exclusive references can be verified. |
| Conflicting Versions | Preserve complete pair snapshots and show ambiguous candidates in vertically scrollable `Version 1`/`Version 2` tabs. Choose explicitly when times are equal, missing, cross-ordered, or the candidate is unpublished. Confirm before unchosen-version removal; require chosen-pair verification and both uploads before cleanup. Preserve unpairable/unknown versions. |
| Submitted edits | Consume M16's independent transaction states in the existing recovery destinations, with clearly distinguished submitted-edit sections and actions. Waiting/review state belongs in Pending Recordings; complete conflicts belong in Conflicting Versions; invalid external pairs belong in Incomplete Diary Snippets. Recording Retry/Remove never operates on a finished asset or its edit journal. |
| Navigation and privacy | Keep the four exact headings under All, Settings only under All, and Main notice routes consistent. Use approved custom template icons, accessible state/actions, inert content, bounded loading, and the nonforeground privacy cover across previews and dialogs. |

## Out of scope

No finished-asset deletion, automatic text merge, edit history, legacy migration or invented legacy grammar, blanket folder cleanup, shared/unknown-file deletion, new conflict ordering, automatic method switching, hosted Qwen, new notification policy, background inference, secure-erasure promise, or new root/recovery destination. Planning does not delete any user data or run recovery actions.

## Completion checklist

- [ ] A typed recovery inventory and action model spans queue, capture, catalog, and edit owners without duplicate entries. Bounded incremental discovery works directly from All, represents incomplete scans/access failures truthfully, and isolates malformed records while valid work continues.
- [ ] Pending and Failed screens show the correct durable stage/reason and only supported actions. Canonical P1-M5 messages/action labels are preserved; model installation/explicit selection rechecks readiness and never switches methods automatically.
- [ ] Manual transcription Retry creates a fresh revision using current Settings with no fixed count cap. Retry Verification and destination restoration preserve the managed draft/title/provenance and do not retranscribe or create duplicate assets. Queue-wide storage failure pauses safely with Retry.
- [ ] Restored/unbound recordings remain review-required before inference or save; Resume verifies owned playable audio and destination trust and clears obsolete attempt/candidate authority. M16 restored edits remain independently quarantined and retain their accepted body. Missing protected data is not mistaken for absence.
- [ ] Confirmed per-recording destination replacement validates a new iCloud capability, settles older accessors, durably increments the destination revision, and resumes only the affected work. Temporary outages, picker cancellation/rejection, account changes, and storage failure preserve the prior destination/candidate; active-folder choice never silently retargets work.
- [ ] Recording removal durably invalidates all inference/title/save/repair work under the shared mutation barrier, shows Cancelling until access settles and cleanup completes, and resumes after a crash. Fully verified completion before confirmation preserves the finished asset and explains completion. Late callbacks cannot publish afterward.
- [ ] Incomplete inspection preserves safe surviving text/audio within approved bounds and uses fresh read-only recovery leases. Repair requires retained ownership/content/version proof; uncertain, unsupported, unsafe, duplicate, or ambiguous resources stay preserved with reasons.
- [ ] Incomplete removal uses exact resource/version-bound confirmation and a crash-safe cleanup record. Changed/shared/unsafe resources and unrelated files survive; no external asset ID or recursive directory deletion supplies authority. Partial cleanup failure remains visible and retryable.
- [ ] Capture-owned, committed-asset, and submitted-edit conflicts share validated complete-pair policy through owner-specific capabilities. Equal/missing/cross-ordered times, shared-audio text conflicts, and unpublished local edits remain explicit choices; unknown or unpairable versions are preserved.
- [ ] Conflict tabs are separately openable, vertically scrollable, read-only, and accessible. Selection and removal confirmation are durable, idempotent, and bound to the reviewed snapshot/version set. Chosen publication, exact-version upload reports for both files, and final unchanged checks precede narrowly scoped obsolete-version/snapshot cleanup.
- [ ] Recovery UI handles stale navigation, refreshed rows, folder/account changes, foreground transitions, unsettled work, empty/loading/waiting states, and repeated inputs without losing pending data or leaking former-folder content. Main notices/counts update from the same state; M18 can observe whether pending work remains.
- [ ] English/Korean, largest Dynamic Type, VoiceOver, Reduce Motion, light/dark, small/large iPhone layouts, custom bitmap semantics, 44-point targets, inert rendering, and privacy/diagnostic checks pass for recovery views, tabs, confirmations, and replay.
- [ ] Focused state-machine, adapter, race, confinement, fault/relaunch, and presentation checks cover the [approach](milestone-17-recovery-architecture.md), including relevant [V-01–V-04, V-08–V-12](../security-review.md#adversarial-verification-matrix) scenarios. Command execution and first-pass failure analysis are delegated to `test_runner`.
- [ ] `make lint` passes for the implementation; record date/revision and concise result.
- [ ] `TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh` passes for the implementation; record destination/date/revision. If CoreSimulator is restricted, follow [the access-retry rule](../contribution-guide.md#coresimulator-access-in-restricted-shells); an unavailable gate stays unchecked.
- [ ] Target-iPhone [M17-D01–D10](milestone-17-recovery-device-evidence.md) have redacted passing observations; provider/version deletion, restore, protected storage, audio-session, and privacy behavior are not inferred from simulator results.
- [ ] Update affected product/UX/architecture/user docs and Phase 1 status with actual implementation evidence and inherited blockers. Do not mark the milestone Done while required checklist or gate evidence is missing.

## Evidence and result

Planning only. No M17 implementation, lint/build/test gate, recovery mutation, or target-iPhone scenario has run. The [approach](milestone-17-recovery-architecture.md) defines sequencing and failure tests; the [device record](milestone-17-recovery-device-evidence.md) leaves all observations open.
